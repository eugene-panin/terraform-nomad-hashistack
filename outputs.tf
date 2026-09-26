output "dns_records" {
  description = "Public DNS records the stack needs, keyed by domain: the internal wildcard, and every record of the mail domains. Publish them with modules/dns-cloudflare, or by hand for other providers."
  value = {
    for d in setunion(keys(local.infra_records), keys(local.mail_records)) :
    d => concat(try(local.infra_records[d], []), try(local.mail_records[d], []))
  }
}

output "ui_urls" {
  description = "Addresses of the Consul, Nomad and Vault UIs behind Traefik."
  value       = { for name, route in local.ui : name => "https://${route.host}" }
}

output "mailboxes" {
  description = "Mailboxes keyed by address, with the aliases each one also receives."
  value       = { for address, box in local.mailboxes : address => box.aliases }
}

output "mail_passwords" {
  description = "Generated password of each mailbox."
  value       = var.mail == null ? {} : module.mail[0].passwords
  sensitive   = true
}

output "traefik_job_id" {
  description = "ID of the Traefik job in Nomad."
  value       = module.traefik.job_id
}

output "mail_job_id" {
  description = "ID of the mail job in Nomad, or null without mail."
  value       = var.mail == null ? null : module.mail[0].job_id
}
