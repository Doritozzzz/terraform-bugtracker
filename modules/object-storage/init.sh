#!/usr/bin/env bash
# Creates the bucket, applies the download-only policy and syncs the mounted
# folder into it. Terraform runs this script on the host; mc runs inside the
# MinIO container, whose own environment holds the root password, so the
# password never leaves it.
set -euo pipefail

# --env NAME without a value passes the host's value into the container. The
# single quotes keep $MINIO_ROOT_* from being expanded on the host.
docker exec --env BUCKET --env POLICY --env CACHE_CONTROL --env API_PORT "$CONTAINER" bash -c '
  set -eu
  # The container filesystem is read-only: mc keeps its config in the tmpfs.
  export MC_CONFIG_DIR=/tmp/.mc
  export MC_HOST_minio="http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@127.0.0.1:$API_PORT"

  mc mb --ignore-existing "minio/$BUCKET"
  printf "%s" "$POLICY" > /tmp/policy.json
  mc anonymous set-json /tmp/policy.json "minio/$BUCKET"
  # cp uploads every file, so the header is applied even to unchanged files
  # (mirror skips those); mirror --remove then deletes files no longer in the folder.
  mc cp --recursive --attr "Cache-Control=$CACHE_CONTROL" /source/ "minio/$BUCKET"
  mc mirror --remove /source "minio/$BUCKET"
'
