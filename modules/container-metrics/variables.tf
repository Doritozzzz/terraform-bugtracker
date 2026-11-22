variable "name" {
  description = "Container name. It is also the hostname Prometheus uses to scrape it."
  type        = string
}

variable "networks" {
  description = "Networks to join: the one where Prometheus can reach it."
  type        = list(string)
}

variable "keep_labels" {
  description = "Docker labels exported with every metric, as container_label_<name>. No other label or environment variable is exported, so secrets never become metric labels."
  type        = list(string)
  default     = []
}

variable "image" {
  description = "cAdvisor image. Published on ghcr.io since v0.53; pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "ghcr.io/google/cadvisor:v0.61.1"
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
