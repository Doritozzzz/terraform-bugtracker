output "app_url" {
  description = "Open the application here."
  value       = module.load_balancer.url
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
