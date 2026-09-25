provider "consul" {}

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

module "workload_identity" {
  source = "../../modules/workload-identity"

  nomad_jwks_url = var.nomad_jwks_url
  vault_kv_path  = var.vault_kv_path
}

output "vault_kv_path" {
  description = "Path of the KV engine workloads read their secrets from."
  value       = module.workload_identity.vault_kv_path
}
