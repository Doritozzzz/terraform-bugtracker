# High availability: every container restarts on its own if it exits (unless
# stopped by hand) and has a memory limit, so one leaking container cannot
# take the memory of the others. Limits come from measured usage plus margin.

locals {
  # Every name starts with "bugtracker-prod", so dev and prod never collide.
  name_prefix = "${var.project}-${var.environment}"
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
  restart     = "unless-stopped"
  memory      = 512
}

module "cache" {
  source = "../../modules/cache"

  name    = "${local.name_prefix}-cache"
  network = docker_network.backend.name
  restart = "unless-stopped"
  memory  = 128
}

module "web" {
  source = "../../modules/web"

  name       = "${local.name_prefix}-web"
  source_dir = "${path.module}/../../app"
  replicas   = var.web_replicas
  port       = 3000
  networks   = [docker_network.app.name, docker_network.backend.name]
  restart    = "unless-stopped"
  memory     = 256

  # PORT, REDIS_PORT and CACHE_TTL_SECONDS are omitted: the app defaults
  # (3000, 6379, 60 seconds) are the values used.
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
  }
}

module "load_balancer" {
  source = "../../modules/load-balancer"

  name        = "${local.name_prefix}-lb"
  backends    = module.web.backends
  health_path = "/live"
  port        = var.lb_port
  networks    = [docker_network.frontend.name, docker_network.app.name]
  restart     = "unless-stopped"
  memory      = 128

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
  restart      = "unless-stopped"
  memory       = 256
}
