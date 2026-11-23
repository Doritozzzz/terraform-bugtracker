# Redis cache

Runs Redis as a pure cache: generated password, no snapshots, a memory cap and least-recently-used eviction.

## Usage

```hcl
module "cache" {
  source = "./modules/cache"

  name    = "myapp-cache"
  network = docker_network.backend.name
}

# Connection: module.cache.host, .port, .password (sensitive)
```

## Notes

- Nothing is written to disk (`--save ''`, data in a tmpfs): after a restart the cache is empty, so it can never serve stale data.
- The password reaches `redis-server` and `redis-cli` through an environment variable, never in the process arguments.
- Runs as the `redis` user, read-only, with no capabilities.

Every container also takes the optional `restart`, `memory` (MB, hard limit) and `labels` inputs; `null` keeps Docker's default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| docker | >= 4.7 |
| random | >= 3.9 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Container name. It is also the hostname other containers use to connect. | `string` | n/a | yes |
| network | Name or ID of the Docker network the cache joins. | `string` | n/a | yes |
| image | Redis image. Pinned to an exact version so every machine runs the same one. | `string` | `"redis:8.10.3-alpine"` | no |
| labels | Docker labels for the containers, e.g. environment and service, used by monitoring to filter them. | `map(string)` | `{}` | no |
| max\_memory | Memory limit for cached data (Redis syntax, e.g. 64mb). The least recently used keys are evicted when it is full. | `string` | `"64mb"` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| host | Hostname to reach Redis from containers on the same network. |
| password | Generated Redis password. |
| port | Redis port inside the network. |
<!-- END_TF_DOCS -->
