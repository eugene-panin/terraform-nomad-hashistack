output "job_id" {
  description = "ID of the Traefik job in Nomad."
  value       = nomad_job.traefik.id
}

output "service_name" {
  description = "Name of the Consul service of the job."
  value       = local.job_name
}

output "entrypoints" {
  description = "Entrypoints this Traefik serves: internal, or public-http and public-https. Routers name them in traefik.<proto>.routers.<name>.entrypoints."
  value       = local.entrypoints
}

output "certresolver" {
  description = "Certificate resolver for routers on public-https (http, HTTP-01); null for the internal role, whose certificate is the one in tls."
  value       = local.public ? "http" : null
}

output "servers_transport" {
  description = "TCP servers transport that sends the PROXY protocol version 2 header, for TLS passthrough on public-https; null for the internal role."
  value       = local.public ? "proxy-protocol@file" : null
}

output "acme_volume" {
  description = "Name of the dynamic host volume holding the ACME account and certificates; null for the internal role."
  value       = local.public ? nomad_dynamic_host_volume.acme_storage[0].name : null
}

output "tag_regex" {
  description = "Regular expression a tag of a Consul service must match for this Traefik to read the service: a router on one of its entrypoints, such as traefik.http.routers.<name>.entrypoints=internal."
  value       = local.tag_regex
}
