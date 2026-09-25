terraform {
  required_version = ">= 1.9"

  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = ">= 2.21, < 3.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.0, < 6.0"
    }
  }
}
