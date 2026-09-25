# Changelog

All notable changes to this module are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-09-25

### Added

- `workload-identity` module: a Consul JWT auth method with binding rules, a
  service registering as itself and a task getting a role with
  `consul_task_policy_rules`; a Vault JWT auth method, a KV version 2 engine
  and a policy templated on the identity, so a job reads only
  `<kv>/<namespace>/<job>`. Tested against Consul, Vault and Nomad in Docker,
  including a job refused another job's secret.
- `traefik` module: Traefik as a Nomad job under `exec`, as `nobody` with only
  `net_bind_service`. An internal entrypoint with a DNS-01 wildcard
  certificate for the Consul catalog and static routes, optional public
  entrypoints with HTTP-01 certificates and a redirect to HTTPS, ACME storage
  on a dynamic host volume, DNS provider credentials written to Vault as a
  write-only value. Tested against Pebble with negative controls.

### Fixed

- `workload-identity`: the `vault_kv_path` output now depends on the KV mount,
  so a caller writing into it waits for the mount.
