locals {
  # Ports inside the container. Above 1024 because HAProxy runs as a non-root user.
  listen_port = 8080
  health_port = 8405
}

resource "docker_image" "haproxy" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Generated once and kept in the Terraform state.
resource "random_password" "this" {
  length = 24
  # Letters and digits only: easy to type, and never needs escaping in the config.
  special = false
}

# Rendered like the load balancer config: its folder is bind-mounted read-only.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}/haproxy.cfg")
  content = templatefile("${path.module}/haproxy.cfg.tftpl", {
    listen_port = local.listen_port
    health_port = local.health_port
    user        = var.user
    routes      = var.routes
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

# The index page, in the same mounted folder. HAProxy keeps it in a buffer of
# 16 KB, so it stays a small page with inline CSS and no scripts.
resource "local_file" "index" {
  filename = "${dirname(local_file.config.filename)}/index.html"
  content = templatefile("${path.module}/index.html.tftpl", {
    title       = var.title
    environment = var.environment
    user        = var.user
    routes      = var.routes
    # One section per group, in the order the routes first use it.
    groups = distinct([for r in var.routes : r.group])
    # Colors of the initial shown when a route has no icon, taken in turn so
    # neighbouring cards differ.
    colors = ["#f46800", "#e6522c", "#7c3aed", "#0ea5e9", "#c72e49", "#16a34a"]
  })

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

  # Read by the config, so the password is not written to the mounted file.
  env = ["ADMIN_PASSWORD=${random_password.this.result}"]

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
    test     = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${local.health_port}/healthz"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply returns once the gateway is accepting traffic.
  wait = true

  # HAProxy refuses to start if the page in its config is missing.
  depends_on = [local_file.index]
}

# A new route or page is loaded without replacing the container, like in the load
# balancer: the config is checked, then SIGUSR2 goes to the master (PID 1)
# from inside, because docker kill --signal would turn off the restart policy.
resource "terraform_data" "reload" {
  # The page is also read only on load, so a change to it needs a reload too.
  triggers_replace = [local_file.config.content_sha256, local_file.index.content_sha256]

  provisioner "local-exec" {
    command = "docker exec ${docker_container.haproxy.name} haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg && docker exec ${docker_container.haproxy.name} kill -USR2 1"
  }
}
