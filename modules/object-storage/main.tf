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

  # Folder that init.sh uploads, mounted read-only: MinIO never changes it.
  volumes {
    host_path      = abspath(var.source_dir)
    container_path = "/source"
    read_only      = true
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

  # terraform apply waits until MinIO is healthy, so init.sh below can run.
  wait = true
}

# Prepares the bucket with init.sh (see the script) right after MinIO is
# healthy, and again whenever the files, the bucket, the policy, the header
# or the container change. Every object gets a Cache-Control header; without
# one, browsers guess how long to reuse a file without asking. A failed
# script fails the apply, and the next apply runs it again.
resource "terraform_data" "init" {
  triggers_replace = [docker_container.minio.id, local.source_hash, var.bucket, local.read_policy, var.cache_control]

  provisioner "local-exec" {
    command = "${path.module}/init.sh"
    # Run through bash, so the script needs no execute permission.
    interpreter = ["bash"]
    environment = {
      CONTAINER     = docker_container.minio.name
      API_PORT      = local.api_port
      BUCKET        = var.bucket
      POLICY        = local.read_policy
      CACHE_CONTROL = var.cache_control
    }
  }
}
