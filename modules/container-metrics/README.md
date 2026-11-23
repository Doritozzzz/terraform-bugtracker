# cAdvisor container metrics

Runs cAdvisor, which reports the CPU, memory, network and Docker health state of every container on the host for Prometheus.

## Usage

```hcl
module "container_metrics" {
  source = "./modules/container-metrics"

  name        = "myapp-cadvisor"
  networks    = [docker_network.monitoring.name]
  keep_labels = ["environment", "service"] # exported as container_label_<name>
}

# Prometheus scrapes module.container_metrics.metrics_target
```

## Notes

- No privileged mode and only three read-only mounts (`/sys`, the Docker and containerd sockets), instead of the upstream instructions' privileged mode and host mounts.
- Only `keep_labels` become metric labels, never environment variables, so secrets cannot leak into metrics.
- It sees every container on the host: filter by label in Prometheus (`keep` in `metrics-store`) and ignore its timestamps (`honor_timestamps = false`) so stopped containers disappear at once.
- Runs as root because it needs the Docker socket; no capabilities, read-only, no published port.

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
| name | Container name. It is also the hostname Prometheus uses to scrape it. | `string` | n/a | yes |
| networks | Networks to join: the one where Prometheus can reach it. | `list(string)` | n/a | yes |
| image | cAdvisor image. Published on ghcr.io since v0.53; pinned to an exact version so every machine runs the same one. | `string` | `"ghcr.io/google/cadvisor:v0.61.1"` | no |
| keep\_labels | Docker labels exported with every metric, as container\_label\_<name>. No other label or environment variable is exported, so secrets never become metric labels. | `list(string)` | `[]` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| metrics\_target | host:port where Prometheus scrapes the container metrics (inside the Docker network). |
<!-- END_TF_DOCS -->
