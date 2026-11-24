variable "name" {
  description = "Container name of the gateway."
  type        = string
}

variable "port" {
  description = "Port published on 127.0.0.1 of the host: the only way in to the admin tools."
  type        = number
}

variable "networks" {
  description = "Networks to join: one that can publish ports and the admin network where the tools listen."
  type        = list(string)
}

variable "routes" {
  description = "One admin tool per path prefix, shown on the index page as a card with its optional description and icon (a URL, usually the tool's own logo under its prefix; without it, its initial), under its optional group heading. strip_prefix removes the prefix before forwarding, for tools that know their public path but serve from /; set it to false for tools that serve under the prefix themselves."
  type = list(object({
    name         = string
    path_prefix  = string
    server       = string
    strip_prefix = optional(bool, true)
    description  = optional(string)
    group        = optional(string)
    icon         = optional(string)
  }))

  validation {
    condition = length(var.routes) > 0 && alltrue([
      for r in var.routes : can(regex("^[a-z0-9_-]+$", r.name)) && r.name != "index" && can(regex("^/[a-z0-9_-]+/$", r.path_prefix))
    ])
    error_message = "At least one route. Each needs a name of lowercase letters, digits, _ or - (not \"index\") and a path_prefix like /grafana/ (one segment, slashes on both sides)."
  }
}

variable "title" {
  description = "Name shown at the top of the index page, e.g. the project."
  type        = string
  default     = "Admin"
}

variable "environment" {
  description = "Environment shown as a badge next to the title, so it is clear which one is open; prod is shown in red. Null: no badge."
  type        = string
  default     = null
}

variable "user" {
  description = "User name of the login."
  type        = string
  default     = "admin"

  # HTTP basic auth separates user and password with a colon.
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.user))
    error_message = "user can only have letters, digits, _, . or -."
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
  description = "Docker labels for the container, e.g. environment and service, used by monitoring to filter it."
  type        = map(string)
  default     = {}
}
