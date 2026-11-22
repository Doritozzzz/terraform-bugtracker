output "host" {
  description = "Hostname to reach Redis from containers on the same network."
  value       = docker_container.redis.name
}

output "port" {
  description = "Redis port inside the network."
  value       = 6379
}

output "password" {
  description = "Generated Redis password."
  value       = random_password.this.result
  sensitive   = true
}
