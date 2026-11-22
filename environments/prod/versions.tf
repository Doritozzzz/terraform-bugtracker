terraform {
  # 1.6 brings `terraform test`, used to verify the modules.
  required_version = ">= 1.6"

  # Every provider used here or in the modules, limited to its current major
  # version: a new major can break the code. The exact versions are pinned in
  # .terraform.lock.hcl.
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
