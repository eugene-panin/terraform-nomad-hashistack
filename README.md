# terraform-nomad-hashistack

OpenTofu and Terraform modules for what runs inside a Consul, Vault and Nomad
stack: how workloads prove who they are to Consul and Vault, and how traffic
gets to them. The hosts themselves come from the Ansible collection
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

Published as `eugene-panin/hashistack/nomad`. Each module is used on its
own, with `source = "eugene-panin/hashistack/nomad//modules/<module>"` and
`version = "~> 0.1"`; see its README.

## Modules

| Module | Status | Purpose |
|---|---|---|
| [`workload-identity`](modules/workload-identity) | done | Consul and Vault auth for Nomad workload identities; each job reads only its own secrets |
| [`traefik`](modules/traefik) | done | Traefik on Nomad: an internal entrypoint with a DNS-01 wildcard, public entrypoints with HTTP-01 |
| [`mail`](modules/mail) | done | Stalwart mail server for several domains: SMTP, submission, IMAP, DKIM, MTA-STS, certificates through TLS-ALPN-01 |

## Requirements

- OpenTofu or Terraform >= 1.9, and >= 1.11 for `traefik` and `mail`, which use
  write-only attributes; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x, and
  `hashicorp/tls` 4.x, `hashicorp/random` 3.x for `mail`

## Development

```bash
make lint
make test              # Terratest with tofu
make test-terraform    # the same with terraform
```

Tests live in `test/` and use [Terratest](https://terratest.gruntwork.io/)
v2. Every example under `examples/` is initialised and validated with both
binaries. Module tests start Consul, Vault, Nomad and two Pebble ACME servers in Docker, one of them validating challenges for real from
`test/fixtures/stack` and run real jobs against them; `KEEP_STACK=1` leaves
the stack up after a run, for a look inside.

## License

MIT, see [LICENSE](LICENSE).
