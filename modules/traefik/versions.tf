terraform {
  required_version = ">= 1.11"

  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 2.5, < 3.0"
    }
  }
}
