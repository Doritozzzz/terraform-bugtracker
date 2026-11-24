output "host" {
  description = "Hostname to reach the S3 API from containers on the same network."
  value       = docker_container.minio.name
}

output "port" {
  description = "S3 API port inside the network."
  value       = local.api_port
}

output "backend" {
  description = "host:port of the S3 API, ready to give to a load balancer."
  value       = "${docker_container.minio.name}:${local.api_port}"
}

output "health_path" {
  description = "Unauthenticated HTTP path that answers 200 while MinIO is alive."
  value       = "/minio/health/live"
}

output "bucket" {
  description = "Bucket name. Objects are served at /<bucket>/<file>."
  value       = var.bucket
}

output "console_url" {
  description = "URL people open for the console: console_url, or the published port. Null when neither is set."
  value       = var.console_url != null ? var.console_url : var.console_port == null ? null : "http://127.0.0.1:${var.console_port}"
}

output "console_backend" {
  description = "host:port of the web console inside the network, ready to give to a gateway."
  value       = "${docker_container.minio.name}:${local.console_port}"
}

output "root_user" {
  description = "Administrator user (console login)."
  value       = local.root_user
}

output "root_password" {
  description = "Generated administrator password (console login)."
  value       = random_password.root.result
  sensitive   = true
}
