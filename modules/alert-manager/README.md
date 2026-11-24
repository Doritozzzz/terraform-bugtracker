# Alertmanager

Runs Alertmanager, which groups the alerts of Prometheus by name and service, lets a critical alert silence the warnings of the same service, and notifies them by email and, optionally, Telegram, with a link to the Grafana dashboard.

## Usage

```hcl
module "alert_manager" {
  source = "./modules/alert-manager"

  name     = "myapp-alertmanager"
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = 9093 # optional web UI

  email = {
    smarthost = module.mail_catcher.smtp_address
    from      = "alertmanager@myapp.local"
    to        = "oncall@myapp.local"
  }
  telegram = { bot_token = var.telegram_bot_token, chat_id = var.telegram_chat_id } # optional
  dashboard_url = module.dashboards.url
}

# Prometheus sends to module.alert_manager.target
```

## Notes

- Alerts are expected to carry `severity` and `service` labels and, optionally, a `dashboard` annotation (a path).
- Email and Telegram send the same plain text, and also when the alert is resolved.
- Behind a gateway that serves it under a path, set `external_url` (`http://127.0.0.1:8081/alertmanager/`) instead of `port`: its links and those of the notifications use it, while the routes stay at `/`. A Telegram receiver needs a network that is not internal.
- Silences and the notification log are kept on a named volume, so nothing is sent twice after a restart.
- The rendered config holds the bot token: it lives in the ignored `.generated/` folder, like the state.

Every container also takes the optional `restart`, `memory` (MB, hard limit) and `labels` inputs; `null` keeps Docker's default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| docker | >= 4.7 |
| local | >= 2.9 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Container name. It is also the hostname Prometheus sends alerts to. | `string` | n/a | yes |
| networks | Networks to join: the ones where Prometheus and the mail server are, the one people reach it from (a gateway's network, or one that is not internal if port is set), and one that is not internal to reach a chat service such as Telegram. | `list(string)` | n/a | yes |
| dashboard\_url | Optional base URL of Grafana. Alerts with a dashboard annotation (a path) get a full link to it in their notifications. | `string` | `null` | no |
| email | Optional email receiver: SMTP server as host:port (plain SMTP, e.g. a test server), sender and recipient. | <pre>object({<br/>    smarthost = string<br/>    from      = string<br/>    to        = string<br/>  })</pre> | `null` | no |
| external\_url | Public URL when the web UI is served under a path of a gateway that removes it, e.g. http://127.0.0.1:8081/alertmanager/. Used in its links and those of the notifications. Null: served from the root of its port. | `string` | `null` | no |
| image | Alertmanager image. Pinned to an exact version so every machine runs the same one. | `string` | `"prom/alertmanager:v0.35.0"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| port | Port on 127.0.0.1 for the web UI (list and silence alerts). Null keeps it unpublished. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| telegram | Optional Telegram receiver: bot token (from @BotFather) and the chat ID it writes to. | <pre>object({<br/>    bot_token = string<br/>    chat_id   = number<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| target | host:port where Prometheus sends alerts, and of the web UI for a gateway (inside the Docker network). |
| url | URL people open: external\_url, or the published port. Null when neither is set. |
<!-- END_TF_DOCS -->
