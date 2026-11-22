locals {
  # Port inside the container.
  http_port = 8080
}

resource "docker_image" "cadvisor" {
  name = var.image
  # Pulled images are shared by every project and environment on the host:
  # deleting it on destroy would fail while another environment uses it.
  keep_locally = true
}

# cAdvisor reads the CPU, memory and network counters the kernel keeps for
# every container, plus its Docker health state, and exposes them for
# Prometheus. It sees every container on the host; Prometheus keeps only the
# ones it wants by their labels.
resource "docker_container" "cadvisor" {
  name  = var.name
  image = docker_image.cadvisor.image_id

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
  # escalation. The upstream instructions add --privileged and mount the whole
  # host root, /var/run, /var/lib/docker and /dev/disk; none of that is needed
  # for CPU, memory and network metrics, so only the three paths below are mounted.
  read_only     = true
  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
  }

  # docker_only skips the cgroups of host processes. Only the metrics that are
  # used are collected (the default set also probes disks that are not
  # mounted here). Every 15 s instead of every second: Prometheus reads them
  # every 15 s, and it costs about eight times less CPU.
  command = [
    "--docker_only=true",
    "--enable_metrics=cpu,memory,network",
    "--housekeeping_interval=15s",
    "--store_container_labels=false",
    "--whitelisted_container_labels=${join(",", var.keep_labels)}",
  ]

  # Kernel counters (cgroups) of every container.
  volumes {
    host_path      = "/sys"
    container_path = "/sys"
    read_only      = true
  }

  # Names, labels and health of the containers. These sockets give full
  # control of Docker (read-only mounts do not limit the API), which is why
  # this container has no published port and stays on an internal network.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  # Docker 29 keeps its containers in containerd; without this socket
  # cAdvisor does not recognise them as Docker containers.
  volumes {
    host_path      = "/run/containerd/containerd.sock"
    container_path = "/run/containerd/containerd.sock"
    read_only      = true
  }

  dynamic "networks_advanced" {
    for_each = var.networks
    content {
      name = networks_advanced.value
    }
  }

  # The image already ships a healthcheck.
}
