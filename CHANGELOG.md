# Changelog

All notable changes to this module are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `workload-identity` module: a Consul JWT auth method with binding rules, a
  service registering as itself and a task getting a role with
  `consul_task_policy_rules`; a Vault JWT auth method, a KV version 2 engine
  and a policy templated on the identity, so a job reads only
  `<kv>/<namespace>/<job>`. Tested against Consul, Vault and Nomad in Docker,
  including a job refused another job's secret.
