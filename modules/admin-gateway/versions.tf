terraform {
  required_version = ">= 1.6"

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
