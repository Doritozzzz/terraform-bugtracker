# Admin gateway

Runs HAProxy as the only way in to the admin tools of an environment: one port on 127.0.0.1 with a login, and every tool under its own path. The tools publish no port of their own; they listen on an internal admin network that only the gateway reaches from outside, like the private subnet of a cloud network behind a bastion or an identity-aware proxy.

## Usage

```hcl
module "admin_gateway" {
  source = "./modules/admin-gateway"

  name     = "myapp-admin"
  port     = 8081                     # published on 127.0.0.1
  networks = [docker_network.frontend.name, docker_network.admin.name]

  routes = [
    { name = "grafana", path_prefix = "/grafana/", server = "myapp-grafana:3000" },
    { name = "mail", path_prefix = "/mail/", server = "myapp-mailpit:8025", strip_prefix = false },
  ]
}
```

Each tool must know its public path to build its links (for example Grafana's `root_url`, Prometheus's `--web.external-url`). By default the gateway removes the prefix before forwarding, so the tool keeps serving from `/`; `strip_prefix = false` is for tools that serve under the prefix themselves (Mailpit's `--webroot`).

## Notes

- HTTP basic auth: every request needs the login, which the `user` and `password` outputs give. The password is generated, passed as an environment variable and never written to the config file. It travels in clear text, which is fine on 127.0.0.1; on a real network the gateway would need TLS.
- The gateway removes the `Authorization` header before forwarding, so the tools never see its credentials (Grafana would take them as its own and reject them). Tools with their own login keep it.
- `/` and any unknown path show an index with a link to every tool; `/grafana` redirects to `/grafana/`.
- Tools are resolved through Docker's DNS, so a replaced tool with a new IP is found again.
- The config is rendered to `<root>/.generated/<name>/haproxy.cfg` and its folder is mounted read-only. A new route is checked and loaded with a graceful reload (`SIGUSR2`), without replacing the container. Needs the `docker` CLI where Terraform runs.
- Every request is logged on stdout with the tool it went to.

Every container also takes the optional `restart`, `memory` (MB, hard limit) and `labels` inputs; `null` keeps Docker's default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| docker | >= 4.7 |
| local | >= 2.9 |
| random | >= 3.9 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Container name of the gateway. | `string` | n/a | yes |
| networks | Networks to join: one that can publish ports and the admin network where the tools listen. | `list(string)` | n/a | yes |
| port | Port published on 127.0.0.1 of the host: the only way in to the admin tools. | `number` | n/a | yes |
| routes | One admin tool per path prefix. strip\_prefix removes the prefix before forwarding, for tools that know their public path but serve from /; set it to false for tools that serve under the prefix themselves. | <pre>list(object({<br/>    name         = string<br/>    path_prefix  = string<br/>    server       = string<br/>    strip_prefix = optional(bool, true)<br/>  }))</pre> | n/a | yes |
| image | HAProxy image (3.4 is the current LTS branch). | `string` | `"haproxy:3.4.7-alpine"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| user | User name of the login. | `string` | `"admin"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| password | Generated password of the login. |
| url | URL of the gateway; every tool is under its path prefix. |
| user | User name of the login. |
<!-- END_TF_DOCS -->
