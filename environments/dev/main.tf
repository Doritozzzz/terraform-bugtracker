locals {
  # Every name starts with "bugtracker-dev", so dev and prod never collide.
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
