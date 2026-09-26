# terraform-nomad-hashistack

OpenTofu and Terraform modules for the platform of a Consul, Vault and Nomad
stack: how workloads prove who they are to Consul and Vault, how traffic gets
to them, DNS and backups. Apps run on the platform as Nomad jobs and come as
modules of their own. The hosts come from the Ansible collection
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

Published as `eugene-panin/hashistack/nomad`.

## Quick start

The root module sets up the platform from a few inputs:

- workload identity in Consul and Vault;
- Traefik with a wildcard certificate for the internal names;
- the Consul, Nomad and Vault UIs behind it.

It returns the DNS records it needs and what apps need from it. Publish the
records with `dns-cloudflare`, together with those of the apps, or by hand
for other DNS providers.

```hcl
module "stack" {
  source  = "eugene-panin/hashistack/nomad"
  version = "~> 0.6"

  infra_domain     = "infra.example.com"
  address          = "10.77.0.1"
  ca_pem           = file("ca.pem")
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = var.cloudflare_api_token }
}

module "mail" {
  source  = "eugene-panin/stalwart/nomad"
  version = "~> 0.1"

  hostname      = "mail.example.com"
  domains       = ["example.com", "example.org"]
  acme_email    = "admin@example.com"
  vault_kv_path = module.stack.vault_kv_path
}

module "dns" {
  source  = "eugene-panin/hashistack/nomad//modules/dns-cloudflare"
  version = "~> 0.6"

  records = [module.stack.dns_records, module.mail.dns_records]
}
```

`address` and `ca_pem` are the ones the Ansible collection sets up: the
private address Consul, Vault and Nomad listen on, and the CA of their
certificates.

## Apps

An app is a Nomad job, packaged as a module of its own that takes what the
platform gives it:

- `vault_kv_path`, where its secrets live;
- the Traefik entrypoints and the `proxy-protocol` TCP transport, by name;
- the `public` Nomad host network for ports it serves on the internet.

It returns its DNS records in the shape `dns-cloudflare` takes.

| App | Module |
|---|---|
| Stalwart mail server | [`eugene-panin/stalwart/nomad`](https://github.com/eugene-panin/terraform-nomad-stalwart) |

## Modules

For settings the root module does not expose, call the modules it is made of
directly, with `source = "eugene-panin/hashistack/nomad//modules/<module>"`.

| Module | Purpose |
|---|---|
| [`workload-identity`](modules/workload-identity) | Consul and Vault auth for Nomad workload identities; each job reads only its own secrets |
| [`traefik`](modules/traefik) | Traefik on Nomad: an internal entrypoint with a DNS-01 wildcard, public entrypoints with HTTP-01 |
| [`dns-cloudflare`](modules/dns-cloudflare) | DNS records in Cloudflare zones, from the `dns_records` outputs of the root module and of the apps |
| [`backup-b2`](modules/backup-b2) | A private Backblaze B2 bucket for restic backups and a key limited to it |

## Requirements

- OpenTofu or Terraform >= 1.11; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x,
  `hashicorp/tls` 4.x, `hashicorp/random` 3.x, `cloudflare/cloudflare` 5.x
  for `dns-cloudflare`, and `Backblaze/b2` 0.14 or later for `backup-b2`

## Tested

`tofu test` with mocked providers checks the root module: the internal
wildcard record and nothing else, the UI addresses, and that apps get the KV
engine of workload identity. The modules themselves run against Consul, Vault
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
real, and run real jobs against them; `KEEP_STACK=1` leaves the stack up after
a run, for a look inside.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| consul | >= 2.21, < 3.0 |
| nomad | >= 2.5, < 3.0 |
| random | >= 3.6, < 4.0 |
| tls | >= 4.0, < 5.0 |
| vault | >= 5.0, < 6.0 |

## Providers

No providers.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| acme\_email | Contact address for the ACME account of Traefik. | `string` | n/a | yes |
| address | Private address the Consul, Vault and Nomad servers listen on, as the hashistack Ansible collection sets them up; the internal names point to it. | `string` | n/a | yes |
| ca\_pem | PEM CA that signs the TLS certificates of Consul, Vault and Nomad. | `string` | n/a | yes |
| dns\_provider | Provider Traefik answers the DNS-01 challenge of the internal wildcard with, by its lego name. | `string` | `"cloudflare"` | no |
| dns\_provider\_env | Environment of the DNS provider, such as { CF\_DNS\_API\_TOKEN = "..." }. Written to Vault as a write-only value, never to the state. | `map(string)` | n/a | yes |
| dns\_provider\_env\_version | Raise to write a changed dns\_provider\_env to Vault. | `number` | `1` | no |
| infra\_domain | Domain of the internal names. Traefik serves *.<infra\_domain> with a DNS-01 wildcard, and the Consul, Nomad and Vault UIs as consul., nomad. and vault.<infra\_domain>. | `string` | n/a | yes |
| public | Open the public HTTP and HTTPS entrypoints of Traefik, for apps that serve the internet. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dns\_records | Public DNS records the platform needs, keyed by domain: the wildcard of the internal names. Publish them with modules/dns-cloudflare, together with the records of the apps, or by hand for other providers. |
| traefik\_job\_id | ID of the Traefik job in Nomad. |
| ui\_urls | Addresses of the Consul, Nomad and Vault UIs behind Traefik. |
| vault\_kv\_path | Path of the Vault KV version 2 engine apps keep their secrets in; a job reads <path>/<namespace>/<job>/*. Pass it to the vault\_kv\_path input of an app module. |
<!-- END_TF_DOCS -->

## License

MIT, see [LICENSE](LICENSE).
