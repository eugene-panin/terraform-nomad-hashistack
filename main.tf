locals {
  ui = {
    consul = { host = "consul.${var.infra_domain}", url = "https://127.0.0.1:8501" }
    nomad  = { host = "nomad.${var.infra_domain}", url = "https://${var.address}:4646" }
    vault  = { host = "vault.${var.infra_domain}", url = "https://${var.address}:8200" }
  }

  infra_records = {
    (var.infra_domain) = [{
      type     = "A"
      name     = "*.${var.infra_domain}"
      content  = var.address
      priority = null
      comment  = "Internal names, reachable through WireGuard only"
    }]
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
  internal_tls             = var.internal_tls
  vault_kv_path            = module.workload_identity.vault_kv_path

  public         = { enabled = var.public }
  consul         = { ca_pem = var.ca_pem }
  routes         = local.ui
  dashboard_host = var.traefik_dashboard ? "traefik.${var.infra_domain}" : null
  backend_ca_pem = var.ca_pem
}

# The scheduler as it was set up (binpack, preemption for system jobs only), with
# memory oversubscription on: a task reserves its usual memory (resources.memory,
# what placement counts) and may grow to resources.memory_max, so reservations
# follow real use instead of the worst case.
resource "nomad_scheduler_config" "this" {
  scheduler_algorithm             = "binpack"
  memory_oversubscription_enabled = true
  preemption_config = {
    batch_scheduler_enabled    = false
    service_scheduler_enabled  = false
    sysbatch_scheduler_enabled = false
    system_scheduler_enabled   = true
  }
}
