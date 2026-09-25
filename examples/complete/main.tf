provider "consul" {}

provider "nomad" {}

provider "vault" {}

variable "nomad_jwks_url" {
  description = "JWKS endpoint of the Nomad servers."
  type        = string
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
}

variable "cloudflare_api_token" {
  description = "Cloudflare token Traefik answers the DNS-01 challenge with."
  type        = string
  sensitive   = true
  ephemeral   = true
}

module "traefik" {
  source = "../../modules/traefik"

  domain           = "example.com"
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = var.cloudflare_api_token }
  vault_kv_path    = module.workload_identity.vault_kv_path
}
