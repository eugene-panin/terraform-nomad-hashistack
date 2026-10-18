# Changelog

All notable changes to this module are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - Unreleased

The platform has no domain. Its admin pages and internal apps are reached
through the private network by their Consul names, `<service>.service.consul`,
with a certificate signed by the project CA. The public entry for apps, DNS
records and single sign-on leave the root module.

### Changed

- **Breaking.** `traefik` takes `role`, `internal` or `public`, and runs one
  Traefik of that role; call it twice for both. Each role is its own job,
  Consul service and names: `traefik` and `traefik-public` by default
  (`job_name` overrides).
  - `internal`: the entrypoint `internal` on the host network `default`, port
    443, with the certificate in `tls` (`cert_pem`, `key_pem`, for
    `*.service.consul` and `service.consul`); services default to
    `Host(<service>.<domain>)`, `domain` being `service.consul`; `routes`,
    `backend_ca_pem` and `dashboard_host` as before. No ACME, no volume. The
    certificate and key are kept in the Nomad variable `nomad/jobs/<job_name>`,
    which the job reads, not in the job.
  - `public`: the entrypoints `public-http` (redirects to HTTPS) and
    `public-https` on the host network `public`, ports 80 and 443, the
    certificate resolver `http` (HTTP-01, needs `acme_email`) with its
    storage on the volume `<job_name>-certificates`, and the TCP servers
    transport `proxy-protocol@file`. No routes, no dashboard.
- **Breaking.** Each role reads only the services of the Consul catalog with a
  router on its own entrypoints (a `constraints` `TagRegex`, the `tag_regex`
  output), under the tag prefix `traefik`. A public app tags as before:
  `traefik.http.routers.<name>.entrypoints=public-https` (or `tcp` for TLS
  passthrough). An internal app must now tag
  `traefik.http.routers.<name>.entrypoints=internal` next to
  `traefik.enable=true`; `traefik.enable=true` alone is served by neither.
  An internal router names no certificate resolver.
- **Breaking.** The root module runs only the internal Traefik, with workload
  identity and the scheduler configuration. It signs the certificate of the
  internal entrypoint itself, for `*.service.consul` and `service.consul`, with
  the project CA (`ca_pem` and the new `ca_key_pem`), valid 825 days and
  renewed on the apply 30 days before it expires. `ui_urls` are
  `https://consul.service.consul`, `https://nomad.service.consul`,
  `https://vault.service.consul`, and `https://traefik.service.consul` with
  `traefik_dashboard`.

### Removed

- **Breaking.** Root module inputs `infra_domain`, `acme_email`,
  `dns_provider`, `dns_provider_env`, `dns_provider_env_version`,
  `internal_tls`, `public`, `sso`, `sso_google_client_secret`,
  `sso_google_client_secret_version`; outputs `dns_records` and `sso`. The
  platform publishes no DNS records: `modules/dns-cloudflare` stays for the
  modules of a domain. `modules/sso` stays, no longer called by the root
  module.
- **Breaking.** `traefik` inputs `domain` as a public name, `acme_email` for the
  internal entrypoint, `dns_provider`, `dns_provider_env`,
  `dns_provider_env_version`, `dns_propagation_check`, `internal_tls`,
  `public.enabled`, `vault_kv_path`; output `secret_path`. No DNS-01: the job
  reads nothing from Vault and the module no longer needs the `vault` provider.
- The root module no longer requires the `random` provider.

### Upgrading from 0.13

Of the root module, `module.traefik` keeps its address and the job keeps its
name, `traefik`. An apply of 1.0.0 over the state of 0.13:

- updates in place `module.traefik.nomad_job.traefik`: the job keeps only the
  entrypoint `internal` on port 443 of the host network `default`. The public
  ports 80 and 443 close: public apps are unreachable until the public role
  runs;
- creates `tls_private_key.internal`, `tls_cert_request.internal`,
  `tls_locally_signed_cert.internal` and
  `module.traefik.nomad_variable.tls[0]` (`nomad/jobs/traefik`);
- destroys `module.traefik.vault_kv_secret_v2.acme`, the DNS provider token.
  It deletes the latest version, as the provider does; the metadata stays
  until `vault kv metadata delete <kv>/default/traefik/acme`;
- forgets `module.traefik.nomad_dynamic_host_volume.certificates` (a
  `removed` block): the volume `traefik-certificates`, with the ACME account
  and the certificates of 0.13 (`dns.json`, `http.json`), stays in Nomad,
  no longer managed. Delete it once nothing needs it with
  `nomad volume delete -type host <id>`;
- forgets `module.sso` when `sso` was on (a `removed` block): the Google sign-in
  method, Vault's OIDC provider and Nomad's auth method stay in Vault and
  Nomad as they are, no longer managed;
- leaves `module.workload_identity` and `nomad_scheduler_config.this`
  unchanged.

The public role is a separate call of `modules/traefik` with
`role = "public"`, in its own state. Its apply creates the job
`traefik-public`, its Consul service and the volume
`traefik-public-certificates`; Traefik requests the public certificates again
through HTTP-01, unless `http.json` is copied from the old volume first. The
records of `*.<infra_domain>` are no longer published by the platform: delete
them, or leave them to a domain module.

A caller that made the internal certificate for `internal_tls.mode = "ca"`
itself drops it: the root module makes its own, for the new names.

## [0.13.0] - 2026-10-11

### Added

- `sso` (`modules/sso`): people sign in to Vault with Google, only the addresses in
  `sso.admins`, each a pre-made entity in the `platform-admins` group (everything
  in Vault). Vault is the OIDC provider of the platform: Nomad signs people in
  through it and gives that group management; other apps make their own client
  with the `sso` output. Other Vault identities (an app's userpass users) are in
  no group and get no token from the provider. The Google client secret is
  written write-only, never to the state.

## [0.12.0] - 2026-10-10

### Added

- Nomad's scheduler has memory oversubscription on (`nomad_scheduler_config`,
  binpack and system-only preemption as before): a task reserves its usual
  memory and may grow to `memory_max`, so reservations follow real use.

### Changed

- Traefik reserves 64 MB and may grow to 256 MB (it used ~35 MB).

## [0.11.0] - 2026-10-10

### Added

- `traefik_dashboard` (default off) serves Traefik's dashboard at
  `traefik.<infra_domain>`, on the internal entrypoint like the Consul, Nomad and
  Vault UIs, so only through the private network; it is listed in `ui_urls`. The
  `traefik` module takes it as `dashboard_host`. The dashboard has no login of
  its own.

## [0.10.0] - 2026-10-09

### Added

- `internal_tls`: the internal entrypoint's certificate is a Let's Encrypt
  wildcard through DNS-01 (`acme-dns`, the default) or a wildcard signed by the
  project CA (`ca`), for when DNS records can only be added by hand.

## [0.9.0] - 2026-10-06

### Changed

- **Breaking.** `traefik` runs the official image, pinned by its digest, with
  the `docker` driver on the network of the host, instead of the release
  binary under `exec`. `image` replaces `traefik_version`. Docker gives a
  process that is not root no capability, so Traefik runs as root of its
  container with only `net_bind_service`, a read-only root file system and
  `no-new-privileges`. Its certificates move to a new volume,
  `<job_name>-certificates`, owned by root, and Traefik requests them again.
  The module no longer manages `<job_name>-acme` but leaves it in place: Nomad
  refuses to delete it while the old allocation holds it. Delete it after the
  apply with `nomad volume delete -type host <id>`.

## [0.8.0] - 2026-09-29

### Added

- `dns-cloudflare` takes `zones`, the zones on the Cloudflare account; the
  records of a domain go into the zone it is under, so `infra_domain` can be a
  subdomain, such as `infra.example.com` in the zone `example.com`. Without
  `zones` nothing changes.

## [0.7.0] - 2026-09-27

### Removed

- **Breaking.** `backup-b2`. Where backups go is the user's choice, not the
  platform's: the `backup` role of `eugene_panin.base` backs up to any restic
  repository, an SSH server by default. A B2 bucket and key are two resources
  of the `Backblaze/b2` provider in the caller's own configuration.

## [0.6.0] - 2026-09-27

### Changed

- **Breaking.** The platform no longer runs mail. The `mail` module, the
  `mail` input of the root module and its `mailboxes`, `mail_passwords` and
  `mail_job_id` outputs move to their own module,
  [`eugene-panin/stalwart/nomad`](https://github.com/eugene-panin/terraform-nomad-stalwart),
  the first app on the platform. To keep an existing server, call it next to
  the root module with the same inputs and add
  `moved { from = module.<stack>.module.mail[0] to = module.<mail> }`; nothing
  is replaced.
- **Breaking.** `dns-cloudflare` takes `records` as a list of record sets, one
  per module, and publishes the records of one domain from several sets
  together: `records = [module.stack.dns_records, module.mail.dns_records]`.
- `dns_records` of the root module returns only the internal wildcard.

### Added

- `vault_kv_path` output of the root module, for the modules of apps.

## [0.5.0] - 2026-09-26

### Added

- `backup-b2` module: a private, encrypted Backblaze B2 bucket for restic and
  an application key limited to it, with the restic repository and key as
  outputs. Files restic deletes stay recoverable for `keep_deleted_days`, 30
  by default, then stop costing storage. Tested with `tofu test` and
  `terraform test` and a mocked provider, with negative controls.

## [0.4.0] - 2026-09-26

### Added

- The root module sets up the whole stack from a few inputs: workload
  identity, Traefik with the Consul, Nomad and Vault UIs, and optionally mail
  with an `info@` mailbox per domain that also receives `postmaster@` and
  `abuse@`. It returns every public DNS record the stack needs. Tested with
  `tofu test` and mocked providers, with negative controls.

### Changed

- `mail-dns-cloudflare` is renamed `dns-cloudflare`: it publishes any records,
  and a record may carry its own comment. The default comment is now
  "Managed by OpenTofu". Callers move the state with
  `moved { from = module.<name> to = module.<new name> }` and the new source.

## [0.3.0] - 2026-09-26

### Added

- `mail-dns-cloudflare` module: the DNS records of `mail` in Cloudflare, MX
  with priority, TXT split into quoted strings of at most 255 characters, host
  names not proxied, domains outside Cloudflare left out. Tested with
  `tofu test` and a mocked provider, with negative controls; CI runs the module
  tests with both binaries.

## [0.2.0] - 2026-09-26

### Added

- `mail` module: Stalwart as a Nomad job under `exec`, as `nobody` with only
  `net_bind_service`. Configuration applied from a plan in Vault by a prestart
  task on every start; DKIM keys and account passwords generated by OpenTofu;
  certificates through TLS-ALPN-01 behind Traefik TLS passthrough with the
  PROXY protocol; the DNS records of every domain as an output. Tested against
  a Pebble that validates for real, with negative controls.
- `traefik` module: a TCP servers transport `proxy-protocol` for services that
  pass TLS through.

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
