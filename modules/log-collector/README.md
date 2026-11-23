# Alloy log collector

Runs Grafana Alloy, which follows the logs of the containers that have every label in `container_filter` and pushes them to Loki. It reads the Docker API through a private, read-only proxy instead of the Docker socket.

## Usage

```hcl
module "log_collector" {
  source = "./modules/log-collector"

  name             = "myapp-alloy"
  networks         = [docker_network.monitoring.name]
  push_url         = module.log_store.push_url
  container_filter = { project = "myapp", environment = "dev" }
  keep_labels      = ["environment", "service"] # Docker labels copied as Loki labels
}
```

## Notes

- The Docker socket gives full control of the host and a read-only mount does not limit the API. The proxy (`<name>-docker-api`) only allows listing containers and networks and reading logs; anything else answers 403.
- The proxy is on a private network only Alloy can reach.
- Alloy keeps its read positions on a named volume: a restart neither loses nor repeats lines.
- Loki labels: `container`, `stream` (stdout/stderr) and the `keep_labels`.

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
| container\_filter | Docker labels a container must have, all of them, for its logs to be collected (e.g. environment = "dev"). | `map(string)` | n/a | yes |
| name | Container name of the collector. The Docker API proxy is called <name>-docker-api. | `string` | n/a | yes |
| networks | Networks to join: the one where Loki can be reached. | `list(string)` | n/a | yes |
| push\_url | Loki push URL (for example the push\_url output of the log-store module). | `string` | n/a | yes |
| image | Grafana Alloy image. Pinned to an exact version so every machine runs the same one. | `string` | `"grafana/alloy:v1.22.0"` | no |
| keep\_labels | Docker labels copied to every log stream as Loki labels, to filter by them (e.g. service). | `list(string)` | `[]` | no |
| labels | Docker labels for both containers, e.g. environment and service, used by monitoring to filter them. | `map(string)` | `{}` | no |
| memory | Memory limit of the collector in MB. Null means no limit. | `number` | `null` | no |
| proxy\_image | Docker API proxy image. linuxserver only tags each weekly rebuild exactly, so that tag is pinned. | `string` | `"lscr.io/linuxserver/socket-proxy:3.4.8-r0-ls107"` | no |
| proxy\_memory | Memory limit of the Docker API proxy in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy of both containers: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| metrics\_target | host:port where Prometheus scrapes the collector's own metrics (inside the Docker network). |
<!-- END_TF_DOCS -->
