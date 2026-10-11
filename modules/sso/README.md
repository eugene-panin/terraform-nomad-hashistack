# sso

Single sign-on for a hashistack platform:

- People sign in to Vault with Google (`auth/oidc`). Only the addresses in
  `admins` are let in; each is a Vault entity, made in advance with the address
  as its alias, in the `platform-admins` group, which has everything in Vault.
- Vault is an OIDC provider (`identity/oidc/provider/platform`, issuer at
  `https://vault.<infra_domain>`). It gives tokens only to the `platform-admins`
  group: other Vault identities, such as an app's userpass users, get none.
- Nomad signs people in through it (auth method `vault`, the default); the group
  gets management.
- Other apps make their own `vault_identity_oidc_client` with the `key` and
  `assignment` of the `oidc` output, and read the `groups` claim.

## Google OAuth client

In the Google Cloud console (Google Auth Platform), a Web application client with
the redirect URIs:

- `https://vault.<infra_domain>/ui/vault/auth/oidc/oidc/callback`
- `http://localhost:8250/oidc/callback` (for `vault login -method=oidc`)

The admin pages being reachable only through WireGuard is no obstacle: the
browser follows the redirects, Google never calls the platform.

## Signing in

- Vault UI: method OIDC, role empty (the default, `admin`).
- CLI: `vault login -method=oidc`, `nomad login` (the default method).
- Nomad UI: Sign in with Vault, under ACL tokens.

The bootstrap tokens stay as the break-glass way in.
