# Prometheus

Runs Prometheus with scrape jobs, optional alerting rules and optional Alertmanagers. It scrapes and evaluates every 15 s and keeps 15 days of data on a named volume.

## Usage

```hcl
module "metrics_store" {
  source = "./modules/metrics-store"

  name     = "myapp-prometheus"
  networks = [docker_network.monitoring.name]

  scrape_jobs = [
    { name = "haproxy", targets = [module.load_balancer.metrics_target] },
    {
      name             = "cadvisor"
      targets          = [module.container_metrics.metrics_target]
      keep             = { container_label_environment = "dev" }
      honor_timestamps = false
    },
  ]

  rules_dir       = "${path.module}/alerts"  # optional, *.rules.yml
  external_labels = { environment = "dev" }  # optional
  alertmanagers   = [module.alert_manager.target] # optional
}
```

## Notes

- `keep` stores only the series whose labels match every regex, e.g. one environment from a shared exporter.
- The config is rendered to `<root>/.generated/<name>/prometheus.yml` and its folder is mounted read-only. A change of config or rules is checked with `promtool` and then loaded with `SIGHUP`, without replacing the container. Needs the `docker` CLI where Terraform runs.
- `port` publishes the web UI on 127.0.0.1; leave it null in production.
- Runs as `nobody`, read-only, with no capabilities.

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
| networks | Networks to join: the ones where the scrape targets are, plus one that is not internal if port is set. | `list(string)` | n/a | yes |
| scrape\_jobs | What to scrape every 15 s: a job name and its host:port targets. Optional: keep, a map of label => regex every stored series must match (e.g. to keep one environment from a shared exporter); honor\_timestamps = false to ignore the timestamps an exporter attaches to its samples. Prometheus scrapes itself as job prometheus. | <pre>list(object({<br/>    name             = string<br/>    targets          = list(string)<br/>    keep             = optional(map(string), {})<br/>    honor_timestamps = optional(bool)<br/>  }))</pre> | n/a | yes |
| alertmanagers | Alertmanagers (host:port) that receive the firing alerts. Empty: rules are evaluated but nobody is notified. | `list(string)` | `[]` | no |
| external\_labels | Labels added to every alert this Prometheus sends, e.g. environment = "prod". | `map(string)` | `{}` | no |
| image | Prometheus image. Pinned to an exact version so every machine runs the same one. | `string` | `"prom/prometheus:v3.16.0"` | no |
| labels | Docker labels for the container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| port | Port on 127.0.0.1 for the Prometheus web UI. Null keeps it unpublished. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| rules\_dir | Optional folder with alerting rule files, named *.rules.yml. Other files in it (such as rule tests) are not loaded. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| internal\_url | URL of the Prometheus API inside the Docker network (for Grafana). |
| url | URL of the Prometheus web UI on the host, or null when it is not published. |
<!-- END_TF_DOCS -->
