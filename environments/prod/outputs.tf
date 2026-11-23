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

output "alertmanager_url" {
  description = "Alertmanager: firing alerts, and silencing them."
  value       = module.alert_manager.url
}

output "mail_url" {
  description = "Test mailbox with the alert emails."
  value       = module.mail_catcher.url
}
