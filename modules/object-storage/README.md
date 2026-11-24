# MinIO object storage

Runs MinIO (S3-compatible storage), creates a bucket that anonymous users can only download from, and uploads a folder to it. The upload runs again whenever a file in the folder changes.

## Usage

```hcl
module "storage" {
  source = "./modules/object-storage"

  name       = "myapp-storage"
  networks   = [docker_network.app.name]
  bucket     = "images"
  source_dir = "${path.module}/images"
  # console_port = 9001   # optional: publish the admin console on 127.0.0.1
}

# For a load balancer route: module.storage.backend and module.storage.health_path
```

## Notes

- The upload is `init.sh`, run by Terraform on the host (`local-exec`): it calls `docker exec` so `mc` runs inside the MinIO container, which already holds the password. No extra container is left behind; a failed upload fails the apply and the next apply retries it.
- The machine running Terraform needs `bash` and the `docker` CLI.
- The bucket policy only allows `s3:GetObject`: anonymous users cannot list, upload or delete (MinIO's built-in `download` policy would allow listing).
- Every object gets a `Cache-Control` header (`no-cache` by default: browsers revalidate and changes show at once).
- The official MinIO images are no longer published, so the Chainguard image is pinned by digest.
- Behind a gateway that serves the console under a path, set `console_url` (`http://127.0.0.1:8081/minio/`, with the final `/` or the console shows a blank page) and leave `console_port` null. `console_backend` gives the gateway its `host:port`.

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
| bucket | Bucket created on start. Anonymous users can download its objects, nothing else. | `string` | n/a | yes |
| name | Container name. It is also the hostname other containers use to connect. | `string` | n/a | yes |
| networks | Networks to join. Publishing the console needs one that is not internal. | `list(string)` | n/a | yes |
| source\_dir | Folder uploaded to the bucket. The upload runs again whenever any file in it changes. | `string` | n/a | yes |
| cache\_control | Cache-Control header of every uploaded object. no-cache makes browsers revalidate (cheap 304) so changes show at once. | `string` | `"no-cache"` | no |
| console\_port | Port on 127.0.0.1 for the MinIO web console. Null keeps the console unpublished. | `number` | `null` | no |
| console\_url | Public URL of the console when it is served under a path of a gateway that removes it, e.g. http://127.0.0.1:8081/minio/ (the final / is needed). Null: served from the root of its port. | `string` | `null` | no |
| image | MinIO image. The official images can no longer be pulled; Chainguard only tags latest, so it is pinned by digest. | `string` | `"cgr.dev/chainguard/minio@sha256:548147b5fc95a67e3e45285dff7e0e50326c3eb1977c6218039461771156c5e7"` | no |
| labels | Docker labels for the MinIO container, e.g. environment and service, used by monitoring to filter it. | `map(string)` | `{}` | no |
| memory | Memory limit in MB. Null means no limit. | `number` | `null` | no |
| restart | Docker restart policy: no, on-failure, always or unless-stopped. Null keeps the Docker default (no). | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| backend | host:port of the S3 API, ready to give to a load balancer. |
| bucket | Bucket name. Objects are served at /<bucket>/<file>. |
| console\_backend | host:port of the web console inside the network, ready to give to a gateway. |
| console\_url | URL people open for the console: console\_url, or the published port. Null when neither is set. |
| health\_path | Unauthenticated HTTP path that answers 200 while MinIO is alive. |
| host | Hostname to reach the S3 API from containers on the same network. |
| port | S3 API port inside the network. |
| root\_password | Generated administrator password (console login). |
| root\_user | Administrator user (console login). |
<!-- END_TF_DOCS -->
