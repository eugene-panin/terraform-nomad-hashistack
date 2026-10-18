provider "consul" {}

provider "nomad" {}

provider "vault" {}

provider "tls" {}

variable "ca_pem" {
  description = "PEM CA of the Consul, Vault and Nomad certificates."
  type        = string
}

variable "ca_key_pem" {
  description = "PEM key of the CA; it signs the certificate of the internal entrypoint."
  type        = string
  sensitive   = true
}

module "stack" {
  source = "../.."

  address    = "10.77.0.1"
  ca_pem     = var.ca_pem
  ca_key_pem = var.ca_key_pem
}

module "traefik_public" {
  source = "../../modules/traefik"

  role       = "public"
  acme_email = "admin@example.com"
  consul     = { ca_pem = var.ca_pem }
}

output "ui_urls" {
  description = "Addresses of the Consul, Nomad and Vault UIs."
  value       = module.stack.ui_urls
}
