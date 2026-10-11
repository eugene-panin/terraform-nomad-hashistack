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

run "traefik_dashboard_is_listed_when_on" {
  command = apply

  variables {
    traefik_dashboard = true
  }

  assert {
    condition     = output.ui_urls["traefik"] == "https://traefik.infra.example.com"
    error_message = "Traefik's dashboard is not served under the internal domain."
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

run "memory_oversubscription_is_on" {
  command = apply

  assert {
    condition     = nomad_scheduler_config.this.memory_oversubscription_enabled && nomad_scheduler_config.this.scheduler_algorithm == "binpack"
    error_message = "Tasks must be able to reserve their usual memory and grow to memory_max, on the binpack scheduler."
  }
}

run "sso_is_off_by_default" {
  command = plan

  assert {
    condition     = length(module.sso) == 0 && output.sso == null
    error_message = "Without sso there is no sign-in method and no OIDC provider."
  }
}

run "sso_signs_people_in_through_vault" {
  command = apply

  variables {
    sso = {
      google_client_id = "123-abc.apps.googleusercontent.com"
      admins           = ["a@example.com"]
    }
    sso_google_client_secret = "secret"
  }

  assert {
    condition     = length(module.sso) == 1 && output.sso.admin_group == "platform-admins"
    error_message = "With sso the platform signs people in through Vault's OIDC provider."
  }
}
