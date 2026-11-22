terraform {
  # 1.6 brings `terraform test`, used to verify the modules.
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      # Any 4.x from 4.7 on; the exact version is pinned in .terraform.lock.hcl.
      version = "~> 4.7"
    }
  }
}
