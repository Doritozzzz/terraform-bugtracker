variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "networks" {
  description = "Networks to join: the ones where the log collector and Grafana can reach it."
  type        = list(string)
}

variable "retention_days" {
  description = "Days logs are kept before Loki deletes them."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a whole number, 1 or more."
  }
}

variable "image" {
  description = "Loki image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "grafana/loki:3.7.10"
}

variable "restart" {
  description = "Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no)."
  type        = string
  default     = null

  # Checked at plan time; Docker would only reject a typo while applying.
  validation {
    condition     = var.restart == null ? true : contains(["no", "on-failure", "always", "unless-stopped"], var.restart)
    error_message = "restart must be no, on-failure, always or unless-stopped."
  }
}

variable "memory" {
  description = "Memory limit in MB. Null means no limit."
  type        = number
  default     = null
}

variable "labels" {
  description = "Docker labels for the container, e.g. environment and service, used by monitoring to filter it."
  type        = map(string)
  default     = {}
}
