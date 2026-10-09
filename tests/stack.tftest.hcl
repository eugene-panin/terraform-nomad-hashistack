mock_provider "consul" {}
mock_provider "nomad" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "vault" {}

variables {
  infra_domain     = "infra.example.com"
  address          = "10.0.0.1"
  ca_pem           = "ca"
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = "token" }
}

run "platform" {
  command = apply

  assert {
    condition = output.dns_records == {
      "infra.example.com" = [{
        type = "A", name = "*.infra.example.com", content = "10.0.0.1", priority = null, comment = "Internal names, reachable through WireGuard only"
      }]
    }
    error_message = "The platform should publish exactly the internal wildcard, pointing at address."
  }

  assert {
    condition     = output.ui_urls == { consul = "https://consul.infra.example.com", nomad = "https://nomad.infra.example.com", vault = "https://vault.infra.example.com" }
    error_message = "The UI addresses are not under the internal domain."
  }

  assert {
    condition     = output.vault_kv_path == module.workload_identity.vault_kv_path
    error_message = "Apps are not given the KV engine of workload identity."
  }

  assert {
    condition     = output.traefik_job_id != null
    error_message = "The Traefik job was not created."
  }
}

run "internal_ca_mode_renders" {
  command = apply

  variables {
    internal_tls     = { mode = "ca", cert_pem = "CERT", key_pem = "KEY" }
    dns_provider_env = {}
  }

  assert {
    condition     = output.traefik_job_id != null
    error_message = "The Traefik job was not created with an internal-CA certificate."
  }
}
