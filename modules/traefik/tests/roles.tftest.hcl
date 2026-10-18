mock_provider "nomad" {}

variables {
  tls = {
    cert_pem = "-----BEGIN CERTIFICATE-----\nINTERNAL-CERT\n-----END CERTIFICATE-----\n"
    key_pem  = "-----BEGIN PRIVATE KEY-----\nINTERNAL-KEY\n-----END PRIVATE KEY-----\n"
  }
  routes = {
    nomad = { host = "nomad.service.consul", url = "https://10.0.0.1:4646" }
  }
  backend_ca_pem = "BACKEND-CA"
  acme_email     = "admin@example.com"
}

run "internal_role" {
  command = apply

  variables {
    role = "internal"
  }

  assert {
    condition     = output.service_name == "traefik" && strcontains(nomad_job.traefik.jobspec, "job \"traefik\" {") && strcontains(nomad_job.traefik.jobspec, "name     = \"traefik\"")
    error_message = "The internal role is the job and Consul service traefik."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "port \"internal\" {\n        static       = 443\n        host_network = \"default\"")
    error_message = "The entrypoint internal must bind 443 on the host network default."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "internal:\n              address: \"[[ env \"NOMAD_IP_internal\" ]]:[[ env \"NOMAD_PORT_internal\" ]]\"\n              asDefault: true\n              http:\n                tls: {}")
    error_message = "The entrypoint internal must be the default one and serve TLS with the default certificate."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "defaultRule: 'Host(`{{ normalize .Name }}.service.consul`)'")
    error_message = "Services must default to <service>.service.consul."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "constraints: 'TagRegex(`${output.tag_regex}`)'") && strcontains(output.tag_regex, "internal")
    error_message = "The internal role must read only services with a router on internal."
  }

  assert {
    condition     = nomad_variable.tls[0].path == "nomad/jobs/traefik" && nomad_variable.tls[0].items.tls_cert == var.tls.cert_pem && nomad_variable.tls[0].items.tls_key == var.tls.key_pem
    error_message = "The certificate and key must be in the Nomad variable of the job."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "{{ with nomadVar \"nomad/jobs/traefik\" }}{{ .tls_cert }}{{ end }}") && strcontains(nomad_job.traefik.jobspec, "certFile: /local/internal-cert.pem") && strcontains(nomad_job.traefik.jobspec, "keyFile: /local/internal-key.pem")
    error_message = "The default certificate must come from the Nomad variable."
  }

  assert {
    condition     = !strcontains(nomad_job.traefik.jobspec, "INTERNAL-KEY") && !strcontains(nomad_job.traefik.jobspec, "INTERNAL-CERT")
    error_message = "The certificate and key must not be in the job."
  }

  assert {
    condition     = !strcontains(lower(nomad_job.traefik.jobspec), "acme") && !strcontains(nomad_job.traefik.jobspec, "certResolver") && !strcontains(nomad_job.traefik.jobspec, "volume") && length(nomad_dynamic_host_volume.acme_storage) == 0 && output.acme_volume == null && output.certresolver == null
    error_message = "The internal role must have no ACME at all."
  }

  assert {
    condition     = !strcontains(nomad_job.traefik.jobspec, "public") && !strcontains(nomad_job.traefik.jobspec, "proxy-protocol") && join(",", output.entrypoints) == "internal"
    error_message = "The internal role must have no public entrypoint."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "nomad:\n                rule: 'Host(`nomad.service.consul`)'") && strcontains(nomad_job.traefik.jobspec, "- url: \"https://10.0.0.1:4646\"") && strcontains(nomad_job.traefik.jobspec, "- /local/backend-ca.pem")
    error_message = "The routes must reach their backends with the CA as rootCAs."
  }

  assert {
    condition     = !strcontains(nomad_job.traefik.jobspec, "api@internal")
    error_message = "The dashboard is off unless dashboard_host is set."
  }
}

run "internal_dashboard" {
  command = apply

  variables {
    role           = "internal"
    dashboard_host = "traefik.service.consul"
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "rule: 'Host(`traefik.service.consul`)'") && strcontains(nomad_job.traefik.jobspec, "service: api@internal")
    error_message = "The dashboard is served at dashboard_host."
  }
}

run "internal_needs_tls" {
  command = plan

  variables {
    role = "internal"
    tls  = null
  }

  expect_failures = [var.tls]
}

run "public_role" {
  command = apply

  variables {
    role = "public"
  }

  assert {
    condition     = output.service_name == "traefik-public" && strcontains(nomad_job.traefik.jobspec, "job \"traefik-public\" {") && strcontains(nomad_job.traefik.jobspec, "name     = \"traefik-public\"")
    error_message = "The public role is the job and Consul service traefik-public."
  }

  assert {
    condition     = nomad_dynamic_host_volume.acme_storage[0].name == "traefik-public-certificates" && output.acme_volume == "traefik-public-certificates" && strcontains(nomad_job.traefik.jobspec, "source          = \"traefik-public-certificates\"")
    error_message = "The public role keeps ACME on its own volume."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "port \"public_http\" {\n        static       = 80\n        host_network = \"public\"") && strcontains(nomad_job.traefik.jobspec, "port \"public_https\" {\n        static       = 443\n        host_network = \"public\"")
    error_message = "public-http and public-https must bind 80 and 443 on the host network public."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "public-http:\n              address: \"[[ env \"NOMAD_IP_public_http\" ]]:[[ env \"NOMAD_PORT_public_http\" ]]\"\n              http:\n                redirections:\n                  entryPoint:\n                    to: public-https\n                    scheme: https")
    error_message = "public-http must redirect to public-https."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "public-https:\n              address: \"[[ env \"NOMAD_IP_public_https\" ]]:[[ env \"NOMAD_PORT_public_https\" ]]\"\n              http:\n                tls:\n                  certResolver: http")
    error_message = "public-https must use the resolver http."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "            http:\n              acme:\n                email: \"admin@example.com\"\n                caServer: \"https://acme-v02.api.letsencrypt.org/directory\"\n                storage: /acme/http.json\n                httpChallenge:\n                  entryPoint: public-http")
    error_message = "The resolver http must answer HTTP-01 on public-http and keep its storage on the volume."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "tcp:\n            serversTransports:\n              proxy-protocol:\n                proxyProtocol:\n                  version: 2") && output.servers_transport == "proxy-protocol@file" && output.certresolver == "http"
    error_message = "The TCP servers transport proxy-protocol must send PROXY protocol version 2."
  }

  assert {
    condition     = strcontains(nomad_job.traefik.jobspec, "prefix: traefik\n              constraints: 'TagRegex(`${output.tag_regex}`)'") && strcontains(output.tag_regex, "public-https?")
    error_message = "The public role must read only services with a router on a public entrypoint, under the tag prefix traefik."
  }

  assert {
    condition     = !strcontains(nomad_job.traefik.jobspec, "NOMAD_PORT_internal") && !strcontains(nomad_job.traefik.jobspec, "defaultRule") && !strcontains(nomad_job.traefik.jobspec, "nomad.service.consul") && !strcontains(nomad_job.traefik.jobspec, "nomadVar") && length(nomad_variable.tls) == 0
    error_message = "The public role must have no internal entrypoint, no default rule, no routes and no internal certificate."
  }

  assert {
    condition     = join(",", output.entrypoints) == "public-http,public-https"
    error_message = "The public role serves public-http and public-https."
  }
}

run "public_needs_acme_email" {
  command = plan

  variables {
    role       = "public"
    acme_email = null
  }

  expect_failures = [var.acme_email]
}

run "role_is_checked" {
  command = plan

  variables {
    role = "both"
  }

  expect_failures = [var.role]
}

run "internal_reads_internal_routers_only" {
  command = plan

  variables {
    role = "internal"
  }

  assert {
    condition = alltrue([for tag in [
      "traefik.http.routers.grafana.entrypoints=internal",
      "traefik.http.routers.grafana.entryPoints=internal",
      "traefik.tcp.routers.db.entrypoints=internal",
      "traefik.http.routers.app.entrypoints=public-https,internal",
    ] : can(regex(output.tag_regex, tag))])
    error_message = "A router on internal must be read by the internal role."
  }

  assert {
    condition = !anytrue([for tag in [
      "traefik.enable=true",
      "traefik.http.routers.odoo.entrypoints=public-https",
      "traefik.tcp.routers.mail.entrypoints=public-https",
      "traefik.http.routers.x.entrypoints=internal-extra",
      "traefik.http.routers.x.rule=Host(`internal`)",
    ] : can(regex(output.tag_regex, tag))])
    error_message = "A service without a router on internal must not be read by the internal role."
  }
}

run "public_reads_public_routers_only" {
  command = plan

  variables {
    role = "public"
  }

  assert {
    condition = alltrue([for tag in [
      "traefik.http.routers.odoo.entrypoints=public-https",
      "traefik.http.routers.odoo-ws.entrypoints=public-https",
      "traefik.tcp.routers.mail.entrypoints=public-https",
      "traefik.http.routers.plain.entrypoints=public-http",
      "traefik.http.routers.app.entrypoints=internal,public-https",
    ] : can(regex(output.tag_regex, tag))])
    error_message = "A router on public-https or public-http must be read by the public role."
  }

  assert {
    condition = !anytrue([for tag in [
      "traefik.enable=true",
      "traefik.http.routers.grafana.entrypoints=internal",
      "traefik.http.routers.x.entrypoints=public-httpsx",
    ] : can(regex(output.tag_regex, tag))])
    error_message = "A service without a router on a public entrypoint must not be read by the public role."
  }
}

run "both_roles_side_by_side" {
  command = apply

  module {
    source = "./tests/both"
  }

  variables {
    tls        = null
    routes     = null
    acme_email = null
  }

  assert {
    condition     = output.internal.service_name != output.public.service_name
    error_message = "The two roles must be different jobs and Consul services."
  }

  assert {
    condition     = output.internal.acme_volume == null && output.public.acme_volume == "traefik-public-certificates"
    error_message = "Only the public role has an ACME volume, under its own name."
  }

  assert {
    condition     = length(setintersection(output.internal.entrypoints, output.public.entrypoints)) == 0
    error_message = "The two roles must serve different entrypoints."
  }

  assert {
    condition     = output.internal.tag_regex != output.public.tag_regex
    error_message = "The two roles must read different services of the catalog."
  }
}
