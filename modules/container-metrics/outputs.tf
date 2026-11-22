output "metrics_target" {
  description = "host:port where Prometheus scrapes the container metrics (inside the Docker network)."
  value       = "${docker_container.cadvisor.name}:${local.http_port}"
}
