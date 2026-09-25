output "consul_auth_method_name" {
  description = "Name of the Consul auth method Nomad workloads log in with."
  value       = consul_acl_auth_method.this.name
}

output "consul_task_policy_name" {
  description = "Name of the Consul policy tasks get; attach more rules to it by replacing consul_task_policy_rules."
  value       = consul_acl_policy.tasks.name
}

output "vault_jwt_path" {
  description = "Path of the Vault JWT auth method."
  value       = vault_jwt_auth_backend.this.path
}

output "vault_jwt_accessor" {
  description = "Accessor of the Vault JWT auth method, for policies that template on workload identity metadata."
  value       = vault_jwt_auth_backend.this.accessor
}

output "vault_role_name" {
  description = "Name of the Vault role Nomad workloads log in with."
  value       = vault_jwt_auth_backend_role.workloads.role_name
}

output "vault_kv_path" {
  description = "Path of the KV version 2 engine; a job reads <path>/<namespace>/<job>/*."
  value       = var.create_vault_kv_mount ? vault_mount.kv[0].path : var.vault_kv_path
}
