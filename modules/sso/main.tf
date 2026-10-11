locals {
  vault_url = "https://vault.${var.infra_domain}"
  nomad_url = "https://nomad.${var.infra_domain}"
  issuer    = "${local.vault_url}/v1/identity/oidc/provider/${var.provider_name}"
  session_s = var.session_hours * 3600
}

# People sign in to Vault with Google; only the admins' addresses are let in.
resource "vault_jwt_auth_backend" "google" {
  path                          = var.vault_oidc_path
  type                          = "oidc"
  description                   = "Google sign-in of the platform's people"
  oidc_discovery_url            = "https://accounts.google.com"
  oidc_client_id                = var.google_client_id
  oidc_client_secret_wo         = var.google_client_secret
  oidc_client_secret_wo_version = var.google_client_secret_version
  default_role                  = "admin"

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "${var.session_hours}h"
    max_lease_ttl      = "${var.session_hours}h"
  }
}

resource "vault_jwt_auth_backend_role" "admin" {
  backend   = vault_jwt_auth_backend.google.path
  role_name = "admin"
  role_type = "oidc"

  # The Vault entity is the person's address, so the pre-made entities below
  # are the ones they sign in as.
  user_claim   = "email"
  oidc_scopes  = ["openid", "email", "profile"]
  bound_claims = { email = join(",", var.admins) }

  allowed_redirect_uris = [
    "${local.vault_url}/ui/vault/auth/${var.vault_oidc_path}/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  # Rights come from the group, not the role.
  token_ttl     = local.session_s
  token_max_ttl = local.session_s
}

# Everything in Vault, for the admins.
resource "vault_policy" "admin" {
  name   = var.admin_group
  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
    }
  EOT
}

# Each admin as a Vault entity with their Google address as its alias, made before
# they first sign in, so they are in the group from the start. Anyone else with a
# Vault login (the Sauron console's operators, say) is in no group, and the OIDC
# provider below gives them nothing.
resource "vault_identity_entity" "admin" {
  for_each = toset(var.admins)
  name     = each.value
}

resource "vault_identity_entity_alias" "admin" {
  for_each       = toset(var.admins)
  name           = each.value
  mount_accessor = vault_jwt_auth_backend.google.accessor
  canonical_id   = vault_identity_entity.admin[each.value].id
}

resource "vault_identity_group" "admins" {
  name              = var.admin_group
  type              = "internal"
  policies          = [vault_policy.admin.name]
  member_entity_ids = [for e in vault_identity_entity.admin : e.id]
}

# Vault as the OIDC provider of the platform's apps (Nomad here; Grafana and the
# others make their own client with the assignment and key below).
resource "vault_identity_oidc_key" "platform" {
  name               = var.provider_name
  algorithm          = "RS256"
  allowed_client_ids = ["*"]
}

resource "vault_identity_oidc_assignment" "admins" {
  name      = var.admin_group
  group_ids = [vault_identity_group.admins.id]
}

resource "vault_identity_oidc_scope" "user" {
  name        = "user"
  description = "The person's address and name."
  template = jsonencode({
    email    = "{{identity.entity.aliases.${vault_jwt_auth_backend.google.accessor}.name}}"
    username = "{{identity.entity.name}}"
  })
}

resource "vault_identity_oidc_scope" "groups" {
  name        = "groups"
  description = "The Vault groups the person is in."
  # Vault fills the list in; a quoted template would make it a string.
  template = "{\"groups\": {{identity.entity.groups.names}}}"
}

resource "vault_identity_oidc_provider" "platform" {
  name               = var.provider_name
  https_enabled      = true
  issuer_host        = "vault.${var.infra_domain}"
  allowed_client_ids = ["*"]
  scopes_supported   = [vault_identity_oidc_scope.user.name, vault_identity_oidc_scope.groups.name]
}

resource "vault_identity_oidc_client" "nomad" {
  name             = "nomad"
  key              = vault_identity_oidc_key.platform.name
  assignments      = [vault_identity_oidc_assignment.admins.name]
  client_type      = "confidential"
  id_token_ttl     = 3600
  access_token_ttl = 3600

  redirect_uris = [
    "${local.nomad_url}/ui/settings/tokens",
    "http://localhost:4649/oidc/callback",
  ]
}

# Nomad signs people in through Vault; the admins get a management token.
resource "nomad_acl_auth_method" "vault" {
  name           = "vault"
  type           = "OIDC"
  token_locality = "global"
  max_token_ttl  = "${var.session_hours}h"
  default        = true

  config {
    oidc_discovery_url    = local.issuer
    oidc_client_id        = vault_identity_oidc_client.nomad.client_id
    oidc_client_secret    = vault_identity_oidc_client.nomad.client_secret
    oidc_scopes           = [vault_identity_oidc_scope.user.name, vault_identity_oidc_scope.groups.name]
    bound_audiences       = [vault_identity_oidc_client.nomad.client_id]
    allowed_redirect_uris = vault_identity_oidc_client.nomad.redirect_uris
    claim_mappings        = { email = "email" }
    list_claim_mappings   = { groups = "groups" }
  }

  depends_on = [vault_identity_oidc_provider.platform]
}

resource "nomad_acl_binding_rule" "admins" {
  auth_method = nomad_acl_auth_method.vault.name
  description = "The platform's admins manage Nomad."
  selector    = "\"${var.admin_group}\" in list.groups"
  bind_type   = "management"
}
