terraform {
  required_version = ">= 1.11"

  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.23"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.6"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
  }
}
