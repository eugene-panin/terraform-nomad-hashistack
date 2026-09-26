terraform {
  required_version = ">= 1.11"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.23"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
  }
}
