locals {
  # Port inside the container.
  http_port = 3000

  # Grafana's default admin user; only its password is set.
  admin_user = "admin"
}

resource "docker_image" "grafana" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Generated once and kept in the Terraform state. Grafana only uses it to
# create the admin user on the first start (it is then stored in the data
# volume), so it must not change afterwards.
resource "random_password" "admin" {
  length = 32
  # Letters and digits only, so it can be typed or pasted anywhere.
  special = false
}

# Named volume: users, settings and anything saved from the UI survive when
# the container is replaced.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# Rendered to a file and bind-mounted read-only, like the load balancer config.
resource "local_file" "datasources" {
  filename = abspath("${path.root}/.generated/${var.name}-datasources.yaml")
  content = templatefile("${path.module}/datasources.yaml.tftpl", {
    datasources = var.datasources
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "docker_container" "grafana" {
  name  = var.name
  image = docker_image.grafana.image_id

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
  # escalation. The image already runs as the unprivileged grafana user.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # Plugins talk to Grafana through sockets they create here; without it
  # every bundled plugin fails to start.
  tmpfs = {
    "/tmp" = ""
  }

  # The home dashboard and the public URL, when given, are added at the end.
  # With root_url Grafana still serves from /: the gateway removes the path.
  env = concat([
    "GF_SECURITY_ADMIN_PASSWORD=${random_password.admin.result}",
    # Logs only to stdout, as JSON like the other services. The default also
    # writes log files, which would fail on the read-only filesystem.
    "GF_LOG_MODE=console",
    "GF_LOG_CONSOLE_FORMAT=json",
    # At the default info level Grafana logs a line for every query of every
    # panel (about 160 lines a minute with a dashboard open); warn keeps
    # problems only.
    "GF_LOG_LEVEL=warn",
    # Grafana 13.3 warns about an empty search manifest list on every poll,
    # forever (grafana/grafana#137058, moved to debug in 13.4).
    "GF_LOG_FILTERS=search-manifest-watcher:error",
    # The bundled plugins are used as they ship: nothing is downloaded from
    # grafana.com at startup, so every start runs the same code.
    "GF_PLUGINS_PREINSTALL_DISABLED=true",
    # No calls home: usage reports, update checks and the news feed are on by default.
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
    "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false",
    "GF_NEWS_NEWS_FEED_ENABLED=false",
    # On by default but deprecated: browsers removed the X-XSS-Protection
    # header, and Grafana itself recommends turning it off.
    "GF_SECURITY_X_XSS_PROTECTION=false",
  ], var.home_dashboard == null ? [] : ["GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/${var.home_dashboard}"], var.root_url == null ? [] : ["GF_SERVER_ROOT_URL=${var.root_url}"])

  volumes {
    host_path      = local_file.datasources.filename
    container_path = "/etc/grafana/provisioning/datasources/datasources.yaml"
    read_only      = true
  }

  # The dashboard files and the provider that loads them. Grafana watches the
  # folder, so editing a dashboard does not need a new container.
  dynamic "volumes" {
    for_each = var.dashboards_dir == null ? {} : {
      "/etc/grafana/provisioning/dashboards/dashboards.yaml" = abspath("${path.module}/dashboards.yaml")
      "/etc/grafana/dashboards"                              = abspath(var.dashboards_dir)
    }
    content {
      host_path      = volumes.value
      container_path = volumes.key
      read_only      = true
    }
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/grafana"
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
    test         = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${local.http_port}/api/health"]
    interval     = "5s"
    timeout      = "3s"
    start_period = "30s"
  }

  # terraform apply returns once Grafana is ready (about 20 s on a fresh volume).
  wait = true

  # Provisioning files are read only at startup, so a change needs a new container.
  lifecycle {
    replace_triggered_by = [local_file.datasources]
  }
}
