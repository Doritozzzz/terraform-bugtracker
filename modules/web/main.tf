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

  name  = "${var.name}-${count.index + 1}"
  image = docker_image.this.image_id

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
