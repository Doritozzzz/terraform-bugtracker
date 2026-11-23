# Web application replicas

Builds a Docker image from a folder with a Dockerfile and runs N identical replicas of it. The image tag is the hash of the code, so a code change builds a new image and replaces the replicas.

## Usage

```hcl
module "web" {
  source = "./modules/web"

  name       = "myapp-web"
  source_dir = "${path.module}/app"
  replicas   = 3
  port       = 3000
  networks   = [docker_network.app.name]

  env = {
    DB_HOST = module.database.host
  }
}

# For a load balancer: module.web.backends = ["myapp-web-1:3000", ...]
```

## Notes

- Each replica's hostname is its container name, so the app can report which replica answered.
- `env` is sensitive (it usually holds passwords); `null` values are skipped so the app default applies.
- Hardened: read-only filesystem (`read_only`), no capabilities, no privilege escalation. The user and the healthcheck come from the Dockerfile.
- `metrics_port` only feeds the `metrics_targets` output, for Prometheus.

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
| name | Base name. Replicas are called <name>-1, <name>-2... and the image <name>. | `string` | n/a | yes |
| networks | Names or IDs of the Docker networks every replica joins. | `list(string)` | n/a | yes |
| port | Port the application listens on inside the container. | `number` | n/a | yes |
| replicas | Number of identical containers to run. | `number` | n/a | yes |
| source\_dir | Folder with the application and its Dockerfile. The image is rebuilt when any file in it changes. | `string` | n/a | yes |
| env | Environment variables for the application; null values are not set. Marked sensitive because it usually holds passwords. | `map(string)` | `{}` | no |
| labels | Docker labels for the containers, e.g. environment and service, used by monitoring to filter them. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| metrics\_port | Port where the application serves Prometheus metrics inside the container. Null if it serves none. | `number` | `null` | no |
| read\_only | Read-only root filesystem. Set to false only if the application must write to disk. | `bool` | `true` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| backends | host:port of every replica, ready to give to a load balancer. |
| metrics\_targets | host:port of every replica's metrics, ready to give to Prometheus. Empty when metrics\_port is null. |
| names | Container name of every replica (also its hostname inside the network). |
<!-- END_TF_DOCS -->
