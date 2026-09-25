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
| [`traefik`](modules/traefik) | not yet | Traefik on Nomad: internal and public entrypoints, DNS-01 certificates |

## Requirements

- OpenTofu or Terraform >= 1.9; no feature specific to either is used
- Providers `hashicorp/consul` 2.x, `hashicorp/vault` 5.x, `hashicorp/nomad` 2.x

## Development

```bash
make lint
make test              # Terratest with tofu
make test-terraform    # the same with terraform
```

Tests live in `test/` and use [Terratest](https://terratest.gruntwork.io/)
v2. Every example under `examples/` is initialised and validated with both
binaries. Module tests start Consul, Vault and Nomad in Docker from
`test/fixtures/stack` and run real jobs against them; `KEEP_STACK=1` leaves
the stack up after a run, for a look inside.

## License

MIT, see [LICENSE](LICENSE).
