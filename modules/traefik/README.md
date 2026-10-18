# traefik

Runs Traefik as a Nomad job in one of two roles. Call the module once per
role; both can run on one host, as different jobs, Consul services and names,
on different host networks.

- `internal`: the entrypoint `internal` on the host network `default` (the
  private network, WireGuard), port 443, with the certificate given in `tls`,
  signed by the project CA for `*.service.consul` and `service.consul`.
  Services of the Consul catalog are served at `<service>.service.consul`
  unless they name a rule, and `routes` adds backends outside Nomad, such as the
  Consul, Nomad and Vault UIs. No ACME. Job and Consul service `traefik`.
- `public`: the entrypoints `public-http`, which redirects to HTTPS, and
  `public-https` on the host network `public`, ports 80 and 443, with
  certificates from the resolver `http` (Let's Encrypt, HTTP-01) and the TCP
  servers transport `proxy-protocol@file`. Job and Consul service
  `traefik-public`, ACME storage on the volume `traefik-public-certificates`.

```hcl
module "traefik" {
  source  = "eugene-panin/hashistack/nomad//modules/traefik"
  version = "~> 1.0"

  role = "internal"
  tls  = { cert_pem = local.cert_pem, key_pem = local.key_pem }

  consul = { ca_pem = file("ca.pem") }
  routes = {
    nomad = { host = "nomad.service.consul", url = "https://10.77.0.1:4646" }
  }
  backend_ca_pem = file("ca.pem")
}

module "traefik_public" {
  source  = "eugene-panin/hashistack/nomad//modules/traefik"
  version = "~> 1.0"

  role       = "public"
  acme_email = "admin@example.com"
  consul     = { ca_pem = file("ca.pem") }
}
```

## Which services a role serves

Both roles read the catalog under the tag prefix `traefik` and need
`traefik.enable=true`. Each reads only the services with a router on one of
its entrypoints, through a `constraints` `TagRegex` (the `tag_regex` output):
a tag `traefik.<http|tcp|udp>.routers.<name>.entrypoints=` that lists
`internal`, or `public-http`/`public-https`. A service with
`traefik.enable=true` alone is served by neither.

An internal app:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.grafana.entrypoints=internal",
]
```

It is served at `grafana.service.consul` with the certificate of the
entrypoint; it names no certificate resolver, the internal role has none.

A public app names its rule and entrypoint:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.site.rule=Host(`www.example.org`)",
  "traefik.http.routers.site.entrypoints=public-https",
  "traefik.http.routers.site.tls.certresolver=http",
]
```

For TCP services that pass TLS through, the public role has the TCP servers
transport `proxy-protocol`, which sends the PROXY protocol version 2 header, so
the backend sees the client's address:
`traefik.tcp.services.<name>.loadbalancer.serverstransport=proxy-protocol@file`.

## What it creates

- The job. Traefik runs with the `docker` driver from the official image,
  pinned by its digest, on the network of the host, so that it binds the
  addresses of the host networks and sees the addresses of the clients. It
  binds ports below 1024, so it runs as root of its container with every
  capability dropped except `net_bind_service`, a read-only root file system
  and `no-new-privileges`. It reads the Consul catalog with its own workload
  identity.
- Internal role: the Nomad variable `nomad/jobs/<job_name>` with the
  certificate and key, which the job reads with its own identity; they are not
  in the job.
- Public role: a dynamic host volume `<job_name>-certificates`, owned by root
  and closed to everyone else, where Traefik keeps its ACME account and
  certificates across allocations.

## Requirements on the cluster

- The `workload-identity` module, or equivalent: Traefik's task needs a Consul
  token that reads the catalog.
- The `docker` driver on the client, the `mkdir` host volume plugin for the
  public role, and the host networks named in `internal` and `public`.
- Clients pull the image, from Docker Hub unless `image` names another
  registry.

## Tested

`tofu test` with a mocked provider renders both roles and checks their jobs:
the entrypoints, host networks, rules, resolver, transport, the certificate in
the Nomad variable and not in the job, no ACME in the internal role, the names
of both roles apart, and which tags each role reads.

The Terratest test runs Consul, Vault, Nomad, a Docker daemon in the network of
Nomad and the Pebble ACME server in Docker, and applies both roles, the internal
one on port 443 and the public one on 80 and 9443. A second plan must be empty.
Then:

- a service with a router on `internal` is served at
  `<service>.service.consul` with the certificate of the project CA;
- a static route reaches Nomad's API on the internal entrypoint;
- a service that names `public-https` is served there with a certificate for
  its own host;
- internal services and routes answer 404 on the public entrypoint, the
  public service 404 on the internal one, and a service with only
  `traefik.enable=true` 404 on both;
- plain HTTP on the public entrypoint redirects to HTTPS;
- a replacement public allocation serves the same certificate, read from the
  volume.

Another test applies the module of 0.13.0, upgrades it to the internal role
and checks the plan: the job updated in place, the DNS secret deleted, the old
volume forgotten and left in Nomad.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| nomad | >= 2.5, < 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| nomad | >= 2.5, < 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| acme\_ca\_certificate | Public role: PEM CA the ACME server's own TLS certificate is signed by, for a private ACME server. Null trusts the system store. | `string` | `null` | no |
| acme\_ca\_server | Public role: ACME directory URL. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| acme\_email | Public role: contact address for the ACME account. | `string` | `null` | no |
| backend\_ca\_pem | Internal role: PEM CA that signs the certificates of the backends in routes. Null trusts the system store. | `string` | `null` | no |
| consul | Consul agent Traefik reads the catalog from, as the task's own identity. | <pre>object({<br/>    address = optional(string, "127.0.0.1:8501")<br/>    scheme  = optional(string, "https")<br/>    ca_pem  = optional(string)<br/>  })</pre> | `{}` | no |
| dashboard\_host | Internal role: serve Traefik's dashboard (and its read-only API) at this host name. Null leaves it off. It has no login of its own: whoever reaches the entrypoint internal can see the routes. | `string` | `null` | no |
| datacenters | Datacenters the job may run in. | `list(string)` | <pre>[<br/>  "*"<br/>]</pre> | no |
| domain | Internal role: services of the Consul catalog get Host(<service>.<domain>) unless they name a rule. | `string` | `"service.consul"` | no |
| image | The image of Traefik, pinned by the digest of its index for every architecture so that no retagging changes it. | `string` | `"traefik:v3.7.13@sha256:24841fe2de7304c149343d877d2923b4c8800a38ba015dea9174c23b20e344a0"` | no |
| internal | Internal role: the Nomad host network the entrypoint internal binds to, and its port. | <pre>object({<br/>    host_network = optional(string, "default")<br/>    port         = optional(number, 443)<br/>  })</pre> | `{}` | no |
| job\_name | Name of the Nomad job and of its Consul service. Null takes traefik for the internal role and traefik-public for the public one. | `string` | `null` | no |
| namespace | Nomad namespace of the job. | `string` | `"default"` | no |
| public | Public role: the Nomad host network of the entrypoints public-http (redirects to HTTPS) and public-https, and their ports. | <pre>object({<br/>    host_network = optional(string, "public")<br/>    http_port    = optional(number, 80)<br/>    https_port   = optional(number, 443)<br/>  })</pre> | `{}` | no |
| role | What this Traefik serves. "internal": the entrypoint internal on a private host<br/>network, with a certificate signed by the project CA (tls), the services of the<br/>Consul catalog at <service>.<domain> and the routes; no ACME. "public": the<br/>entrypoints public-http and public-https on the public host network, with<br/>certificates from Let's Encrypt through HTTP-01 (resolver http). Each role is its<br/>own job, Consul service and names, so one host can run both. | `string` | n/a | yes |
| routes | Internal role: routes to backends outside Nomad, such as the Nomad, Consul and Vault UIs, keyed by name. | <pre>map(object({<br/>    host = string<br/>    url  = string<br/>  }))</pre> | `{}` | no |
| tls | Internal role: the certificate of the entrypoint internal, for *.<domain> and <domain>, signed by the project CA (cert\_pem may carry the chain). Kept in a Nomad variable the job reads, not in the job. | <pre>object({<br/>    cert_pem = string<br/>    key_pem  = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| acme\_volume | Name of the dynamic host volume holding the ACME account and certificates; null for the internal role. |
| certresolver | Certificate resolver for routers on public-https (http, HTTP-01); null for the internal role, whose certificate is the one in tls. |
| entrypoints | Entrypoints this Traefik serves: internal, or public-http and public-https. Routers name them in traefik.<proto>.routers.<name>.entrypoints. |
| job\_id | ID of the Traefik job in Nomad. |
| servers\_transport | TCP servers transport that sends the PROXY protocol version 2 header, for TLS passthrough on public-https; null for the internal role. |
| service\_name | Name of the Consul service of the job. |
| tag\_regex | Regular expression a tag of a Consul service must match for this Traefik to read the service: a router on one of its entrypoints, such as traefik.http.routers.<name>.entrypoints=internal. |
<!-- END_TF_DOCS -->
