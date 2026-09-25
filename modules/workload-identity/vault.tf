resource "vault_jwt_auth_backend" "this" {
  path               = var.vault_jwt_path
  description        = "Nomad workload identities"
  jwks_url           = var.nomad_jwks_url
  jwks_ca_pem        = var.nomad_jwks_ca_pem
  jwt_supported_algs = ["RS256"]
  default_role       = var.vault_role_name
}

resource "vault_mount" "kv" {
  count = var.create_vault_kv_mount ? 1 : 0

  path        = var.vault_kv_path
  type        = "kv"
  description = "Secrets of Nomad workloads, under <namespace>/<job>"
  options     = { version = "2" }
}

locals {
  alias_metadata = "identity.entity.aliases.${vault_jwt_auth_backend.this.accessor}.metadata"
  job_path       = "{{${local.alias_metadata}.nomad_namespace}}/{{${local.alias_metadata}.nomad_job_id}}"
}

resource "vault_policy" "workloads" {
  name   = var.vault_role_name
  policy = <<-EOT
    path "${var.vault_kv_path}/data/${local.job_path}" {
      capabilities = ["read"]
    }

    path "${var.vault_kv_path}/data/${local.job_path}/*" {
      capabilities = ["read"]
    }

    path "${var.vault_kv_path}/metadata/${local.job_path}/*" {
      capabilities = ["list"]
    }
  EOT
}

resource "vault_jwt_auth_backend_role" "workloads" {
  backend                 = vault_jwt_auth_backend.this.path
  role_name               = var.vault_role_name
  role_type               = "jwt"
  bound_audiences         = ["vault.io"]
  user_claim              = "/nomad_job_id"
  user_claim_json_pointer = true
  claim_mappings = {
    nomad_namespace = "nomad_namespace"
    nomad_job_id    = "nomad_job_id"
    nomad_task      = "nomad_task"
  }
  token_type     = "service"
  token_policies = [vault_policy.workloads.name]
  token_period   = var.vault_token_period
}
