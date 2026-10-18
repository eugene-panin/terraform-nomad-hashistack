# terraform-nomad-hashistack

OpenTofu and Terraform modules for the platform of a Consul, Vault and Nomad
stack: how workloads prove who they are to Consul and Vault, how traffic gets
to them, and DNS. Apps run on the platform as Nomad jobs and come as
modules of their own. The hosts come from the Ansible collection
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

Published as `eugene-panin/hashistack/nomad`.

## Quick start

The root module sets up the platform from a few inputs:

- workload identity in Consul and Vault;
- Traefik on the private network (the role `internal`), with a certificate
  for `*.service.consul` it signs with the project CA;
- the Consul, Nomad and Vault UIs behind it, at
  `https://consul.service.consul`, `https://nomad.service.consul` and
  `https://vault.service.consul`.

The platform has no domain and publishes no DNS records: the names are
Consul's, resolved and reached through WireGuard.

```hcl
module "stack" {
  source  = "eugene-panin/hashistack/nomad"
  version = "~> 1.0"

  address    = "10.77.0.1"
  ca_pem     = file("ca.pem")
  ca_key_pem = var.ca_key_pem
}
```

`address`, `ca_pem` and `ca_key_pem` are the ones the Ansible collection sets
up: the private address Consul, Vault and Nomad listen on, and the CA of their
certificates with its key. The CA must allow the `consul` DNS subtree.

The public entry for apps is a second Traefik, the role `public` of
`modules/traefik`, called in its own configuration:

```hcl
module "traefik_public" {
  source  = "eugene-panin/hashistack/nomad//modules/traefik"
  version = "~> 1.0"

  role       = "public"
  acme_email = "admin@example.com"
  consul     = { ca_pem = file("ca.pem") }
}
```

## Apps

An app is a Nomad job, packaged as a module of its own that takes what the
platform gives it:

- `vault_kv_path`, where its secrets live;
- the Traefik entrypoints, certificate resolver and TCP transport, by name:
  `internal`; `public-https`, `public-http`, the resolver `http` and
  `proxy-protocol@file`;
- the `public` Nomad host network for ports it serves on the internet.

Each Traefik reads only the services with a router on its own entrypoints. An
internal app tags `traefik.enable=true` and
`traefik.http.routers.<name>.entrypoints=internal`, and is served at
`<service>.service.consul` unless it names a rule; it names no certificate
resolver. A public app names `public-https`, its rule and the resolver `http`.

| App | Module |
|---|---|
| Stalwart mail server | [`eugene-panin/stalwart/nomad`](https://github.com/eugene-panin/terraform-nomad-stalwart) |

## Modules

For settings the root module does not expose, call the modules it is made of
directly, with `source = "eugene-panin/hashistack/nomad//modules/<module>"`.

| Module | Purpose |
|---|---|
| [`workload-identity`](modules/workload-identity) | Consul and Vault auth for Nomad workload identities; each job reads only its own secrets |
| [`traefik`](modules/traefik) | Traefik on Nomad in one of two roles: internal, with a certificate of the project CA, or public, with HTTP-01 |
| [`dns-cloudflare`](modules/dns-cloudflare) | DNS records in Cloudflare zones, from the `dns_records` outputs of the apps and of domain modules |
| [`sso`](modules/sso) | Google sign-in to Vault for the admins, and Vault as the OIDC provider Nomad and the apps sign them in through; needs a public domain, not called by the root module |

## Requirements

- OpenTofu or Terraform >= 1.11; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x,
  `hashicorp/tls` 4.x, and `cloudflare/cloudflare` 5.x for `dns-cloudflare`

## Tested

`tofu test` with mocked providers checks the root module: the UI addresses,
the internal Traefik without ACME, its certificate for `*.service.consul`, and
that apps get the KV engine of workload identity. The modules themselves run against Consul, Vault
and Nomad in Docker; see their READMEs.

## Development

```bash
make lint
make test              # tofu test in every module, then Terratest, with tofu
make test-terraform    # the same with terraform
```

Terratest tests live in `test/` and use [Terratest](https://terratest.gruntwork.io/)
v2. Every example under `examples/` is initialised and validated with both
binaries. Module tests start Consul, Vault, Nomad and two Pebble ACME servers
in Docker from `test/fixtures/stack`, one of them validating challenges for
real, and run real jobs against them; one applies 0.13.0 and upgrades it; `KEEP_STACK=1` leaves the stack up after
a run, for a look inside.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| consul | >= 2.21, < 3.0 |
| nomad | >= 2.5, < 3.0 |
| tls | >= 4.0, < 5.0 |
| vault | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| nomad | >= 2.5, < 3.0 |
| tls | >= 4.0, < 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| address | Private address the Consul, Vault and Nomad servers listen on, as the hashistack Ansible collection sets them up. | `string` | n/a | yes |
| ca\_key\_pem | PEM private key of ca\_pem. It signs the certificate of the internal entrypoint, for *.service.consul and service.consul; the CA must allow the consul DNS subtree. | `string` | n/a | yes |
| ca\_pem | PEM CA that signs the TLS certificates of Consul, Vault and Nomad; it also signs the certificate of the internal entrypoint. | `string` | n/a | yes |
| traefik\_dashboard | Serve Traefik's dashboard at traefik.service.consul, like the Consul, Nomad and Vault UIs: on the internal entrypoint, through the private network only. It has no login of its own. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| traefik\_job\_id | ID of the internal Traefik job in Nomad. |
| ui\_urls | Addresses of the Consul, Nomad and Vault UIs behind the internal Traefik, and of Traefik's dashboard when traefik\_dashboard is on. |
| vault\_kv\_path | Path of the Vault KV version 2 engine apps keep their secrets in; a job reads <path>/<namespace>/<job>/*. Pass it to the vault\_kv\_path input of an app module. |
<!-- END_TF_DOCS -->

## License

MIT, see [LICENSE](LICENSE).
