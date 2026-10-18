provider "consul" {}

provider "nomad" {}

provider "vault" {}

variable "nomad_jwks_url" {
  type = string
}

variable "image" {
  type = string
}

variable "internal_tls" {
  type = object({
    cert_pem = string
    key_pem  = string
  })
  sensitive = true
}

module "workload_identity" {
  source = "../../../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = "kv"
}

module "traefik" {
  source = "../../../../modules/traefik"

  role   = "internal"
  tls    = var.internal_tls
  consul = { address = "consul:8500", scheme = "http" }
  image  = var.image
}
