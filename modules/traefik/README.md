# traefik

Runs Traefik as a Nomad job with two faces. The internal entrypoint serves
`*.<domain>` with a wildcard certificate from a DNS-01 challenge, so internal
names need no public DNS records pointing at them. The optional public
entrypoints serve whatever a service asks for, with certificates from an
HTTP-01 challenge, and redirect plain HTTP to HTTPS.

```hcl
module "traefik" {
  source  = "eugene-panin/hashistack/nomad//modules/traefik"
  version = "~> 0.3"

  domain           = "infra.example.com"
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = var.cloudflare_api_token }
  vault_kv_path    = module.workload_identity.vault_kv_path

  internal = { host_network = "default" }
  public   = { enabled = true, host_network = "public" }

  consul = { ca_pem = file("consul-ca.pem") }

  routes = {
    nomad = { host = "nomad.infra.example.com", url = "https://127.0.0.1:4646" }
  }
  backend_ca_pem = file("nomad-ca.pem")
}
```

## What it creates

- A KV secret at `<vault_kv_path>/<namespace>/<job_name>/acme` holding
  `dns_provider_env`. The value is write-only: it never reaches the state or
  the plan. Change `dns_provider_env_version` to write a new one.
- A dynamic host volume `<job_name>-acme`, owned by `nobody`, where Traefik
  keeps its ACME account and certificates across allocations.
- The job. Traefik runs with the `exec` driver as `nobody`, from the official
  release checked against its checksums file, with every capability dropped
  except `net_bind_service`. It reads the Consul catalog with its own
  workload identity, and the DNS provider credentials from Vault with its
  own.

A Consul service is exposed only with the tag `traefik.enable=true`. Without
further tags it gets `Host(<service>.<domain>)` on the internal entrypoint.
A public site names its rule and entrypoint:

```hcl
service {
  name = "site"
  port = "http"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.site.rule=Host(`www.example.org`)",
    "traefik.http.routers.site.entrypoints=public-https",
  ]
}
```

`routes` adds backends that are not in the Consul catalog, such as the Nomad,
Consul and Vault UIs; they are served on the internal entrypoint only.

For TCP services that pass TLS through, the dynamic configuration has a TCP
servers transport `proxy-protocol` that sends the PROXY protocol version 2
header, so the backend sees the client's address. A service uses it with
`traefik.tcp.services.<name>.loadbalancer.serverstransport=proxy-protocol@file`;
the `mail` module does, and its test covers it.

## Requirements on the cluster

- The `workload-identity` module, or equivalent: Traefik's task needs a Consul
  token that reads the catalog and a Vault token that reads its own secret.
- The `exec` driver and the `mkdir` host volume plugin on the client, and the
  host networks named in `internal` and `public`.
- Clients reach GitHub releases to fetch Traefik, with system CA certificates.

## Tested

The test runs Consul, Vault, Nomad and the Pebble ACME server in Docker, with
ports below 1024 privileged in the Nomad container, and applies the module on
ports 443, 80 and 9443. A second plan must be empty, the DNS provider
credentials must be in Vault and absent from the state. Then:

- a service with only `traefik.enable=true` is served on the internal
  entrypoint with a certificate for `<domain>` and `*.<domain>`, verified
  against Pebble's root;
- a static route reaches Nomad's API on the internal entrypoint;
- a service that names `public-https` is served there with a certificate for
  its own host;
- the internal service and the static route answer 404 on the public
  entrypoint, and the public service 404 on the internal one;
- plain HTTP on the public entrypoint redirects to HTTPS;
- a replacement allocation serves the same certificate, read from the volume.

Each of these fails when its part of the job is removed: the capability, the
internal entrypoint as default, the storage on the volume, the secret as
environment, the wildcard, the redirect, and the ACME server's CA.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| nomad | >= 2.5, < 3.0 |
| vault | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| nomad | >= 2.5, < 3.0 |
| vault | >= 5.0, < 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| acme\_ca\_certificate | PEM CA the ACME server's own TLS certificate is signed by, for a private ACME server. Null trusts the system store. | `string` | `null` | no |
| acme\_ca\_server | ACME directory URL. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| acme\_email | Contact address for the ACME account. | `string` | n/a | yes |
| backend\_ca\_pem | PEM CA that signs the certificates of the backends in routes. Null trusts the system store. | `string` | `null` | no |
| consul | Consul agent Traefik reads the catalog from, as the task's own identity. | <pre>object({<br/>    address = optional(string, "127.0.0.1:8501")<br/>    scheme  = optional(string, "https")<br/>    ca_pem  = optional(string)<br/>  })</pre> | `{}` | no |
| datacenters | Datacenters the job may run in. | `list(string)` | <pre>[<br/>  "*"<br/>]</pre> | no |
| dns\_propagation\_check | Wait until the DNS-01 record is visible before asking for validation. | `bool` | `true` | no |
| dns\_provider | Provider for the DNS-01 challenge, by its lego name, such as cloudflare. | `string` | `"cloudflare"` | no |
| dns\_provider\_env | Environment the DNS provider needs, such as { CF\_DNS\_API\_TOKEN = "..." }. Written to Vault as a write-only value, so it never reaches the state, and read by the job with its own identity. | `map(string)` | n/a | yes |
| dns\_provider\_env\_version | Version of dns\_provider\_env. Raise it to write a changed value to Vault; a write-only value is not compared otherwise. | `number` | `1` | no |
| domain | Domain Traefik serves on the internal entrypoint. It gets one wildcard certificate, *.<domain>, through DNS-01. | `string` | n/a | yes |
| internal | Internal entrypoint: the Nomad host network it binds to and its port. Routers use it unless they name another. | <pre>object({<br/>    host_network = optional(string, "default")<br/>    port         = optional(number, 443)<br/>  })</pre> | `{}` | no |
| job\_name | Name of the Nomad job; also the second segment of its secret path in Vault. | `string` | `"traefik"` | no |
| namespace | Nomad namespace of the job; also the first segment of its secret path in Vault. | `string` | `"default"` | no |
| public | Public entrypoints, HTTP redirecting to HTTPS, with certificates through HTTP-01. Only routers that name public-https use them. | <pre>object({<br/>    enabled      = optional(bool, false)<br/>    host_network = optional(string, "public")<br/>    http_port    = optional(number, 80)<br/>    https_port   = optional(number, 443)<br/>  })</pre> | `{}` | no |
| routes | Routes to backends outside Nomad, such as the Nomad, Consul and Vault UIs, on the internal entrypoint, keyed by name. | <pre>map(object({<br/>    host = string<br/>    url  = string<br/>  }))</pre> | `{}` | no |
| traefik\_version | Traefik release, downloaded from GitHub and checked against its published checksums. | `string` | `"3.7.13"` | no |
| vault\_kv\_path | Path of the KV version 2 engine the workload-identity module mounts. | `string` | `"secret"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| acme\_volume | Name of the dynamic host volume holding the ACME account and certificates. |
| job\_id | ID of the Traefik job in Nomad. |
| secret\_path | Path in Vault the DNS provider environment is written to. |
<!-- END_TF_DOCS -->
