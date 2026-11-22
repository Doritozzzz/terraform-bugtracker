locals {
  # Ports inside the container.
  api_port     = 9000
  console_port = 9001

  root_user = "admin"

  # One hash for all the files to upload: it changes only when a file changes.
  source_hash = sha1(join("", [for f in fileset(var.source_dir, "**") : filesha1("${var.source_dir}/${f}")]))

  # Anonymous users may only download objects. MinIO's built-in "download"
  # policy would also let anyone list the bucket contents.
  read_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = ["*"] }
      Action    = ["s3:GetObject"]
      Resource  = ["arn:aws:s3:::${var.bucket}/*"]
    }]
  })
}

resource "docker_image" "minio" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# Generated once and kept in the Terraform state. MinIO stores it in the data
# volume on the first start, so it must not change afterwards.
resource "random_password" "root" {
  length = 32
  # Letters and digits only, so it can go inside a URL without escaping.
  special = false
}

# Named volume: the objects survive when the container is replaced.
resource "docker_volume" "data" {
  name = "${var.name}-data"
}

resource "docker_container" "minio" {
  name  = var.name
  image = docker_image.minio.image_id

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

  # Hardening: read-only filesystem, no Linux capabilities and no privilege
  # escalation. The image already runs as an unprivileged user.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  # Scratch space in memory, also used by mc in the healthcheck.
  tmpfs = {
    "/tmp" = ""
  }

  env = [
    "MINIO_ROOT_USER=${local.root_user}",
    "MINIO_ROOT_PASSWORD=${random_password.root.result}",
  ]

  # Fixed console port; otherwise MinIO picks a random one on every start.
  command = ["server", "/data", "--console-address", ":${local.console_port}"]

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  # Published on localhost only: the Docker default (0.0.0.0) would expose it
  # to the whole local network.
  dynamic "ports" {
    for_each = var.console_port == null ? [] : [var.console_port]
    content {
      internal = local.console_port
      external = ports.value
      ip       = "127.0.0.1"
    }
  }

  # mc ready calls MinIO's unauthenticated health endpoint, so no password is
  # needed here. mc keeps a config folder, which must live in the tmpfs.
  healthcheck {
    test     = ["CMD-SHELL", "MC_CONFIG_DIR=/tmp/.mc MC_HOST_local=http://127.0.0.1:${local.api_port} mc ready local"]
    interval = "5s"
    timeout  = "3s"
  }

  # terraform apply waits until MinIO is healthy, so the upload below can run.
  wait = true
}

# Changes only when a file to upload changes; it replaces the init container below.
resource "terraform_data" "source" {
  input = local.source_hash
}

# One-shot container (same image, which also ships the mc client): creates the
# bucket, applies the read-only policy and mirrors source_dir into it, so the
# bucket ends up with exactly the files of the folder. Every object gets a
# Cache-Control header; without one, browsers guess how long to reuse a file
# without asking. It runs on creation and again whenever the files, the
# bucket, the policy or the header change.
resource "docker_container" "init" {
  name  = "${var.name}-init"
  image = docker_image.minio.image_id

  # Run to completion and wait for it instead of keeping it running.
  must_run = false
  attach   = true

  log_driver    = "local"
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }
  tmpfs = {
    "/tmp" = ""
  }

  # MC_HOST_<alias> defines the "minio" alias without writing a config file.
  env = [
    "MC_CONFIG_DIR=/tmp/.mc",
    "MC_HOST_minio=http://${local.root_user}:${random_password.root.result}@${docker_container.minio.name}:${local.api_port}",
    "BUCKET=${var.bucket}",
    "POLICY=${local.read_policy}",
    "CACHE_CONTROL=${var.cache_control}",
  ]

  entrypoint = ["bash", "-c"]
  command = [<<-EOT
    set -eu
    mc mb --ignore-existing "minio/$BUCKET"
    printf '%s' "$POLICY" > /tmp/policy.json
    mc anonymous set-json /tmp/policy.json "minio/$BUCKET"
    # cp uploads every file, so the header is applied even to unchanged files
    # (mirror skips those); mirror --remove then deletes files no longer in the folder.
    mc cp --recursive --attr "Cache-Control=$CACHE_CONTROL" /source/ "minio/$BUCKET"
    mc mirror --remove /source "minio/$BUCKET"
  EOT
  ]

  volumes {
    host_path      = abspath(var.source_dir)
    container_path = "/source"
    read_only      = true
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.source]

    # Without this a failed upload would still count as a successful apply.
    postcondition {
      condition     = self.exit_code == 0
      error_message = "Uploading to the bucket failed: see docker logs ${var.name}-init."
    }
  }
}
