provider "consul" {}

provider "nomad" {}

provider "vault" {}

provider "cloudflare" {}

variable "ca_pem" {
  description = "PEM CA of the Consul, Vault and Nomad certificates."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare token Traefik answers the DNS-01 challenge with."
  type        = string
  sensitive   = true
  ephemeral   = true
}

module "stack" {
  source = "../.."

  infra_domain     = "infra.example.com"
  address          = "10.77.0.1"
  ca_pem           = var.ca_pem
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = var.cloudflare_api_token }

  mail = {
    hostname = "mail.example.com"
    domains  = ["example.com", "example.org"]
  }
}

module "dns" {
  source = "../../modules/dns-cloudflare"

  records = module.stack.dns_records
  domains = ["infra.example.com", "example.com", "example.org"]
}

output "ui_urls" {
  description = "Addresses of the Consul, Nomad and Vault UIs."
  value       = module.stack.ui_urls
}

output "mail_passwords" {
  description = "Password of each mailbox."
  value       = module.stack.mail_passwords
  sensitive   = true
}
