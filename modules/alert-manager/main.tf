locals {
  # Port inside the container.
  http_port = 9093

  # Address of the web UI, used in its links and those of the notifications.
  # Behind a gateway the routes stay at /, so the healthcheck and Prometheus
  # are unchanged.
  web_flags = (
    var.external_url != null ? ["--web.external-url=${var.external_url}", "--web.route-prefix=/"] :
    var.port != null ? ["--web.external-url=http://127.0.0.1:${var.port}"] : []
  )
}

resource "docker_image" "alertmanager" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Named volume: silences and the record of what was already notified survive
# when the container is replaced, so nothing is sent twice.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# Rendered to files and bind-mounted read-only, like the load balancer config.
resource "local_sensitive_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}.yml")
  content = templatefile("${path.module}/alertmanager.yml.tftpl", {
    email    = var.email
    telegram = var.telegram
  })

  # The provider default is 0700 (owner only). It must stay readable by the
  # nobody user of the container; with a Telegram receiver it holds the bot
  # token, so it lives in the ignored .generated folder, like the state.
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "local_file" "templates" {
  filename = abspath("${path.root}/.generated/${var.name}.tmpl")
  content = templatefile("${path.module}/notification.tmpl.tftpl", {
    dashboard_url = var.dashboard_url == null ? null : trimsuffix(var.dashboard_url, "/")
  })

  file_permission      = "0644"
  directory_permission = "0755"
}

resource "docker_container" "alertmanager" {
  name  = var.name
  image = docker_image.alertmanager.image_id

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

  # Same as the image command, plus the address of its web UI and no cluster
  # port: with a single instance there are no peers to talk to.
  command = concat([
    "--config.file=/etc/alertmanager/alertmanager.yml",
    "--storage.path=/alertmanager",
    "--cluster.listen-address=",
  ], local.web_flags)

  volumes {
    host_path      = local_sensitive_file.config.filename
    container_path = "/etc/alertmanager/alertmanager.yml"
    read_only      = true
  }

  volumes {
    host_path      = local_file.templates.filename
    container_path = "/etc/alertmanager/notification.tmpl"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/alertmanager"
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

  # terraform apply waits until Alertmanager is ready to receive alerts.
  wait = true

  # The mounted files are read only at startup, so a change needs a new container.
  lifecycle {
    replace_triggered_by = [local_sensitive_file.config, local_file.templates]
  }
}
