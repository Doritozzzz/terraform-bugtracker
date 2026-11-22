resource "docker_image" "redis" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Generated once and kept in the Terraform state.
resource "random_password" "this" {
  length = 32
  # Letters and digits only, so it never needs escaping in the shell command below.
  special = false
}

resource "docker_container" "redis" {
  name  = var.name
  image = docker_image.redis.image_id

  # Optional; all null (Docker defaults) unless the caller sets them.
  # memory_swap = memory means no swap: the limit is a hard one, and Docker
  # only accepts changing the limit of a running container if both change together.
  restart     = var.restart
  memory      = var.memory
  memory_swap = var.memory

  # Docker's default json-file driver never rotates, so logs grow until the
  # disk is full. The local driver rotates and compresses by default (5 files
  # of 20 MB per container); docker logs and the Docker API still read it.
  log_driver = "local"

  # Optional metadata, e.g. to tell environments and services apart in monitoring.
  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Hardening: unprivileged user from the start (the image would otherwise
  # start as root and drop privileges itself), read-only filesystem, no Linux
  # capabilities and no privilege escalation.
  user          = "redis"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # Working directory of the image. In memory: a cache never writes to disk.
  tmpfs = {
    "/data" = ""
  }

  env = ["REDIS_PASSWORD=${random_password.this.result}"]

  # The shell expands the password from the environment, so it is not
  # repeated in the container command. Pure cache: snapshots are turned off
  # (the append-only file is already off by default) and the least recently
  # used keys are evicted when max_memory is reached.
  command = [
    "sh", "-c",
    "exec redis-server --requirepass \"$REDIS_PASSWORD\" --save '' --maxmemory ${var.max_memory} --maxmemory-policy allkeys-lru",
  ]

  networks_advanced {
    name = var.network
  }

  # REDISCLI_AUTH passes the password to redis-cli without putting it in the
  # process arguments.
  healthcheck {
    test     = ["CMD-SHELL", "REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli -h 127.0.0.1 ping | grep -q PONG"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply finishes only when Redis is healthy, so the web starts afterwards.
  wait = true
}
