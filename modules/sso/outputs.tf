output "issuer" {
  description = "Issuer of Vault's OIDC provider; an app discovers the rest at <issuer>/.well-known/openid-configuration."
  value       = local.issuer
}

output "oidc" {
  description = "What an app needs to sign people in through Vault: the provider's endpoints, the key and the assignment its client is made with (vault_identity_oidc_client), the scopes and the admins' group in the groups claim."
  value = {
    issuer            = local.issuer
    authorization_url = "${local.vault_url}/ui/vault/identity/oidc/provider/${var.provider_name}/authorize"
    token_url         = "${local.issuer}/token"
    userinfo_url      = "${local.issuer}/userinfo"
    key               = vault_identity_oidc_key.platform.name
    assignment        = vault_identity_oidc_assignment.admins.name
    scopes            = ["openid", vault_identity_oidc_scope.user.name, vault_identity_oidc_scope.groups.name]
    admin_group       = var.admin_group
  }
}

output "vault_login_path" {
  description = "Mount path of the Google sign-in in Vault: vault login -method=oidc -path=<path>."
  value       = vault_jwt_auth_backend.google.path
}
