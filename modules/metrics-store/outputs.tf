output "internal_url" {
  description = "URL of the Prometheus API inside the Docker network (for Grafana)."
  value       = "http://${docker_container.prometheus.name}:${local.http_port}"
}

output "url" {
  description = "URL people open: external_url, or the published port. Null when neither is set."
  value       = var.external_url != null ? var.external_url : var.port == null ? null : "http://127.0.0.1:${var.port}"
}

output "backend" {
  description = "host:port of the web UI inside the network, ready to give to a gateway."
  value       = "${docker_container.prometheus.name}:${local.http_port}"
}
