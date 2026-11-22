variable "name" {
  description = "Container name of the load balancer."
  type        = string
}

variable "backends" {
  description = "Servers to balance, as host:port (for example the backends output of the web module)."
  type        = list(string)

  validation {
    condition     = length(var.backends) > 0
    error_message = "backends needs at least one host:port."
  }
}

variable "health_path" {
  description = "HTTP path HAProxy calls on every backend to know if it is alive."
  type        = string
}

variable "port" {
  description = "Port published on 127.0.0.1 of the host."
  type        = number
}

variable "networks" {
  description = "Networks to join: one that reaches the backends and one that can publish ports."
  type        = list(string)
}

variable "routes" {
  description = "Extra backends chosen by path prefix (e.g. /static/ to object storage). Anything else goes to backends."
  type = list(object({
    name        = string
    path_prefix = string
    servers     = list(string)
    health_path = string
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.routes : can(regex("^[a-z0-9_-]+$", r.name)) && r.name != "app" && startswith(r.path_prefix, "/") && length(r.servers) > 0
    ])
    error_message = "Each route needs a name of lowercase letters, digits, _ or - (not \"app\"), a path_prefix starting with / and at least one server."
  }
}

variable "balance" {
  description = "HAProxy balancing algorithm."
  type        = string
  # static-rr alternates strictly and puts a recovered server back in rotation
  # at once; roundrobin can take many requests to re-integrate it.
  default = "static-rr"

  validation {
    condition     = contains(["static-rr", "roundrobin", "leastconn", "first", "source"], var.balance)
    error_message = "balance must be static-rr, roundrobin, leastconn, first or source."
  }
}

variable "image" {
  description = "HAProxy image (3.4 is the current LTS branch)."
  type        = string
  default     = "haproxy:3.4.7-alpine"
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
