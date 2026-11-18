output "host" {
  description = "Hostname to reach PostgreSQL from containers on the same network."
  value       = docker_container.postgres.name
}

output "port" {
  description = "PostgreSQL port inside the network."
  value       = 5432
}

output "database" {
  description = "Database name."
  value       = var.database
}

output "user" {
  description = "Database user."
  value       = var.user
}

output "password" {
  description = "Generated database password."
  value       = random_password.this.result
  sensitive   = true
}
