# HAProxy load balancer

Runs HAProxy in front of a list of backends, with active health checks (plus passive ones on real traffic), optional path routes to other backends, a request ID for every request, a JSON access log and a Prometheus metrics port.

## Usage

```hcl
module "load_balancer" {
  source = "./modules/load-balancer"

  name        = "myapp-lb"
  backends    = module.web.backends   # ["myapp-web-1:3000", ...]
  health_path = "/live"
  port        = 8080                  # published on 127.0.0.1
  networks    = [docker_network.frontend.name, docker_network.app.name]

  routes = [{                         # optional
    name        = "storage"
    path_prefix = "/images/"
    servers     = [module.storage.backend]
    health_path = module.storage.health_path
  }]
}
```

## Notes

- `balance` defaults to `static-rr`: strict turns, and a recovered backend is back in rotation at once.
- The config is rendered to `<root>/.generated/<name>.cfg` and mounted read-only; a change replaces the container (HAProxy reads it only at startup).
- Backends are resolved through Docker's DNS, so recreated containers with a new IP are found again.
- Every request gets an `X-Request-ID` (UUID) sent to the backend and back to the client, also on errors HAProxy generates itself.
- Metrics and `/healthz` listen on port 8405, which is never published (`metrics_target` output).

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
| backends | Servers to balance, as host:port (for example the backends output of the web module). | `list(string)` | n/a | yes |
| health\_path | HTTP path HAProxy calls on every backend to know if it is alive. | `string` | n/a | yes |
| name | Container name of the load balancer. | `string` | n/a | yes |
| networks | Networks to join: one that reaches the backends and one that can publish ports. | `list(string)` | n/a | yes |
| port | Port published on 127.0.0.1 of the host. | `number` | n/a | yes |
| balance | HAProxy balancing algorithm. | `string` | `"static-rr"` | no |
| image | HAProxy image (3.4 is the current LTS branch). | `string` | `"haproxy:3.4.7-alpine"` | no |
| labels | Docker labels for the containers, e.g. environment and service, used by monitoring to filter them. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |
| routes | Extra backends chosen by path prefix (e.g. /images/ to object storage). Anything else goes to backends. | <pre>list(object({<br/>    name        = string<br/>    path_prefix = string<br/>    servers     = list(string)<br/>    health_path = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| metrics\_target | host:port where Prometheus scrapes HAProxy metrics (inside the Docker network). |
| url | URL of the application through the load balancer. |
<!-- END_TF_DOCS -->
