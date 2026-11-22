output "url" {
  description = "URL of Grafana on the host."
  value       = "http://127.0.0.1:${var.port}"
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
