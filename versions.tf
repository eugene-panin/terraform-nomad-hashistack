terraform {
  required_version = ">= 1.11"

  required_providers {
    consul = {
      source  = "hashicorp/consul"
      version = ">= 2.21, < 3.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.5, < 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0, < 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.0, < 6.0"
    }
  }
}
