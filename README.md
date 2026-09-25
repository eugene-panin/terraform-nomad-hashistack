# terraform-nomad-hashistack

OpenTofu and Terraform modules for what runs inside a Consul, Vault and Nomad
stack: how workloads prove who they are to Consul and Vault, and how traffic
gets to them. The hosts themselves come from the Ansible collection
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

Work in progress: nothing is released yet.

## Modules

| Module | Status | Purpose |
|---|---|---|
| [`workload-identity`](modules/workload-identity) | done | Consul and Vault auth for Nomad workload identities; each job reads only its own secrets |
| [`traefik`](modules/traefik) | done | Traefik on Nomad: an internal entrypoint with a DNS-01 wildcard, public entrypoints with HTTP-01 |

## Requirements

- OpenTofu or Terraform >= 1.9, and >= 1.11 for `traefik`, which uses a write-only
  attribute; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x

## Development

```bash
make lint
make test              # Terratest with tofu
make test-terraform    # the same with terraform
```

Tests live in `test/` and use [Terratest](https://terratest.gruntwork.io/)
v2. Every example under `examples/` is initialised and validated with both
binaries. Module tests start Consul, Vault, Nomad and the Pebble ACME server in Docker from
`test/fixtures/stack` and run real jobs against them; `KEEP_STACK=1` leaves
the stack up after a run, for a look inside.

## License

MIT, see [LICENSE](LICENSE).
