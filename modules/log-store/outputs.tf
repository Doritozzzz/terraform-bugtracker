output "push_url" {
  description = "URL where log collectors push logs (inside the Docker network)."
  value       = "http://${docker_container.loki.name}:${local.http_port}/loki/api/v1/push"
}
