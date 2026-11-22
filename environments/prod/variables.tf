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
}

variable "lb_port" {
  description = "Port on 127.0.0.1 where the application is served."
  type        = number
}

variable "storage_console_port" {
  description = "Port on 127.0.0.1 where the MinIO console is served."
  type        = number
}
