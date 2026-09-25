output "record_ids" {
  description = "IDs of the Cloudflare records, keyed by \"<type> <name>\"."
  value       = { for k, r in cloudflare_dns_record.this : k => r.id }
}

output "zone_ids" {
  description = "Cloudflare zone ID of each domain."
  value       = { for d, z in data.cloudflare_zone.this : d => z.zone_id }
}
