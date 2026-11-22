variable "name" {
  description = "Container name."
  type        = string
}

variable "networks" {
  description = "Networks to join: the ones where the data sources are, plus one that is not internal to publish the port."
  type        = list(string)
}

variable "port" {
  description = "Port on 127.0.0.1 where Grafana is served."
  type        = number
}

variable "datasources" {
  description = "Data sources to provision: uid (fixed ID for dashboards), display name, Grafana type (e.g. prometheus, loki), URL, whether it is the default one and, optionally, json_data: type-specific settings (Grafana's jsonData) as JSON text, e.g. jsonencode({...}). Grafana expands $VAR in provisioning files, so a literal $ must be written $$."
  type = list(object({
    uid       = string
    name      = string
    type      = string
    url       = string
    default   = optional(bool, false)
    json_data = optional(string)
  }))

  validation {
    condition     = length([for ds in var.datasources : ds if ds.default]) <= 1
    error_message = "At most one data source can be the default."
  }

  validation {
    condition     = alltrue([for ds in var.datasources : ds.json_data == null ? true : can(jsondecode(ds.json_data))])
    error_message = "json_data must be JSON text, e.g. jsonencode({...})."
  }

  validation {
    condition     = length(distinct([for ds in var.datasources : ds.uid])) == length(var.datasources)
    error_message = "Every data source needs a different uid."
  }
}

variable "dashboards_dir" {
  description = "Optional folder with dashboard JSON files to provision. Null provisions none."
  type        = string
  default     = null
}

variable "home_dashboard" {
  description = "Optional file name (inside dashboards_dir) of the dashboard shown as the home page."
  type        = string
  default     = null

  validation {
    condition     = var.home_dashboard == null ? true : var.dashboards_dir != null
    error_message = "home_dashboard needs dashboards_dir."
  }
}

variable "image" {
  description = "Grafana image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "grafana/grafana:13.3.1"
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
