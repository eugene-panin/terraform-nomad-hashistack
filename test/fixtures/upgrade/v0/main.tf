provider "consul" {}

provider "nomad" {}

provider "vault" {}

variable "nomad_jwks_url" {
  type = string
}

variable "image" {
  type = string
}

variable "acme_ca_certificate" {
  type = string
}

module "workload_identity" {
  source = "git::https://github.com/eugene-panin/terraform-nomad-hashistack.git//modules/workload-identity?ref=v0.13.0"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = "kv"
}

module "traefik" {
  source = "git::https://github.com/eugene-panin/terraform-nomad-hashistack.git//modules/traefik?ref=v0.13.0"

  domain                = "hashistack.test"
  acme_email            = "admin@hashistack.test"
  acme_ca_server        = "https://pebble:14000/dir"
  acme_ca_certificate   = var.acme_ca_certificate
  dns_provider          = "exec"
  dns_provider_env      = { EXEC_PATH = "/bin/true" }
  dns_propagation_check = false
  public                = { enabled = true, http_port = 80, https_port = 9443 }
  consul                = { address = "consul:8500", scheme = "http" }
  image                 = var.image
  vault_kv_path         = module.workload_identity.vault_kv_path
}
