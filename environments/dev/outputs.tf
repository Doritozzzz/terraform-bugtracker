output "app_url" {
  description = "Open the application here."
  value       = module.load_balancer.url
}

output "grafana_url" {
  description = "Grafana: metrics and logs. User: grafana_user; password: terraform output -raw grafana_password."
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
  description = "Prometheus web UI: metrics, targets and their health."
  value       = module.metrics_store.url
}

output "storage_console_url" {
  description = "MinIO console. User: storage_console_user; password: terraform output -raw storage_console_password."
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
