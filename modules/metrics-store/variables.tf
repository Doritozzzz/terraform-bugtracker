variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "networks" {
  description = "Networks to join: the ones where the scrape targets are, plus one that is not internal if port is set."
  type        = list(string)
}

variable "scrape_jobs" {
  description = "What to scrape every 15 s: a job name and its host:port targets. Optional: keep, a map of label => regex every stored series must match (e.g. to keep one environment from a shared exporter); honor_timestamps = false to ignore the timestamps an exporter attaches to its samples. Prometheus scrapes itself as job prometheus."
  type = list(object({
    name             = string
    targets          = list(string)
    keep             = optional(map(string), {})
    honor_timestamps = optional(bool)
  }))

  validation {
    condition = alltrue([
      for j in var.scrape_jobs : can(regex("^[a-zA-Z_][a-zA-Z0-9_-]*$", j.name)) && j.name != "prometheus" && length(j.targets) > 0
    ]) && length(distinct([for j in var.scrape_jobs : j.name])) == length(var.scrape_jobs)
    error_message = "Each job needs a unique name of letters, digits, _ or - (not \"prometheus\") and at least one target."
  }
}

variable "port" {
  description = "Port on 127.0.0.1 for the Prometheus web UI. Null keeps it unpublished."
  type        = number
  default     = null
}

variable "image" {
  description = "Prometheus image. Pinned to an exact version so every machine runs the same one."
  type        = string
  default     = "prom/prometheus:v3.16.0"
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
