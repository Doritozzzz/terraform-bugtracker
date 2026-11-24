locals {
  # Port inside the container.
  http_port = 9090

  # Changes whenever a rule file changes, so the rules are reloaded too.
  rules_hash = var.rules_dir == null ? null : sha1(join("", [for f in fileset(var.rules_dir, "*.rules.yml") : filesha1("${var.rules_dir}/${f}")]))
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

# Rendered to a file whose folder is bind-mounted read-only, like the load
# balancer config.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}/prometheus.yml")
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

  # The folder, not the file: a single mounted file stays tied to the file it
  # pointed to when the container started, so a rewritten config would never
  # be seen. The image command already reads prometheus.yml from this folder.
  volumes {
    host_path      = dirname(local_file.config.filename)
    container_path = "/etc/prometheus"
    read_only      = true
  }

  # Outside /etc/prometheus: Docker cannot create a mount point inside a
  # read-only mounted folder.
  dynamic "volumes" {
    for_each = var.rules_dir == null ? [] : [abspath(var.rules_dir)]
    content {
      host_path      = volumes.value
      container_path = "/etc/prometheus-rules"
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
}

# A new config (more targets) or rule is loaded without replacing the
# container, so metrics and alerts never stop. SIGHUP makes Prometheus read
# its config and rule files again. promtool checks both first because an
# invalid file is only logged on reload: this way apply fails, Prometheus
# keeps the old ones and the next apply tries again. It also runs once after
# the container is created, a harmless reload of the same files.
resource "terraform_data" "reload" {
  triggers_replace = [local_file.config.content_sha256, local.rules_hash]

  provisioner "local-exec" {
    command = "docker exec ${docker_container.prometheus.name} promtool check config /etc/prometheus/prometheus.yml && docker kill --signal HUP ${docker_container.prometheus.name}"
  }
}
