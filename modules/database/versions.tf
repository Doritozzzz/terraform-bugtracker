terraform {
  required_version = ">= 1.6"

  # A reusable module only sets minimum versions; the project using it pins
  # the exact ones in its own .terraform.lock.hcl.
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 4.7"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9"
    }
  }
}
