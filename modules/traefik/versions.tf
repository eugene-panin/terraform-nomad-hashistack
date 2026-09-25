terraform {
  required_version = ">= 1.9"

  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.5, < 3.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 5.0, < 6.0"
    }
  }
}
