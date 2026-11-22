output "metrics_target" {
  description = "host:port where Prometheus scrapes the collector's own metrics (inside the Docker network)."
  value       = "${docker_container.alloy.name}:${local.http_port}"
}
