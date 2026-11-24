output "url" {
  description = "URL of the gateway; every tool is under its path prefix."
  value       = "http://127.0.0.1:${var.port}"
}

output "user" {
  description = "User name of the login."
  value       = var.user
}

output "password" {
  description = "Generated password of the login."
  value       = random_password.this.result
  sensitive   = true
}
