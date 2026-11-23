output "smtp_address" {
  description = "host:port where containers on the same network send mail (plain SMTP, no TLS or authentication)."
  value       = "${docker_container.mailpit.name}:${local.smtp_port}"
}

output "url" {
  description = "URL of the web UI with the received mail."
  value       = "http://127.0.0.1:${var.port}"
}
