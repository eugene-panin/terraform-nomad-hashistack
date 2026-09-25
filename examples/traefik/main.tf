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

variable "domain" {
  description = "Domain Traefik serves internally."
  type        = string
}

variable "acme_email" {
  description = "Contact address for the ACME account."
  type        = string
}

variable "acme_ca_server" {
  description = "ACME directory URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_ca_certificate" {
  description = "PEM CA of a private ACME server."
  type        = string
  default     = null
}

variable "dns_provider" {
  description = "DNS-01 provider, by its lego name."
  type        = string
  default     = "cloudflare"
}

variable "dns_provider_env" {
  description = "Environment of the DNS provider."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
}

variable "dns_propagation_check" {
  description = "Wait for the DNS-01 record before validation."
  type        = bool
  default     = true
}

variable "internal" {
  description = "Internal entrypoint."
  type = object({
    host_network = optional(string, "default")
    port         = optional(number, 443)
  })
  default = {}
}

variable "public" {
  description = "Public entrypoints."
  type = object({
    enabled      = optional(bool, false)
    host_network = optional(string, "public")
    http_port    = optional(number, 80)
    https_port   = optional(number, 443)
  })
  default = {}
}

variable "consul" {
  description = "Consul agent Traefik reads the catalog from."
  type = object({
    address = optional(string, "127.0.0.1:8501")
    scheme  = optional(string, "https")
    ca_pem  = optional(string)
  })
  default = {}
}

variable "routes" {
  description = "Routes to backends outside Nomad."
  type = map(object({
    host = string
    url  = string
  }))
  default = {}
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = var.vault_kv_path
}

module "traefik" {
  source = "../../modules/traefik"

  domain                = var.domain
  acme_email            = var.acme_email
  acme_ca_server        = var.acme_ca_server
  acme_ca_certificate   = var.acme_ca_certificate
  dns_provider          = var.dns_provider
  dns_provider_env      = var.dns_provider_env
  dns_propagation_check = var.dns_propagation_check
  internal              = var.internal
  public                = var.public
  consul                = var.consul
  routes                = var.routes
  vault_kv_path         = module.workload_identity.vault_kv_path
}
