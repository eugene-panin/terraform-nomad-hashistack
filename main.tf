locals {
  domain = "service.consul"

  ui = {
    consul = { host = "consul.${local.domain}", url = "https://127.0.0.1:8501" }
    nomad  = { host = "nomad.${local.domain}", url = "https://${var.address}:4646" }
    vault  = { host = "vault.${local.domain}", url = "https://${var.address}:8200" }
  }

  dashboard_host = "traefik.${local.domain}"
}

module "workload_identity" {
  source = "./modules/workload-identity"

  nomad_jwks_url    = "https://${var.address}:4646/.well-known/jwks.json"
  nomad_jwks_ca_pem = var.ca_pem
}

resource "tls_private_key" "internal" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "internal" {
  private_key_pem = tls_private_key.internal.private_key_pem

  subject {
    common_name = "*.${local.domain}"
  }

  dns_names = ["*.${local.domain}", local.domain]
}

resource "tls_locally_signed_cert" "internal" {
  cert_request_pem      = tls_cert_request.internal.cert_request_pem
  ca_private_key_pem    = var.ca_key_pem
  ca_cert_pem           = var.ca_pem
  validity_period_hours = 19800
  early_renewal_hours   = 720

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

module "traefik" {
  source = "./modules/traefik"

  role   = "internal"
  domain = local.domain
  tls = {
    cert_pem = "${tls_locally_signed_cert.internal.cert_pem}${var.ca_pem}"
    key_pem  = tls_private_key.internal.private_key_pem
  }

  consul         = { ca_pem = var.ca_pem }
  routes         = local.ui
  backend_ca_pem = var.ca_pem
  dashboard_host = var.traefik_dashboard ? local.dashboard_host : null
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

removed {
  from = module.sso

  lifecycle {
    destroy = false
  }
}
