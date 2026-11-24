locals {
  # Hosts the UI answers for: its published port and the gateway, if any.
  allowed_hosts = concat(
    var.port == null ? [] : ["127.0.0.1:${var.port}", "localhost:${var.port}"],
    var.public_url == null ? [] : [regex("^https?://([^/]+)/", var.public_url)[0]],
  )

  # Ports inside the container.
  smtp_port = 1025
  http_port = 8025
}

resource "docker_image" "mailpit" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# A test SMTP server: it accepts every email and shows it in a web UI instead
# of delivering it, the way a mail provider (e.g. Amazon SES) would be used in
# the cloud, but with no account or credentials, so it works on any machine.
resource "docker_container" "mailpit" {
  name  = var.name
  image = docker_image.mailpit.image_id

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

  # Hardening: unprivileged user (the image would otherwise run as root; its
  # ports are above 1024, so it needs no privilege), read-only filesystem, no
  # Linux capabilities and no privilege escalation.
  user          = "65534:65534"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # The mailbox lives in memory: it is a test inbox, emptied on restart.
  tmpfs = {
    "/tmp" = ""
  }

  # The UI only answers requests addressed to its public address, so a web
  # page cannot read the mailbox through DNS rebinding. No call to GitHub to
  # check for new versions.
  command = concat(
    length(local.allowed_hosts) == 0 ? [] : ["--allowed-hosts=${join(",", local.allowed_hosts)}"],
    ["--disable-version-check"],
  )

  # Served under the gateway path. An environment variable, not --webroot:
  # the healthcheck the image ships (mailpit readyz) reads it too, while the
  # flag would make it fail.
  env = var.public_url == null ? null : ["MP_WEBROOT=${regex("^https?://[^/]+(/.*)$", var.public_url)[0]}"]

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

  # The image already ships a healthcheck (mailpit readyz).

  wait = true
}
