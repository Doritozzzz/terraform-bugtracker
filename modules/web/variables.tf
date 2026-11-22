variable "name" {
  description = "Base name. Replicas are called <name>-1, <name>-2... and the image <name>."
  type        = string
}

variable "source_dir" {
  description = "Folder with the application and its Dockerfile. The image is rebuilt when any file in it changes."
  type        = string
}

variable "replicas" {
  description = "Number of identical containers to run."
  type        = number

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "port" {
  description = "Port the application listens on inside the container."
  type        = number
}

variable "networks" {
  description = "Names or IDs of the Docker networks every replica joins."
  type        = list(string)
}

variable "env" {
  description = "Environment variables for the application; null values are not set. Marked sensitive because it usually holds passwords."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "read_only" {
  description = "Read-only root filesystem. Set to false only if the application must write to disk."
  type        = bool
  default     = true
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
