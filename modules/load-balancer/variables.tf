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
