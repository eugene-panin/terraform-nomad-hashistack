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

variable "internal_tls" {
  description = "Certificate and key of the internal entrypoint, for *.service.consul, signed by the project CA."
  type = object({
    cert_pem = string
    key_pem  = string
  })
  sensitive = true
}

variable "internal" {
  description = "Internal entrypoint."
  type = object({
    host_network = optional(string, "default")
    port         = optional(number, 443)
  })
  default = {}
}

variable "routes" {
  description = "Routes to backends outside Nomad, on the internal entrypoint."
  type = map(object({
    host = string
    url  = string
  }))
  default = {}
}

variable "acme_email" {
  description = "Contact address for the ACME account of the public Traefik."
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

variable "public" {
  description = "Public entrypoints."
  type = object({
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

variable "image" {
  description = "The image of Traefik; null takes the default of the module."
  type        = string
  default     = null
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = var.vault_kv_path
}

module "traefik_internal" {
  source = "../../modules/traefik"

  role     = "internal"
  tls      = var.internal_tls
  internal = var.internal
  routes   = var.routes
  consul   = var.consul
  image    = var.image

  depends_on = [module.workload_identity]
}

module "traefik_public" {
  source = "../../modules/traefik"

  role                = "public"
  acme_email          = var.acme_email
  acme_ca_server      = var.acme_ca_server
  acme_ca_certificate = var.acme_ca_certificate
  public              = var.public
  consul              = var.consul
  image               = var.image

  depends_on = [module.workload_identity]
}
