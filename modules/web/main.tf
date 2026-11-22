locals {
  # One hash for all the files of the application: it changes only when the code changes.
  source_hash = sha1(join("", [for f in fileset(var.source_dir, "**") : filesha1("${var.source_dir}/${f}")]))
}

# The tag is the code hash: a code change means a new image, and every image
# can be traced back to the exact code it was built from.
resource "docker_image" "this" {
  name = "${var.name}:${substr(local.source_hash, 0, 12)}"

  build {
    context = abspath(var.source_dir)
  }
}

resource "docker_container" "this" {
  count = var.replicas

  name = "${var.name}-${count.index + 1}"
  # Docker's default hostname is the container ID. Using the name lets the
  # application report which replica answered in a readable way.
  hostname = "${var.name}-${count.index + 1}"
  image    = docker_image.this.image_id

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

  env = [for key, value in var.env : "${key}=${value}"]

  # Hardening: no Linux capabilities and no privilege escalation. The
  # unprivileged user and the healthcheck come from the Dockerfile.
  read_only     = var.read_only
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }
}
