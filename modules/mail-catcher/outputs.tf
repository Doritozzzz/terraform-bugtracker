output "smtp_address" {
  description = "host:port where containers on the same network send mail (plain SMTP, no TLS or authentication)."
  value       = "${docker_container.mailpit.name}:${local.smtp_port}"
}

output "url" {
  description = "URL of the web UI with the received mail: public_url, or the published port. Null when neither is set."
  value       = var.public_url != null ? var.public_url : var.port == null ? null : "http://127.0.0.1:${var.port}"
}

output "backend" {
  description = "host:port of the web UI inside the network, ready to give to a gateway."
  value       = "${docker_container.mailpit.name}:${local.http_port}"
}
