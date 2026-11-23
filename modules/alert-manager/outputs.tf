output "target" {
  description = "host:port where Prometheus sends alerts (inside the Docker network)."
  value       = "${docker_container.alertmanager.name}:${local.http_port}"
}

output "url" {
  description = "URL of the web UI on the host, or null when it is not published."
  value       = var.port == null ? null : "http://127.0.0.1:${var.port}"
}
