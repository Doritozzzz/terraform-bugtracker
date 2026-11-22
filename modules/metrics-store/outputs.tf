output "internal_url" {
  description = "URL of the Prometheus API inside the Docker network (for Grafana)."
  value       = "http://${docker_container.prometheus.name}:${local.http_port}"
}

output "url" {
  description = "URL of the Prometheus web UI on the host, or null when it is not published."
  value       = var.port == null ? null : "http://127.0.0.1:${var.port}"
}
