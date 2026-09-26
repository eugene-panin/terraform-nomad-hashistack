# terraform-nomad-hashistack

OpenTofu and Terraform modules for what runs inside a Consul, Vault and Nomad
stack: how workloads prove who they are to Consul and Vault, how traffic gets
to them, and mail. The hosts themselves come from the Ansible collection
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

Published as `eugene-panin/hashistack/nomad`.

## Quick start

The root module sets up the whole stack from a few inputs: workload identity
in Consul and Vault, Traefik with a wildcard certificate for the internal
names and the Consul, Nomad and Vault UIs behind it, and, if asked, a mail
server. It returns every public DNS record the stack needs; publish them with
`dns-cloudflare`, or by hand for other DNS providers.

```hcl
module "stack" {
  source  = "eugene-panin/hashistack/nomad"
  version = "~> 0.4"

  infra_domain     = "infra.example.com"
  address          = "10.77.0.1"
  ca_pem           = file("ca.pem")
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = var.cloudflare_api_token }

  mail = {
    hostname = "mail.example.com"
    domains  = ["example.com", "example.org"]
  }
}

module "dns" {
  source  = "eugene-panin/hashistack/nomad//modules/dns-cloudflare"
  version = "~> 0.4"

  records = module.stack.dns_records
  domains = ["infra.example.com", "example.com", "example.org"]
}
```

`address` and `ca_pem` are the ones the Ansible collection sets up: the
private address Consul, Vault and Nomad listen on, and the CA of their
certificates. Every mail domain gets an `info@` mailbox, which also receives
`postmaster@` and `abuse@`; `mail.mailboxes` names others. The passwords are in
the `mail_passwords` output.

## Modules

For settings the root module does not expose, call the modules it is made of
directly, with `source = "eugene-panin/hashistack/nomad//modules/<module>"`.

| Module | Purpose |
|---|---|
| [`workload-identity`](modules/workload-identity) | Consul and Vault auth for Nomad workload identities; each job reads only its own secrets |
| [`traefik`](modules/traefik) | Traefik on Nomad: an internal entrypoint with a DNS-01 wildcard, public entrypoints with HTTP-01 |
| [`mail`](modules/mail) | Stalwart mail server for several domains: SMTP, submission, IMAP, DKIM, MTA-STS, certificates through TLS-ALPN-01 |
| [`dns-cloudflare`](modules/dns-cloudflare) | DNS records in Cloudflare zones, from the `dns_records` output of the root module or of `mail` |

## Requirements

- OpenTofu or Terraform >= 1.11; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x,
  `hashicorp/tls` 4.x, `hashicorp/random` 3.x, and `cloudflare/cloudflare` 5.x
  for `dns-cloudflare`

## Tested

`tofu test` with mocked providers checks the root module: the internal wildcard
record, the mail records of every domain including the internal one, every
mailbox on every domain with postmaster@ and abuse@ on the first, a password
per mailbox, the UI addresses, and a stack without mail. Each check fails when
its part is removed. The modules themselves run against Consul, Vault and
Nomad in Docker; see their READMEs.

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
| acme\_email | Contact address for the ACME account of Traefik, and of the mail server unless mail.acme\_email is set. | `string` | n/a | yes |
| address | Private address the Consul, Vault and Nomad servers listen on, as the hashistack Ansible collection sets them up; the internal names point to it. | `string` | n/a | yes |
| ca\_pem | PEM CA that signs the TLS certificates of Consul, Vault and Nomad. | `string` | n/a | yes |
| dns\_provider | Provider Traefik answers the DNS-01 challenge of the internal wildcard with, by its lego name. | `string` | `"cloudflare"` | no |
| dns\_provider\_env | Environment of the DNS provider, such as { CF\_DNS\_API\_TOKEN = "..." }. Written to Vault as a write-only value, never to the state. | `map(string)` | n/a | yes |
| dns\_provider\_env\_version | Raise to write a changed dns\_provider\_env to Vault. | `number` | `1` | no |
| infra\_domain | Domain of the internal names. Traefik serves *.<infra\_domain> with a DNS-01 wildcard, and the Consul, Nomad and Vault UIs as consul., nomad. and vault.<infra\_domain>. | `string` | n/a | yes |
| mail | Mail server, or null for none. Every domain gets every mailbox in mailboxes; the first mailbox of a domain also receives postmaster@ and abuse@. | <pre>object({<br/>    hostname     = string<br/>    domains      = set(string)<br/>    mailboxes    = optional(list(string), ["info"])<br/>    acme_email   = optional(string)<br/>    dmarc_policy = optional(string, "none")<br/>    mta_sts_mode = optional(string, "testing")<br/>  })</pre> | `null` | no |
| public | Open the public HTTP and HTTPS entrypoints of Traefik, for sites and for the mail server's certificates and MTA-STS. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dns\_records | Public DNS records the stack needs, keyed by domain: the internal wildcard, and every record of the mail domains. Publish them with modules/dns-cloudflare, or by hand for other providers. |
| mail\_job\_id | ID of the mail job in Nomad, or null without mail. |
| mail\_passwords | Generated password of each mailbox. |
| mailboxes | Mailboxes keyed by address, with the aliases each one also receives. |
| traefik\_job\_id | ID of the Traefik job in Nomad. |
| ui\_urls | Addresses of the Consul, Nomad and Vault UIs behind Traefik. |
<!-- END_TF_DOCS -->

## License

MIT, see [LICENSE](LICENSE).
