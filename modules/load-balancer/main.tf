locals {
  # Ports inside the container. Above 1024 because HAProxy runs as a non-root user.
  listen_port  = 8080
  metrics_port = 8405
}

resource "docker_image" "haproxy" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# The config is rendered to a file and its folder is bind-mounted read-only.
# The provider's `upload` block cannot be used: it copies into the container
# root, which is read-only. Each environment writes to its own folder, so dev
# and prod never share a file.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}/haproxy.cfg")
  content = templatefile("${path.module}/haproxy.cfg.tftpl", {
    listen_port  = local.listen_port
    metrics_port = local.metrics_port
    balance      = var.balance
    health_path  = var.health_path
    backends     = var.backends
    routes       = var.routes
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "docker_container" "haproxy" {
  name  = var.name
  image = docker_image.haproxy.image_id

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

  # Hardening: read-only filesystem, no Linux capabilities and no privilege
  # escalation. The image already runs as the unprivileged haproxy user.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  # The folder, not the file: a single mounted file stays tied to the file it
  # pointed to when the container started, so a rewritten config would never
  # be seen. The image command already reads haproxy.cfg from this folder.
  volumes {
    host_path      = dirname(local_file.config.filename)
    container_path = "/usr/local/etc/haproxy"
    read_only      = true
  }

  # Published on localhost only: the Docker default (0.0.0.0) would expose it
  # to the whole local network.
  ports {
    internal = local.listen_port
    external = var.port
    ip       = "127.0.0.1"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${local.metrics_port}/healthz"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply returns once HAProxy is accepting traffic.
  wait = true
}

# A new config (more replicas, other routes) is loaded without replacing the
# container. The image runs HAProxy in master-worker mode, where SIGUSR2 makes
# the master start new workers with the new config while the old ones finish
# their requests; the listening port stays open. The check comes first because
# a reload with an invalid file is only logged: this way apply fails, HAProxy
# keeps the old config and the next apply tries again. It also runs once after
# the container is created, a harmless reload of the same file. The signal is
# sent from inside (kill to PID 1, the master): docker kill --signal marks the
# container as stopped by hand, and Docker would then never restart it.
resource "terraform_data" "reload" {
  triggers_replace = local_file.config.content_sha256

  provisioner "local-exec" {
    command = "docker exec ${docker_container.haproxy.name} haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg && docker exec ${docker_container.haproxy.name} kill -USR2 1"
  }
}
