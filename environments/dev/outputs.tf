output "app_url" {
  description = "Open the application here."
  value       = module.load_balancer.url
}

output "admin_url" {
  description = "Admin gateway: one login (admin_user / terraform output -raw admin_password), then every tool."
  value       = module.admin_gateway.url
}

output "admin_user" {
  description = "Admin gateway user."
  value       = module.admin_gateway.user
}

output "admin_password" {
  description = "Admin gateway password."
  value       = module.admin_gateway.password
  sensitive   = true
}

output "grafana_url" {
  description = "Grafana: metrics and logs, through the admin gateway. Then its own login: grafana_user / terraform output -raw grafana_password."
  value       = module.dashboards.url
}

output "grafana_user" {
  description = "Grafana administrator user."
  value       = module.dashboards.admin_user
}

output "grafana_password" {
  description = "Grafana administrator password."
  value       = module.dashboards.admin_password
  sensitive   = true
}

output "prometheus_url" {
  description = "Prometheus web UI, through the admin gateway: metrics, targets and their health."
  value       = module.metrics_store.url
}

output "storage_console_url" {
  description = "MinIO console, through the admin gateway. Then its own login: storage_console_user / terraform output -raw storage_console_password."
  value       = module.storage.console_url
}

output "storage_console_user" {
  description = "MinIO console user."
  value       = module.storage.root_user
}

output "storage_console_password" {
  description = "MinIO console password."
  value       = module.storage.root_password
  sensitive   = true
}
