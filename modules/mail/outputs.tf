output "job_id" {
  description = "ID of the mail job in Nomad."
  value       = nomad_job.mail.id
}

output "data_volume" {
  description = "Name of the dynamic host volume holding the mail store."
  value       = nomad_dynamic_host_volume.data.name
}

output "passwords" {
  description = "Generated password of each account, keyed by address."
  value       = { for address, p in random_password.account : address => p.result }
  sensitive   = true
}

output "dns_records" {
  description = "DNS records each domain needs, keyed by domain: MX, SPF, two DKIM keys, DMARC, MTA-STS, TLS-RPT, and the service names that point at hostname. The A record of hostname itself is not included."
  value = {
    for d in var.domains : d => concat(
      [
        { type = "MX", name = d, content = var.hostname, priority = 10 },
        { type = "TXT", name = d, content = "v=spf1 mx -all", priority = null },
        { type = "TXT", name = "${var.dkim_selector}-ed25519._domainkey.${d}", content = "v=DKIM1; k=ed25519; p=${local.dkim_public[d].ed25519}", priority = null },
        { type = "TXT", name = "${var.dkim_selector}-rsa._domainkey.${d}", content = "v=DKIM1; k=rsa; p=${local.dkim_public[d].rsa}", priority = null },
        { type = "TXT", name = "_dmarc.${d}", content = "v=DMARC1; p=${var.dmarc_policy}; rua=mailto:postmaster@${d}", priority = null },
        { type = "TXT", name = "_mta-sts.${d}", content = "v=STSv1; id=${substr(sha256("${var.mta_sts_mode} ${var.hostname}"), 0, 20)}", priority = null },
        { type = "TXT", name = "_smtp._tls.${d}", content = "v=TLSRPTv1; rua=mailto:postmaster@${d}", priority = null },
      ],
      [for l in local.service_labels : { type = "CNAME", name = "${l}.${d}", content = var.hostname, priority = null }],
    )
  }
}
