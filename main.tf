locals {
  ui = {
    consul = { host = "consul.${var.infra_domain}", url = "https://127.0.0.1:8501" }
    nomad  = { host = "nomad.${var.infra_domain}", url = "https://${var.address}:4646" }
    vault  = { host = "vault.${var.infra_domain}", url = "https://${var.address}:8200" }
  }

  mailboxes = var.mail == null ? {} : merge([
    for d in var.mail.domains : {
      for i, m in var.mail.mailboxes : "${m}@${d}" => {
        aliases = i == 0 ? ["postmaster@${d}", "abuse@${d}"] : []
      }
    }
  ]...)

  infra_records = {
    (var.infra_domain) = [{
      type     = "A"
      name     = "*.${var.infra_domain}"
      content  = var.address
      priority = null
      comment  = "Internal names, reachable through WireGuard only"
    }]
  }

  mail_records = var.mail == null ? {} : {
    for d, records in module.mail[0].dns_records : d => [
      for r in records : merge(r, { comment = "Mail, managed by OpenTofu" })
    ]
  }
}

module "workload_identity" {
  source = "./modules/workload-identity"

  nomad_jwks_url    = "https://${var.address}:4646/.well-known/jwks.json"
  nomad_jwks_ca_pem = var.ca_pem
}

module "traefik" {
  source = "./modules/traefik"

  domain                   = var.infra_domain
  acme_email               = var.acme_email
  dns_provider             = var.dns_provider
  dns_provider_env         = var.dns_provider_env
  dns_provider_env_version = var.dns_provider_env_version
  vault_kv_path            = module.workload_identity.vault_kv_path

  public         = { enabled = var.public }
  consul         = { ca_pem = var.ca_pem }
  routes         = local.ui
  backend_ca_pem = var.ca_pem
}

module "mail" {
  source = "./modules/mail"
  count  = var.mail == null ? 0 : 1

  hostname      = var.mail.hostname
  domains       = var.mail.domains
  accounts      = local.mailboxes
  acme_email    = coalesce(var.mail.acme_email, var.acme_email)
  dmarc_policy  = var.mail.dmarc_policy
  mta_sts_mode  = var.mail.mta_sts_mode
  vault_kv_path = module.workload_identity.vault_kv_path
}
