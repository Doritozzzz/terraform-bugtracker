variable "project" {
  description = "Project name. First part of every Docker resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod). Second part of every Docker resource name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "web_replicas" {
  description = "Number of web replicas behind the load balancer."
  type        = number
}

variable "log_level" {
  description = "Application log level: debug, info, warn or error. Null keeps the app default (info)."
  type        = string
  default     = null

  # Checked at plan time; otherwise the app would only reject it when it starts, and exit.
  validation {
    condition     = var.log_level == null ? true : contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "log_level must be debug, info, warn or error."
  }
}

variable "lb_port" {
  description = "Port on 127.0.0.1 where the application is served."
  type        = number
}

variable "grafana_port" {
  description = "Port on 127.0.0.1 where Grafana is served."
  type        = number
}

variable "alertmanager_port" {
  description = "Port on 127.0.0.1 where the Alertmanager web UI is served."
  type        = number
}

variable "mail_port" {
  description = "Port on 127.0.0.1 where the test mailbox (Mailpit) is served."
  type        = number
}
