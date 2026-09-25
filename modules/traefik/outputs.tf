output "job_id" {
  description = "ID of the Traefik job in Nomad."
  value       = nomad_job.traefik.id
}

output "acme_volume" {
  description = "Name of the dynamic host volume holding the ACME account and certificates."
  value       = nomad_dynamic_host_volume.acme.name
}

output "secret_path" {
  description = "Path in Vault the DNS provider environment is written to."
  value       = "${var.vault_kv_path}/${local.secret_name}"
}
