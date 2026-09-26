output "dns_records" {
  description = "Public DNS records the platform needs, keyed by domain: the wildcard of the internal names. Publish them with modules/dns-cloudflare, together with the records of the apps, or by hand for other providers."
  value       = local.infra_records
}

output "ui_urls" {
  description = "Addresses of the Consul, Nomad and Vault UIs behind Traefik."
  value       = { for name, route in local.ui : name => "https://${route.host}" }
}

output "traefik_job_id" {
  description = "ID of the Traefik job in Nomad."
  value       = module.traefik.job_id
}

output "vault_kv_path" {
  description = "Path of the Vault KV version 2 engine apps keep their secrets in; a job reads <path>/<namespace>/<job>/*. Pass it to the vault_kv_path input of an app module."
  value       = module.workload_identity.vault_kv_path
}
