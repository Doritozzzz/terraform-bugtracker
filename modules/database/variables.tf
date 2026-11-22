variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "network" {
  description = "Name or ID of the Docker network the database joins."
  type        = string
}

variable "database" {
  description = "Name of the database created on the first start."
  type        = string
}

variable "user" {
  description = "Owner of the database."
  type        = string
}

variable "image" {
  description = "PostgreSQL image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "postgres:18.7-alpine"
}

variable "init_script" {
  description = "Optional path to a .sql file run only on the first start, while the data volume is empty."
  type        = string
  default     = null
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
