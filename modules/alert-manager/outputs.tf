output "target" {
  description = "host:port where Prometheus sends alerts, and of the web UI for a gateway (inside the Docker network)."
  value       = "${docker_container.alertmanager.name}:${local.http_port}"
}

output "url" {
  description = "URL people open: external_url, or the published port. Null when neither is set."
  value       = var.external_url != null ? var.external_url : var.port == null ? null : "http://127.0.0.1:${var.port}"
}
