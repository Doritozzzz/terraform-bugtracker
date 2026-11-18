output "names" {
  description = "Container name of every replica (also its hostname inside the network)."
  value       = docker_container.this[*].name
}

output "backends" {
  description = "host:port of every replica, ready to give to a load balancer."
  value       = [for c in docker_container.this : "${c.name}:${var.port}"]
}
