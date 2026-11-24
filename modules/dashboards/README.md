# Grafana

Runs Grafana with its data sources and dashboards provisioned from files, so they are code and cannot be changed from the web UI. The admin password is generated.

## Usage

```hcl
module "dashboards" {
  source = "./modules/dashboards"

  name     = "myapp-grafana"
  networks = [docker_network.monitoring.name, docker_network.frontend.name]
  port     = 3001

  datasources = [
    { uid = "prometheus", name = "Prometheus", type = "prometheus", url = module.metrics_store.internal_url, default = true },
    { uid = "loki", name = "Loki", type = "loki", url = module.log_store.internal_url },
  ]

  dashboards_dir = "${path.module}/dashboards" # optional
  home_dashboard = "status.json"               # optional
}

# Login: module.dashboards.admin_user / admin_password (sensitive)
```

## Notes

- Grafana expands `$VAR` in provisioning files: write a literal `$` as `$$` in `json_data`.
- Behind a gateway that serves it under a path (e.g. `admin-gateway`), leave `port` null and set `root_url` to the public URL (`http://127.0.0.1:8081/grafana/`): Grafana builds its links with it and keeps serving from `/`. `backend` gives the gateway its `host:port`.
- Uses the plugins bundled in the image (nothing downloaded at startup) and does not call home (usage reports, update checks, news).
- Logs JSON to stdout at `warn` (at `info` it logs every panel query).
- Dashboards are reloaded when their files change, without replacing the container.

Every container also takes the optional `restart`, `memory` (MB, hard limit) and `labels` inputs; `null` keeps Docker's default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9 |
| docker | >= 4.7 |
| local | >= 2.9 |
| random | >= 3.9 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| datasources | Data sources to provision: uid (fixed ID for dashboards), display name, Grafana type (e.g. prometheus, loki), URL, whether it is the default one and, optionally, json\_data: type-specific settings (Grafana's jsonData) as JSON text, e.g. jsonencode({...}). Grafana expands $VAR in provisioning files, so a literal $ must be written $$. | <pre>list(object({<br/>    uid       = string<br/>    name      = string<br/>    type      = string<br/>    url       = string<br/>    default   = optional(bool, false)<br/>    json_data = optional(string)<br/>  }))</pre> | n/a | yes |
| name | Container name. | `string` | n/a | yes |
| networks | Networks to join: the ones where the data sources are, plus the one people reach it from (a gateway's network, or one that is not internal to publish the port). | `list(string)` | n/a | yes |
| dashboards\_dir | Optional folder with dashboard JSON files to provision. Null provisions none. | `string` | `null` | no |
| home\_dashboard | Optional file name (inside dashboards\_dir) of the dashboard shown as the home page. | `string` | `null` | no |
| image | Grafana image. Pinned to an exact version so every machine runs the same one. | `string` | `"grafana/grafana:13.3.1"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| port | Port on 127.0.0.1 where Grafana is published. Null keeps it unpublished, e.g. behind a gateway. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| root\_url | Public URL when Grafana is served under a path of a gateway that removes it, e.g. http://127.0.0.1:8081/grafana/. Grafana builds its links and redirects with it. Null: served from the root of its port. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_password | Generated Grafana administrator password. |
| admin\_user | Grafana administrator user. |
| backend | host:port of the web UI inside the network, ready to give to a gateway. |
| url | URL people open: root\_url, or the published port. Null when neither is set. |
<!-- END_TF_DOCS -->
