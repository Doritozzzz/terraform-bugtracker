resource "docker_image" "postgres" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Generated once and kept in the Terraform state. PostgreSQL stores it in the
# data volume on the first start, so it must not change afterwards.
resource "random_password" "this" {
  length = 32
  # Letters and digits only: special characters can break connection strings.
  special = false
}

# Named volume: the data survives when the container is replaced.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

resource "docker_container" "postgres" {
  name  = var.name
  image = docker_image.postgres.image_id

  # Optional; all null (Docker defaults) unless the caller sets them.
  # memory_swap = memory means no swap: the limit is a hard one, and Docker
  # only accepts changing the limit of a running container if both change together.
  restart     = var.restart
  memory      = var.memory
  memory_swap = var.memory

  # Hardening: unprivileged user, read-only filesystem, no Linux capabilities
  # and no privilege escalation.
  user          = "postgres"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # Writable scratch space in memory, needed by PostgreSQL with a read-only filesystem.
  tmpfs = {
    "/tmp"                = ""
    "/var/run/postgresql" = ""
  }

  env = [
    "POSTGRES_DB=${var.database}",
    "POSTGRES_USER=${var.user}",
    "POSTGRES_PASSWORD=${random_password.this.result}",
  ]

  networks_advanced {
    name = var.network
  }

  # PostgreSQL 18 keeps its data in a versioned subdirectory of this path.
  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/postgresql"
  }

  # Bind mount, not `upload`: Docker cannot copy files into a read-only container.
  dynamic "volumes" {
    for_each = var.init_script == null ? [] : [abspath(var.init_script)]
    content {
      host_path      = volumes.value
      container_path = "/docker-entrypoint-initdb.d/init.sql"
      read_only      = true
    }
  }

  # Over TCP (-h 127.0.0.1): it fails until the server accepts network
  # connections, so the container is not healthy while init.sql is loading.
  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
    interval     = "5s"
    timeout      = "3s"
    retries      = 10
    start_period = "10s"
  }

  # terraform apply finishes only when the database is healthy, so whatever
  # depends on it starts afterwards.
  wait = true
}
