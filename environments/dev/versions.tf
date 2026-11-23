terraform {
  # 1.9 lets a variable validation refer to other variables (telegram_chat_id
  # in prod and home_dashboard in the dashboards module); older versions
  # reject the configuration.
  required_version = ">= 1.9"

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
