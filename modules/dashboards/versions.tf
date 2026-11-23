terraform {
  # 1.9: the home_dashboard validation also checks dashboards_dir.
  required_version = ">= 1.9"

  # A reusable module only sets minimum versions; the project using it pins
  # the exact ones in its own .terraform.lock.hcl.
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 4.7"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.9"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9"
    }
  }
}
