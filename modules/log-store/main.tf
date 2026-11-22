locals {
  # Port inside the container.
  http_port = 3100
}

resource "docker_image" "loki" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Named volume: the stored logs survive when the container is replaced.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# Rendered to a file and bind-mounted read-only, like the load balancer config.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}.yaml")
  content = templatefile("${path.module}/loki.yaml.tftpl", {
    http_port       = local.http_port
    retention_hours = var.retention_days * 24
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "docker_container" "loki" {
  name  = var.name
  image = docker_image.loki.image_id

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
  # escalation. The image already runs as an unprivileged user.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  command = ["-config.file=/etc/loki/config.yaml"]

  volumes {
    host_path      = local_file.config.filename
    container_path = "/etc/loki/config.yaml"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/loki"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  # No healthcheck: the image is distroless (no shell, wget or curl), so
  # nothing inside it can call /ready. Prometheus checks it from outside.

  # The mounted file is read only at startup, so a new config needs a new container.
  lifecycle {
    replace_triggered_by = [local_file.config]
  }
}
