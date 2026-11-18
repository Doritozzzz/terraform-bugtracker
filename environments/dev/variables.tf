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
