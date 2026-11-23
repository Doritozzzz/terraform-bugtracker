# PostgreSQL

Runs PostgreSQL with a generated password and a named volume, so the data survives when the container is replaced.

## Usage

```hcl
module "database" {
  source = "./modules/database"

  name          = "myapp-db"
  network       = docker_network.backend.name
  database      = "app"
  user          = "app"
  init_script   = "${path.module}/db/init.sql" # optional, first start only
  slow_query_ms = 500                          # optional
}

# Connection: module.database.host, .port, .database, .user, .password (sensitive)
```

## Notes

- The password is generated once (`random_password`) and kept in the Terraform state.
- The healthcheck uses `pg_isready` over TCP, which fails until `init_script` has loaded, and `wait = true` makes `terraform apply` wait for it.
- `slow_query_ms` sets `log_min_duration_statement`: every slower statement is logged with its duration.
- Runs as the `postgres` user, read-only, with no capabilities.

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
| database | Name of the database created on the first start. | `string` | n/a | yes |
| name | Container name. It is also the hostname other containers use to connect. | `string` | n/a | yes |
| network | Name or ID of the Docker network the database joins. | `string` | n/a | yes |
| user | Owner of the database. | `string` | n/a | yes |
| image | PostgreSQL image. Pinned to an exact version so every machine runs the same one. | `string` | `"postgres:18.7-alpine"` | no |
| init\_script | Optional path to a .sql file run only on the first start, while the data volume is empty. | `string` | `null` | no |
| labels | Docker labels for the containers, e.g. environment and service, used by monitoring to filter them. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| slow\_query\_ms | Log every statement that takes longer than this many milliseconds (PostgreSQL log\_min\_duration\_statement; 0 logs them all). Null keeps it off, the PostgreSQL default. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| database | Database name. |
| host | Hostname to reach PostgreSQL from containers on the same network. |
| password | Generated database password. |
| port | PostgreSQL port inside the network. |
| user | Database user. |
<!-- END_TF_DOCS -->
