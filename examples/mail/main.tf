provider "consul" {}

provider "nomad" {}

provider "vault" {}

variable "nomad_jwks_url" {
  description = "JWKS endpoint of the Nomad servers."
  type        = string
}

variable "vault_kv_path" {
  description = "Path of the KV engine for workload secrets."
  type        = string
  default     = "secret"
}

variable "traefik" {
  description = "Inputs of the traefik module."
  type = object({
    domain                = string
    acme_email            = string
    acme_ca_server        = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
    acme_ca_certificate   = optional(string)
    dns_provider          = optional(string, "cloudflare")
    dns_propagation_check = optional(bool, true)
    internal              = optional(object({ host_network = optional(string, "default"), port = optional(number, 443) }), {})
    public                = optional(object({ host_network = optional(string, "public"), http_port = optional(number, 80), https_port = optional(number, 443) }), {})
    consul                = optional(object({ address = optional(string, "127.0.0.1:8501"), scheme = optional(string, "https"), ca_pem = optional(string) }), {})
  })
}

variable "dns_provider_env" {
  description = "Environment of the DNS provider Traefik answers DNS-01 with."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
}

variable "mail" {
  description = "Inputs of the mail module."
  type = object({
    hostname            = string
    domains             = set(string)
    accounts            = optional(map(object({ aliases = optional(set(string), []) })), {})
    acme_email          = string
    acme_ca_server      = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
    acme_ca_certificate = optional(string)
    mta_sts_mode        = optional(string, "testing")
  })
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = var.vault_kv_path
}

module "traefik" {
  source = "../../modules/traefik"

  domain                = var.traefik.domain
  acme_email            = var.traefik.acme_email
  acme_ca_server        = var.traefik.acme_ca_server
  acme_ca_certificate   = var.traefik.acme_ca_certificate
  dns_provider          = var.traefik.dns_provider
  dns_provider_env      = var.dns_provider_env
  dns_propagation_check = var.traefik.dns_propagation_check
  internal              = var.traefik.internal
  public                = merge(var.traefik.public, { enabled = true })
  consul                = var.traefik.consul
  vault_kv_path         = module.workload_identity.vault_kv_path
}

module "mail" {
  source = "../../modules/mail"

  hostname            = var.mail.hostname
  domains             = var.mail.domains
  accounts            = var.mail.accounts
  acme_email          = var.mail.acme_email
  acme_ca_server      = var.mail.acme_ca_server
  acme_ca_certificate = var.mail.acme_ca_certificate
  mta_sts_mode        = var.mail.mta_sts_mode
  vault_kv_path       = module.workload_identity.vault_kv_path
}

output "passwords" {
  description = "Generated password of each account."
  value       = module.mail.passwords
  sensitive   = true
}

output "dns_records" {
  description = "DNS records each mail domain needs."
  value       = module.mail.dns_records
}
