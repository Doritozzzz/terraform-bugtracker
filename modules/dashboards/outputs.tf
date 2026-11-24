output "url" {
  description = "URL people open: root_url, or the published port. Null when neither is set."
  value       = var.root_url != null ? var.root_url : var.port == null ? null : "http://127.0.0.1:${var.port}"
}

output "backend" {
  description = "host:port of the web UI inside the network, ready to give to a gateway."
  value       = "${docker_container.grafana.name}:${local.http_port}"
}

output "admin_user" {
  description = "Grafana administrator user."
  value       = local.admin_user
}

output "admin_password" {
  description = "Generated Grafana administrator password."
  value       = random_password.admin.result
  sensitive   = true
}
