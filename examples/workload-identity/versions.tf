terraform {
  required_version = ">= 1.9"

  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.23"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
  }
}
