locals {
  # Ports inside the containers.
  proxy_port = 2375
  http_port  = 12345

  proxy_name = "${var.name}-docker-api"
}

# ------------------------------------------------------------ Docker API proxy
# The Docker socket gives full control of the host (it is equivalent to root),
# and mounting it read-only does not limit the API. The collector only needs to
# list containers and read their logs, so it talks to this proxy, which allows
# just those GET requests and rejects everything else with 403.

resource "docker_image" "proxy" {
  name = var.proxy_image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Private network: only the collector can reach the proxy.
resource "docker_network" "docker_api" {
  name     = local.proxy_name
  internal = true
}

resource "docker_container" "proxy" {
  name  = local.proxy_name
  image = docker_image.proxy.image_id

  # Same restart policy as the collector, which cannot work without it.
  restart     = var.restart
  memory      = var.proxy_memory
  memory_swap = var.proxy_memory

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
  # escalation. It runs as root only to open the socket, which belongs to root.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # The entrypoint writes the generated HAProxy config here at startup.
  tmpfs = {
    "/run" = ""
  }

  # Only what the collector uses. Writes (POST) are already denied by default.
  # Events are on by default but not needed. warning hides the line the proxy
  # would log for every API request.
  env = [
    "CONTAINERS=1",
    "NETWORKS=1",
    "ALLOW_LOGS=1",
    "EVENTS=0",
    "LOG_LEVEL=warning",
  ]

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.docker_api.name
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${local.proxy_port}/_ping"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply waits until the proxy answers, so the collector can use it.
  wait = true
}

# --------------------------------------------------------------- Collector

resource "docker_image" "alloy" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Named volume: Alloy records how far it has read each container's log, so a
# restart neither loses nor repeats lines.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# Rendered to a file and bind-mounted read-only, like the load balancer config.
resource "local_file" "config" {
  filename = abspath("${path.root}/.generated/${var.name}.alloy")
  content = templatefile("${path.module}/config.alloy.tftpl", {
    docker_host      = "tcp://${docker_container.proxy.name}:${local.proxy_port}"
    push_url         = var.push_url
    container_filter = var.container_filter
    keep_labels      = var.keep_labels
  })

  # The provider default is 0777 (writable by anyone).
  file_permission      = "0644"
  directory_permission = "0755"
}

resource "docker_container" "alloy" {
  name  = var.name
  image = docker_image.alloy.image_id

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

  # Hardening: unprivileged user that ships with the image (it would otherwise
  # start as root), read-only filesystem, no Linux capabilities and no
  # privilege escalation.
  user          = "alloy"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  # Same as the image command, plus listening on every interface (the default
  # is 127.0.0.1, unreachable for Prometheus) and no usage reports to Grafana Labs.
  command = [
    "run", "/etc/alloy/config.alloy",
    "--storage.path=/var/lib/alloy/data",
    "--server.http.listen-addr=0.0.0.0:${local.http_port}",
    "--disable-reporting",
  ]

  volumes {
    host_path      = local_file.config.filename
    container_path = "/etc/alloy/config.alloy"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/alloy/data"
  }

  networks_advanced {
    name = docker_network.docker_api.name
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  # The image has no curl or wget; bash sends the HTTP request itself.
  healthcheck {
    test     = ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${local.http_port} && printf 'GET /-/ready HTTP/1.0\\r\\n\\r\\n' >&3 && head -n 1 <&3 | grep -q ' 200 '"]
    interval = "5s"
    timeout  = "3s"
  }

  # The mounted file is read only at startup, so a new config needs a new container.
  lifecycle {
    replace_triggered_by = [local_file.config]
  }
}
