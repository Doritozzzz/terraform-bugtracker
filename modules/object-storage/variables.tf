variable "name" {
  description = "Container name. It is also the hostname other containers use to connect."
  type        = string
}

variable "networks" {
  description = "Networks to join. Publishing the console needs one that is not internal."
  type        = list(string)
}

variable "bucket" {
  description = "Bucket created on start. Anonymous users can download its objects, nothing else."
  type        = string

  # S3 naming rules, checked at plan time instead of failing inside the init container.
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be 3-63 characters: lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }
}

variable "source_dir" {
  description = "Folder uploaded to the bucket. The upload runs again whenever any file in it changes."
  type        = string
}

variable "console_port" {
  description = "Port on 127.0.0.1 for the MinIO web console. Null keeps the console unpublished."
  type        = number
  default     = null
}

variable "image" {
  description = "MinIO image. The official images can no longer be pulled; Chainguard only tags latest, so it is pinned by digest."
  type        = string
  default     = "cgr.dev/chainguard/minio@sha256:548147b5fc95a67e3e45285dff7e0e50326c3eb1977c6218039461771156c5e7"
}

variable "restart" {
  description = "Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no)."
  type        = string
  default     = null
}

variable "memory" {
  description = "Memory limit in MB. Null means no limit."
  type        = number
  default     = null
}
