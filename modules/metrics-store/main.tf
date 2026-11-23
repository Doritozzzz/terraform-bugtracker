locals {
  # Port inside the container.
  http_port = 9090
}

resource "docker_image" "prometheus" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Named volume: the stored metrics survive when the container is replaced.
# Retention is Prometheus's default, 15 days.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# Rendered to a file and bind-mounted read-only, like the load balancer config.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}.yml")
  content = templatefile("${path.module}/prometheus.yml.tftpl", {
    http_port       = local.http_port
    scrape_jobs     = var.scrape_jobs
    external_labels = var.external_labels
    rules           = var.rules_dir != null
    alertmanagers   = var.alertmanagers
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

# Changes whenever a rule file changes. Prometheus reads rules only at startup,
# so the container is replaced to load them, like when the config changes.
resource "terraform_data" "rules" {
  input = var.rules_dir == null ? null : sha1(join("", [for f in fileset(var.rules_dir, "*.rules.yml") : filesha1("${var.rules_dir}/${f}")]))
}

resource "docker_container" "prometheus" {
  name  = var.name
  image = docker_image.prometheus.image_id

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
  # escalation. The image already runs as the unprivileged nobody user.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  # Mounted where the image command already looks for it, so no command is set.
  volumes {
    host_path      = local_file.config.filename
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  dynamic "volumes" {
    for_each = var.rules_dir == null ? [] : [abspath(var.rules_dir)]
    content {
      host_path      = volumes.value
      container_path = "/etc/prometheus/rules"
      read_only      = true
    }
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/prometheus"
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  # Published on localhost only: the Docker default (0.0.0.0) would expose it
  # to the whole local network.
  dynamic "ports" {
    for_each = var.port == null ? [] : [var.port]
    content {
      internal = local.http_port
      external = ports.value
      ip       = "127.0.0.1"
    }
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${local.http_port}/-/ready"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply waits until Prometheus is ready.
  wait = true

  # The mounted files are read only at startup, so a new config or rule needs a new container.
  lifecycle {
    replace_triggered_by = [local_file.config, terraform_data.rules]
  }
}
