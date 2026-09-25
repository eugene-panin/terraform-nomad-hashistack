variable "nomad_jwks_url" {
  description = "URL of the JWKS endpoint of the Nomad servers, such as https://10.0.0.10:4646/.well-known/jwks.json. Consul and Vault fetch the keys that sign workload identities from it."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.nomad_jwks_url))
    error_message = "nomad_jwks_url must be an http or https URL."
  }
}

variable "nomad_jwks_ca_pem" {
  description = "PEM CA that signs the certificate of the JWKS endpoint. Null trusts the system store, as for a plain http endpoint."
  type        = string
  default     = null
}

variable "consul_auth_method_name" {
  description = "Name of the Consul auth method. It must match the auth method the Nomad agents are configured with, nomad-workloads by default in both."
  type        = string
  default     = "nomad-workloads"
}

variable "consul_task_policy_rules" {
  description = "Consul ACL rules for tasks, the identity a task's template and Consul block use. Services get a service identity of their own and are not affected."
  type        = string
  default     = <<-EOT
    service_prefix "" {
      policy = "read"
    }
    node_prefix "" {
      policy = "read"
    }
  EOT
}

variable "vault_jwt_path" {
  description = "Path to mount the Vault JWT auth method at. It must match nomad_vault_jwt_auth_path on the Nomad agents, jwt-nomad by default in both."
  type        = string
  default     = "jwt-nomad"
}

variable "vault_role_name" {
  description = "Name of the Vault role workloads log in with; also the auth method's default role."
  type        = string
  default     = "nomad-workloads"
}

variable "vault_kv_path" {
  description = "Path of the KV version 2 engine workloads read their secrets from. A job reads <path>/<namespace>/<job>/*."
  type        = string
  default     = "secret"
}

variable "create_vault_kv_mount" {
  description = "Mount the KV engine at vault_kv_path. Turn off when a KV version 2 engine is already mounted there."
  type        = bool
  default     = true
}

variable "vault_token_period" {
  description = "Period of the Vault tokens workloads get, in seconds. Nomad renews them while the task runs."
  type        = number
  default     = 1800

  validation {
    condition     = var.vault_token_period >= 60
    error_message = "vault_token_period must be at least 60 seconds."
  }
}
