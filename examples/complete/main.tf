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

module "traefik" {
  source = "../../modules/traefik"
}
