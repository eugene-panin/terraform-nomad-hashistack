mock_provider "consul" {}
mock_provider "nomad" {}
mock_provider "vault" {}

mock_provider "tls" {
  mock_resource "tls_locally_signed_cert" {
    defaults = {
      cert_pem = "LEAF\n"
    }
  }
}

variables {
  address    = "10.0.0.1"
  ca_pem     = "CA\n"
  ca_key_pem = "CA-KEY"
}

run "platform" {
  command = apply

  assert {
    condition     = output.ui_urls == { consul = "https://consul.service.consul", nomad = "https://nomad.service.consul", vault = "https://vault.service.consul" }
    error_message = "The UIs must be at <svc>.service.consul."
  }

  assert {
    condition     = output.vault_kv_path == module.workload_identity.vault_kv_path
    error_message = "Apps are not given the KV engine of workload identity."
  }

  assert {
    condition     = output.traefik_job_id != null && module.traefik.service_name == "traefik" && join(",", module.traefik.entrypoints) == "internal"
    error_message = "The platform runs the internal Traefik as the job traefik."
  }

  assert {
    condition     = module.traefik.acme_volume == null && module.traefik.certresolver == null
    error_message = "The platform's Traefik must have no ACME."
  }

  assert {
    condition     = toset(tls_cert_request.internal.dns_names) == toset(["*.service.consul", "service.consul"]) && tls_cert_request.internal.subject[0].common_name == "*.service.consul"
    error_message = "The internal certificate must be for *.service.consul and service.consul."
  }

  assert {
    condition     = tls_locally_signed_cert.internal.ca_cert_pem == var.ca_pem && tls_locally_signed_cert.internal.validity_period_hours <= 19800 && contains(tls_locally_signed_cert.internal.allowed_uses, "server_auth")
    error_message = "The internal certificate must be a server certificate signed by the project CA, valid no longer than Apple platforms accept."
  }

  assert {
    condition     = module.traefik.tag_regex != null && can(regex(module.traefik.tag_regex, "traefik.http.routers.grafana.entrypoints=internal")) && !can(regex(module.traefik.tag_regex, "traefik.http.routers.odoo.entrypoints=public-https"))
    error_message = "The platform's Traefik must read internal routers only."
  }
}

run "traefik_dashboard_is_listed_when_on" {
  command = apply

  variables {
    traefik_dashboard = true
  }

  assert {
    condition     = output.ui_urls["traefik"] == "https://traefik.service.consul"
    error_message = "Traefik's dashboard must be at traefik.service.consul."
  }
}

run "memory_oversubscription_is_on" {
  command = apply

  assert {
    condition     = nomad_scheduler_config.this.memory_oversubscription_enabled && nomad_scheduler_config.this.scheduler_algorithm == "binpack"
    error_message = "Tasks must be able to reserve their usual memory and grow to memory_max, on the binpack scheduler."
  }
}
