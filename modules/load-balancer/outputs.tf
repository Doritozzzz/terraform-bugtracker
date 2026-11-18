output "url" {
  description = "URL of the application through the load balancer."
  value       = "http://127.0.0.1:${var.port}"
}

output "metrics_target" {
  description = "host:port where Prometheus scrapes HAProxy metrics (inside the Docker network)."
  value       = "${docker_container.haproxy.name}:${local.metrics_port}"
}
