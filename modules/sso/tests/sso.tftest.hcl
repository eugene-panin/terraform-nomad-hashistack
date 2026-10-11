mock_provider "nomad" {}
mock_provider "vault" {
  mock_resource "vault_jwt_auth_backend" {
    defaults = { accessor = "auth_oidc_1234" }
  }
}

variables {
  infra_domain         = "infra.example.com"
  google_client_id     = "123-abc.apps.googleusercontent.com"
  google_client_secret = "secret"
  admins               = ["a@example.com", "b@example.org"]
}

run "only_the_admins_sign_in_to_vault" {
  command = apply

  assert {
    condition = (
      vault_jwt_auth_backend_role.admin.bound_claims["email"] == "a@example.com,b@example.org"
      && vault_jwt_auth_backend_role.admin.user_claim == "email"
      && contains(vault_jwt_auth_backend_role.admin.allowed_redirect_uris, "https://vault.infra.example.com/ui/vault/auth/oidc/oidc/callback")
    )
    error_message = "Vault must let in only the admins' Google addresses, as entities named by their address."
  }

  assert {
    condition     = length(vault_identity_entity_alias.admin) == 2 && contains(vault_identity_group.admins.policies, "platform-admins") && length(vault_identity_group.admins.policies) == 1
    error_message = "Each admin must be a pre-made entity in the admins' group, which carries the admin policy."
  }
}

run "vault_gives_tokens_to_the_admins_group_only" {
  command = apply

  assert {
    condition = (
      contains(vault_identity_oidc_client.nomad.assignments, "platform-admins") && length(vault_identity_oidc_client.nomad.assignments) == 1
      && vault_identity_oidc_provider.platform.issuer_host == "vault.infra.example.com"
      && output.issuer == "https://vault.infra.example.com/v1/identity/oidc/provider/platform"
    )
    error_message = "The OIDC provider must answer at vault.<infra_domain> and give tokens to the admins' group only."
  }

  assert {
    condition     = vault_identity_oidc_scope.groups.template == "{\"groups\": {{identity.entity.groups.names}}}"
    error_message = "The groups scope must carry the entity's groups as a list."
  }
}

run "nomad_makes_the_admins_managers" {
  command = apply

  assert {
    condition = (
      nomad_acl_auth_method.vault.config[0].oidc_discovery_url == "https://vault.infra.example.com/v1/identity/oidc/provider/platform"
      && nomad_acl_binding_rule.admins.selector == "\"platform-admins\" in list.groups"
      && nomad_acl_binding_rule.admins.bind_type == "management"
    )
    error_message = "Nomad must sign people in through Vault and give the admins' group management."
  }
}
