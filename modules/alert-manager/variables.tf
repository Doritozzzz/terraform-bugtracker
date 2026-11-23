variable "name" {
  description = "Container name. It is also the hostname Prometheus sends alerts to."
  type        = string
}

variable "networks" {
  description = "Networks to join: the ones where Prometheus and the mail server are, plus one that is not internal if port is set."
  type        = list(string)
}

variable "port" {
  description = "Port on 127.0.0.1 for the web UI (list and silence alerts). Null keeps it unpublished."
  type        = number
  default     = null
}

variable "email" {
  description = "Optional email receiver: SMTP server as host:port (plain SMTP, e.g. a test server), sender and recipient."
  type = object({
    smarthost = string
    from      = string
    to        = string
  })
  default = null
}

variable "dashboard_url" {
  description = "Optional base URL of Grafana. Alerts with a dashboard annotation (a path) get a full link to it in their notifications."
  type        = string
  default     = null
}

variable "image" {
  description = "Alertmanager image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "prom/alertmanager:v0.35.0"
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
