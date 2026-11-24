# Mailpit test mail server

Runs Mailpit, a test SMTP server that accepts every email and shows it in a web UI instead of delivering it, so notifications can be tested on any machine with no mail account.

## Usage

```hcl
module "mail_catcher" {
  source = "./modules/mail-catcher"

  name     = "myapp-mailpit"
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = 8025
}

# Senders use module.mail_catcher.smtp_address (plain SMTP, no TLS or authentication)
```

## Notes

- The mailbox lives in memory: it is a test inbox, emptied on restart.
- The web UI only answers requests for its published address, which blocks DNS rebinding.
- Runs as an unprivileged user (the image would run as root), read-only, with no capabilities.

Every container also takes the optional `restart`, `memory` (MB, hard limit) and `labels` inputs; `null` keeps Docker's default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| docker | >= 4.7 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Container name. It is also the SMTP hostname other containers send mail to. | `string` | n/a | yes |
| networks | Networks to join: the one where the senders are, plus the one people reach the web UI from (a gateway's network, or one that is not internal to publish the port). | `list(string)` | n/a | yes |
| image | Mailpit image. Pinned to an exact version so every machine runs the same one. | `string` | `"axllent/mailpit:v1.34.0"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| port | Port on 127.0.0.1 where the web UI with the received mail is published. Null keeps it unpublished, e.g. behind a gateway. | `number` | `null` | no |
| public\_url | Public URL when the web UI is served under a path of a gateway that keeps it, e.g. http://127.0.0.1:8081/mail/. Mailpit then serves under that path and only answers requests for that host. Null: served from the root of its port. | `string` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| backend | host:port of the web UI inside the network, ready to give to a gateway. |
| smtp\_address | host:port where containers on the same network send mail (plain SMTP, no TLS or authentication). |
| url | URL of the web UI with the received mail: public\_url, or the published port. Null when neither is set. |
<!-- END_TF_DOCS -->
