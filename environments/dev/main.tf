locals {
  # Every name starts with "bugtracker-dev", so dev and prod never collide.
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

module "database" {
  source = "../../modules/database"

  name        = "${local.name_prefix}-db"
  network     = docker_network.backend.name
  database    = "tracker"
  user        = "tracker"
  init_script = "${path.module}/../../db/init.sql"
  labels      = merge(local.labels, { service = "database" })
}

module "web" {
  source = "../../modules/web"

  name       = "${local.name_prefix}-web"
  source_dir = "${path.module}/../../app"
  replicas   = var.web_replicas
  port       = 3000
  networks   = [docker_network.app.name, docker_network.backend.name]
  labels     = merge(local.labels, { service = "web" })

  # NODE_ENV, PORT and CACHE_ENABLED are omitted: the app defaults
  # (development, 3000, false) are already the dev values.
  env = {
    LOG_LEVEL         = var.log_level
    DB_HOST           = module.database.host
    POSTGRES_DB       = module.database.database
    POSTGRES_USER     = module.database.user
    POSTGRES_PASSWORD = module.database.password
    # Only used to report whether the static files are being served.
    STORAGE_HEALTH_URL = "http://${module.storage.backend}${module.storage.health_path}"
  }
}

module "load_balancer" {
  source = "../../modules/load-balancer"

  name        = "${local.name_prefix}-lb"
  backends    = module.web.backends
  health_path = "/live"
  port        = var.lb_port
  networks    = [docker_network.frontend.name, docker_network.app.name]
  labels      = merge(local.labels, { service = "load-balancer" })

  # The bucket is served under its own name (/static/...), so no path rewrite is needed.
  routes = [{
    name        = "storage"
    path_prefix = "/${module.storage.bucket}/"
    servers     = [module.storage.backend]
    health_path = module.storage.health_path
  }]
}

# Shared storage for the static files of the web: one copy for every replica,
# like S3 in the cloud. On the app network so the load balancer and the web
# reach it, and on frontend so its console can be published.
module "storage" {
  source = "../../modules/object-storage"

  name         = "${local.name_prefix}-storage"
  networks     = [docker_network.frontend.name, docker_network.app.name]
  bucket       = "static"
  source_dir   = "${path.module}/../../static"
  console_port = var.storage_console_port
  labels       = merge(local.labels, { service = "storage" })
}
