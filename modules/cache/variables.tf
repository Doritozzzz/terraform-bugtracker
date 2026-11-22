variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "network" {
  description = "Name or ID of the Docker network the cache joins."
  type        = string
}

variable "max_memory" {
  description = "Memory limit for cached data (Redis syntax, e.g. 64mb). The least recently used keys are evicted when it is full."
  type        = string
  default     = "64mb"
}

variable "image" {
  description = "Redis image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "redis:8.10.3-alpine"
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
  description = "Docker labels for the containers, e.g. environment and service, used by monitoring to filter them."
  type        = map(string)
  default     = {}
}
