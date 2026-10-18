output "ui_urls" {
  description = "Addresses of the Consul, Nomad and Vault UIs behind the internal Traefik, and of Traefik's dashboard when traefik_dashboard is on."
  value = merge(
    { for name, route in local.ui : name => "https://${route.host}" },
    var.traefik_dashboard ? { traefik = "https://${local.dashboard_host}" } : {},
  )
}

output "traefik_job_id" {
  description = "ID of the internal Traefik job in Nomad."
  value       = module.traefik.job_id
}

output "vault_kv_path" {
  description = "Path of the Vault KV version 2 engine apps keep their secrets in; a job reads <path>/<namespace>/<job>/*. Pass it to the vault_kv_path input of an app module."
  value       = module.workload_identity.vault_kv_path
}
