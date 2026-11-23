# High availability: every container restarts on its own if it exits (unless
# stopped by hand) and has a memory limit, so one leaking container cannot
# take the memory of the others. Limits come from measured usage plus margin.

locals {
  # Every name starts with "bugtracker-prod", so dev and prod never collide.
  name_prefix = "${var.project}-${var.environment}"

  # Labels shared by every container; each module adds its service. The
  # monitoring of this environment only collects containers with these labels.
  labels = {
    project     = var.project
    environment = var.environment
  }
}

# Network with access to the outside. Only containers that publish a port join it.
resource "docker_network" "frontend" {
  name = "${local.name_prefix}-frontend"
}

# Internal network: no access to the outside. Only the web, PostgreSQL and Redis join it.
resource "docker_network" "backend" {
  name     = "${local.name_prefix}-backend"
  internal = true
}

# Internal network between the load balancer and the web replicas, so the
# load balancer never reaches the database.
resource "docker_network" "app" {
  name     = "${local.name_prefix}-app"
  internal = true
}

# Internal network for the monitoring stack, apart from the application
# networks: the collectors and stores never reach the database or the web.
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
  restart       = "unless-stopped"
  memory        = 512
  labels        = merge(local.labels, { service = "database" })
}

module "cache" {
  source = "../../modules/cache"

  name    = "${local.name_prefix}-cache"
  network = docker_network.backend.name
  restart = "unless-stopped"
  memory  = 128
  labels  = merge(local.labels, { service = "cache" })
}

module "web" {
  source = "../../modules/web"

  name         = "${local.name_prefix}-web"
  source_dir   = "${path.module}/../../app"
  replicas     = var.web_replicas
  port         = 3000
  metrics_port = 9464
  # monitoring lets Prometheus read the metrics port, which the load balancer never forwards.
  networks = [docker_network.app.name, docker_network.backend.name, docker_network.monitoring.name]
  restart  = "unless-stopped"
  memory   = 256
  labels   = merge(local.labels, { service = "web" })

  # PORT, METRICS_PORT, REDIS_PORT and CACHE_TTL_SECONDS are omitted: the app
  # defaults (3000, 9464, 6379, 60 seconds) are the values used. log_level is not set in
  # terraform.tfvars, so LOG_LEVEL is skipped and the app default (info) applies.
  env = {
    NODE_ENV          = "production"
    LOG_LEVEL         = var.log_level
    DB_HOST           = module.database.host
    POSTGRES_DB       = module.database.database
    POSTGRES_USER     = module.database.user
    POSTGRES_PASSWORD = module.database.password
    CACHE_ENABLED     = "true"
    REDIS_HOST        = module.cache.host
    REDIS_PASSWORD    = module.cache.password
    # Only used to report whether the static files are being served.
    STORAGE_HEALTH_URL = "http://${module.storage.backend}${module.storage.health_path}"
    # Links shown in the System view; the app never calls them.
    GRAFANA_URL = module.dashboards.url
  }
}

module "load_balancer" {
  source = "../../modules/load-balancer"

  name        = "${local.name_prefix}-lb"
  backends    = module.web.backends
  health_path = "/live"
  port        = var.lb_port
  # frontend publishes the app, app reaches the replicas and storage, and
  # monitoring lets Prometheus read the metrics port (never published).
  networks = [docker_network.frontend.name, docker_network.app.name, docker_network.monitoring.name]
  restart  = "unless-stopped"
  memory   = 128
  labels   = merge(local.labels, { service = "load-balancer" })

  # The bucket is served under its own name (/static/...), so no path rewrite is needed.
  routes = [{
    name        = "storage"
    path_prefix = "/${module.storage.bucket}/"
    servers     = [module.storage.backend]
    health_path = module.storage.health_path
  }]
}

# Shared storage for the static files of the web: one copy for every replica,
# like S3 in the cloud. Only on the app network, where the load balancer and
# the web reach it. The admin console is a dev tool and is not published here,
# so MinIO stays off the frontend network and has no access to the outside.
module "storage" {
  source = "../../modules/object-storage"

  name       = "${local.name_prefix}-storage"
  networks   = [docker_network.app.name]
  bucket     = "static"
  source_dir = "${path.module}/../../static"
  restart    = "unless-stopped"
  memory     = 256
  labels     = merge(local.labels, { service = "storage" })
}

# Central log store: every container log of this environment ends up here.
module "log_store" {
  source = "../../modules/log-store"

  name     = "${local.name_prefix}-loki"
  networks = [docker_network.monitoring.name]
  restart  = "unless-stopped"
  memory   = 256
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
  restart          = "unless-stopped"
  memory           = 128
  proxy_memory     = 64
  labels           = merge(local.labels, { service = "log-collector" })
}

# CPU, memory, network and health of every container on the host.
module "container_metrics" {
  source = "../../modules/container-metrics"

  name        = "${local.name_prefix}-cadvisor"
  networks    = [docker_network.monitoring.name]
  keep_labels = ["project", "environment", "service"]
  restart     = "unless-stopped"
  memory      = 64
  labels      = merge(local.labels, { service = "container-metrics" })
}

# Collects and stores the metrics of this environment. Its web UI is not
# published in prod: Grafana is the way in.
module "metrics_store" {
  source = "../../modules/metrics-store"

  name     = "${local.name_prefix}-prometheus"
  networks = [docker_network.monitoring.name]

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
    { name = "alertmanager", targets = [module.alert_manager.target] },
  ]
  rules_dir       = "${path.module}/../../monitoring/alerts"
  external_labels = local.labels
  alertmanagers   = [module.alert_manager.target]

  restart = "unless-stopped"
  memory  = 256
  labels  = merge(local.labels, { service = "metrics-store" })
}

# Web UI over the metrics and logs of this environment.
module "dashboards" {
  source = "../../modules/dashboards"

  name = "${local.name_prefix}-grafana"
  # frontend only to publish its port on the host.
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = var.grafana_port

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

  restart = "unless-stopped"
  memory  = 512
  labels  = merge(local.labels, { service = "dashboards" })
}

# Test mail server: receives the alert emails and shows them in a web UI.
module "mail_catcher" {
  source = "../../modules/mail-catcher"

  name = "${local.name_prefix}-mailpit"
  # frontend only to publish its web UI on the host.
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = var.mail_port
  restart  = "unless-stopped"
  memory   = 64
  labels   = merge(local.labels, { service = "mail-catcher" })
}

# Groups the alerts of Prometheus and notifies them. Only prod notifies; dev
# evaluates the same rules without sending anything.
module "alert_manager" {
  source = "../../modules/alert-manager"

  name = "${local.name_prefix}-alertmanager"
  # frontend only to publish its web UI, where alerts can be listed and silenced.
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = var.alertmanager_port

  email = {
    smarthost = module.mail_catcher.smtp_address
    from      = "alertmanager@${local.name_prefix}.local"
    to        = "oncall@${local.name_prefix}.local"
  }
  dashboard_url = module.dashboards.url

  restart = "unless-stopped"
  memory  = 64
  labels  = merge(local.labels, { service = "alert-manager" })
}
