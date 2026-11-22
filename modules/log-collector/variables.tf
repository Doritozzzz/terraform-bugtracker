variable "name" {
  description = "Container name of the collector. The Docker API proxy is called <name>-docker-api."
  type        = string
}

variable "networks" {
  description = "Networks to join: the one where Loki can be reached."
  type        = list(string)
}

variable "push_url" {
  description = "Loki push URL (for example the push_url output of the log-store module)."
  type        = string
}

variable "container_filter" {
  description = "Docker labels a container must have, all of them, for its logs to be collected (e.g. environment = \"dev\")."
  type        = map(string)

  validation {
    condition     = length(var.container_filter) > 0
    error_message = "container_filter needs at least one label, otherwise every container on the host would be collected."
  }
}

variable "keep_labels" {
  description = "Docker labels copied to every log stream as Loki labels, to filter by them (e.g. service)."
  type        = list(string)
  default     = []

  # Loki label names; Docker labels with other characters would need renaming.
  validation {
    condition     = alltrue([for l in var.keep_labels : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", l))])
    error_message = "keep_labels may only contain letters, digits and _, and must not start with a digit."
  }
}

variable "image" {
  description = "Grafana Alloy image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "grafana/alloy:v1.22.0"
}

variable "proxy_image" {
  description = "Docker API proxy image. linuxserver only tags each weekly rebuild exactly, so that tag is pinned."
  type        = string
  default     = "lscr.io/linuxserver/socket-proxy:3.4.8-r0-ls107"
}

variable "restart" {
  description = "Docker restart policy of both containers: no, on-failure, always or unless-stopped. Null keeps the Docker default (no)."
  type        = string
  default     = null

  # Checked at plan time; Docker would only reject a typo while applying.
  validation {
    condition     = var.restart == null ? true : contains(["no", "on-failure", "always", "unless-stopped"], var.restart)
    error_message = "restart must be no, on-failure, always or unless-stopped."
  }
}

variable "memory" {
  description = "Memory limit of the collector in MB. Null means no limit."
  type        = number
  default     = null
}

variable "proxy_memory" {
  description = "Memory limit of the Docker API proxy in MB. Null means no limit."
  type        = number
  default     = null
}

variable "labels" {
  description = "Docker labels for both containers, e.g. environment and service, used by monitoring to filter them."
  type        = map(string)
  default     = {}
}
