locals {
  # Every name starts with "bugtracker-dev", so dev and prod never collide.
  name_prefix = "${var.project}-${var.environment}"

  # Labels shared by every container; each module adds its service. The
  # monitoring of this environment only collects containers with these labels.
  labels = {
    project     = var.project
    environment = var.environment
  }

  # The admin gateway; each tool builds its links with its path under it.
  admin_url = "http://127.0.0.1:${var.admin_port}"
}

# Network with access to the outside, for the only two containers that
# publish a port: the load balancer (the app) and the admin gateway.
resource "docker_network" "frontend" {
  name = "${local.name_prefix}-frontend"
}

# Internal network of the admin tools: only people reach it, and only through
# the admin gateway. The tools keep their data flows on app and monitoring.
resource "docker_network" "admin" {
  name     = "${local.name_prefix}-admin"
  internal = true
}

# Internal network: no access to the outside. Only the web, PostgreSQL and Redis join it.
resource "docker_network" "backend" {
  name     = "${local.name_prefix}-backend"
  internal = true
}

# Internal network between the load balancer and the web replicas, so the
# load balancer never reaches the database. Prometheus joins it too, to read
# their metrics. It is the only network the load balancer and the replicas
# share: with two in common, Docker's DNS would answer either address and
# user traffic would also flow through the monitoring network.
resource "docker_network" "app" {
  name     = "${local.name_prefix}-app"
  internal = true
}

# Internal network for the monitoring stack, apart from the application
# networks: the collectors, Loki, Grafana and Alertmanager never reach the
# database or the web.
resource "docker_network" "monitoring" {
  name     = "${local.name_prefix}-monitoring"
  internal = true
}

module "database" {
  source = "../../modules/database"

  name        = "${local.name_prefix}-db"
  network     = docker_network.backend.name
  database    = "tracker"
  user        = "tracker"
  init_script = "${path.module}/../../db/init.sql"

  # The slowest normal query (a search with no match over 50,000 rows) takes
  # about 110 ms, so only real problems such as load or locks reach 500 ms.
  slow_query_ms = 500
  labels        = merge(local.labels, { service = "database" })
}

module "web" {
  source = "../../modules/web"

  name         = "${local.name_prefix}-web"
  source_dir   = "${path.module}/../../app"
  replicas     = var.web_replicas
  port         = 3000
  metrics_port = 9464
  # Prometheus reads the metrics port over app; the load balancer never forwards it.
  networks = [docker_network.app.name, docker_network.backend.name]
  labels   = merge(local.labels, { service = "web" })

  # NODE_ENV, PORT, METRICS_PORT and CACHE_ENABLED are omitted: the app
  # defaults (development, 3000, 9464, false) are already the dev values.
  env = {
    LOG_LEVEL         = var.log_level
    DB_HOST           = module.database.host
    POSTGRES_DB       = module.database.database
    POSTGRES_USER     = module.database.user
    POSTGRES_PASSWORD = module.database.password
    # Only used to report whether the images are being served.
    STORAGE_HEALTH_URL = "http://${module.storage.backend}${module.storage.health_path}"
    # Links shown in the System view, through the admin gateway; the app never calls them.
    GRAFANA_URL    = "${local.admin_url}/grafana"
    PROMETHEUS_URL = module.metrics_store.url
  }
}

module "load_balancer" {
  source = "../../modules/load-balancer"

  name        = "${local.name_prefix}-lb"
  backends    = module.web.backends
  health_path = "/live"
  port        = var.lb_port
  # frontend publishes the app; app reaches the replicas and storage, and lets
  # Prometheus read the metrics port (never published).
  networks = [docker_network.frontend.name, docker_network.app.name]
  labels   = merge(local.labels, { service = "load-balancer" })

  # The bucket is served under its own name (/images/...), so no path rewrite is needed.
  routes = [{
    name        = "storage"
    path_prefix = "/${module.storage.bucket}/"
    servers     = [module.storage.backend]
    health_path = module.storage.health_path
  }]
}

# Shared storage for the images of the web: one copy for every replica,
# like S3 in the cloud. On the app network so the load balancer and the web
# reach it, and on admin for its console.
module "storage" {
  source = "../../modules/object-storage"

  name        = "${local.name_prefix}-storage"
  networks    = [docker_network.app.name, docker_network.admin.name]
  bucket      = "images"
  source_dir  = "${path.module}/../../images"
  console_url = "${local.admin_url}/minio/"
  labels      = merge(local.labels, { service = "storage" })
}

# Central log store: every container log of this environment ends up here.
module "log_store" {
  source = "../../modules/log-store"

  name     = "${local.name_prefix}-loki"
  networks = [docker_network.monitoring.name]
  labels   = merge(local.labels, { service = "log-store" })
}

# Ships the logs of this environment's containers (and only those) to Loki.
module "log_collector" {
  source = "../../modules/log-collector"

  name             = "${local.name_prefix}-alloy"
  networks         = [docker_network.monitoring.name]
  push_url         = module.log_store.push_url
  container_filter = local.labels
  keep_labels      = ["environment", "service"]
  labels           = merge(local.labels, { service = "log-collector" })
}

# CPU, memory, network and health of every container on the host.
module "container_metrics" {
  source = "../../modules/container-metrics"

  name        = "${local.name_prefix}-cadvisor"
  networks    = [docker_network.monitoring.name]
  keep_labels = ["project", "environment", "service"]
  labels      = merge(local.labels, { service = "container-metrics" })
}

# Collects and stores the metrics of this environment.
module "metrics_store" {
  source = "../../modules/metrics-store"

  name = "${local.name_prefix}-prometheus"
  # app to scrape the load balancer and the replicas; admin for its web UI.
  networks     = [docker_network.monitoring.name, docker_network.app.name, docker_network.admin.name]
  external_url = "${local.admin_url}/prometheus/"

  scrape_jobs = [
    {
      name    = "cadvisor"
      targets = [module.container_metrics.metrics_target]
      # cAdvisor reports every container on the host: keep only this
      # environment's, by the labels it exports as container_label_<name>.
      keep = { for k, v in local.labels : "container_label_${k}" => v }
      # cAdvisor stamps its samples with its own time, which stops Prometheus
      # from marking a stopped container's series as gone: it would linger
      # for 5 minutes. Using the scrape time, it disappears on the next scrape.
      honor_timestamps = false
    },
    { name = "web", targets = module.web.metrics_targets },
    { name = "haproxy", targets = [module.load_balancer.metrics_target] },
    { name = "loki", targets = [module.log_store.metrics_target] },
    { name = "alloy", targets = [module.log_collector.metrics_target] },
  ]
  # Rules are evaluated here too, so a rule can be tried in dev before prod;
  # only prod sends notifications.
  rules_dir       = "${path.module}/../../monitoring/alerts"
  external_labels = local.labels

  labels = merge(local.labels, { service = "metrics-store" })
}

# Web UI over the metrics and logs of this environment.
module "dashboards" {
  source = "../../modules/dashboards"

  name = "${local.name_prefix}-grafana"
  # monitoring to read the data sources; admin for its web UI.
  networks = [docker_network.monitoring.name, docker_network.admin.name]
  root_url = "${local.admin_url}/grafana/"

  datasources = [
    { uid = "prometheus", name = "Prometheus", type = "prometheus", url = module.metrics_store.internal_url, default = true },
    {
      uid  = "loki"
      name = "Loki"
      type = "loki"
      url  = module.log_store.internal_url
      json_data = jsonencode({
        # Turns the request ID of a log line into a link that searches every
        # log line of that request (load balancer and replica). "$$$" writes a
        # literal "$$" in the file, which Grafana reads as one "$".
        derivedFields = [{
          name            = "requestId"
          matcherRegex    = "\"requestId\": ?\"([0-9a-f-]{36})\""
          datasourceUid   = "loki"
          url             = "{environment=~\".+\"} |= \"$$${__value.raw}\""
          urlDisplayLabel = "All log lines of this request"
        }]
      })
    },
  ]
  dashboards_dir = "${path.module}/../../monitoring/dashboards"
  home_dashboard = "status.json"

  labels = merge(local.labels, { service = "dashboards" })
}

# The only way in to the admin tools: one port with a login, every tool under
# its path. frontend to publish the port, admin to reach the tools.
module "admin_gateway" {
  source = "../../modules/admin-gateway"

  name     = "${local.name_prefix}-admin"
  port     = var.admin_port
  networks = [docker_network.frontend.name, docker_network.admin.name]
  routes = [
    { name = "grafana", path_prefix = "/grafana/", server = module.dashboards.backend },
    { name = "prometheus", path_prefix = "/prometheus/", server = module.metrics_store.backend },
    { name = "minio", path_prefix = "/minio/", server = module.storage.console_backend },
  ]
  labels = merge(local.labels, { service = "admin-gateway" })
}
