output "record_ids" {
  description = "IDs of the Cloudflare records, keyed by \"<type> <name>\"."
  value       = { for k, r in cloudflare_dns_record.this : k => r.id }
}

output "zone_ids" {
  description = "Cloudflare zone ID of each domain, the zone it is or is under."
  value       = { for d in local.domains : d => data.cloudflare_zone.this[local.zone_of[d]].zone_id }
}
