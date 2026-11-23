# Loki log store

Runs Loki in single-process mode with its data on a named volume and a retention period, so logs are deleted after a number of days instead of kept forever.

## Usage

```hcl
module "log_store" {
  source = "./modules/log-store"

  name           = "myapp-loki"
  networks       = [docker_network.monitoring.name]
  retention_days = 7 # the default
}

# Log collectors push to module.log_store.push_url; Grafana reads module.log_store.internal_url
```

## Notes

- Usage reports to Grafana Labs are disabled, and Loki logs at `warn` (at `info` it logs every query it serves).
- No Docker healthcheck: the image is distroless (no shell or HTTP client). Watch it from Prometheus (`metrics_target`).
- Runs as an unprivileged user, read-only, with no capabilities.

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
| name | Container name. It is also the hostname other containers use to connect. | `string` | n/a | yes |
| networks | Networks to join: the ones where the log collector and Grafana can reach it. | `list(string)` | n/a | yes |
| image | Loki image. Pinned to an exact version so every machine runs the same one. | `string` | `"grafana/loki:3.7.10"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| retention\_days | Days logs are kept before Loki deletes them. | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| internal\_url | URL of the Loki API inside the Docker network (for Grafana). |
| metrics\_target | host:port where Prometheus scrapes Loki's own metrics (inside the Docker network). |
| push\_url | URL where log collectors push logs (inside the Docker network). |
<!-- END_TF_DOCS -->
