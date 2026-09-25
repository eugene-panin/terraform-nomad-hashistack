provider "consul" {}

provider "nomad" {}

provider "vault" {}

module "workload_identity" {
  source = "../../modules/workload-identity"
}

module "traefik" {
  source = "../../modules/traefik"
}
