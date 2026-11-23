variable "name" {
  description = "Container name. It is also the SMTP hostname other containers send mail to."
  type        = string
}

variable "networks" {
  description = "Networks to join: the one where the senders are, plus one that is not internal to publish the web UI."
  type        = list(string)
}

variable "port" {
  description = "Port on 127.0.0.1 where the web UI with the received mail is served."
  type        = number
}

variable "image" {
  description = "Mailpit image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "axllent/mailpit:v1.34.0"
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
