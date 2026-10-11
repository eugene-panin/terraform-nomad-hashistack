variable "infra_domain" {
  description = "Domain of the internal names: Vault answers at vault.<infra_domain> and Nomad at nomad.<infra_domain>, through Traefik."
  type        = string
}

variable "google_client_id" {
  description = "Client ID of the Google OAuth client (Web application) people sign in to Vault with."
  type        = string

  validation {
    condition     = can(regex("\\.apps\\.googleusercontent\\.com$", var.google_client_id))
    error_message = "google_client_id must be a Google OAuth client ID, ending in .apps.googleusercontent.com."
  }
}

variable "google_client_secret" {
  description = "Secret of that client. Written to Vault as a write-only value, never to the state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "google_client_secret_version" {
  description = "Raise to write a changed google_client_secret to Vault."
  type        = number
  default     = 1
}

variable "admins" {
  description = "Email addresses of the platform's admins: the only Google accounts Vault lets in. Each gets the platform-admins group: everything in Vault, management in Nomad, Admin in the apps that sign in through Vault."
  type        = list(string)

  validation {
    condition     = length(var.admins) > 0 && alltrue([for e in var.admins : can(regex("^[^@\\s,]+@[^@\\s,]+$", e))])
    error_message = "admins must be at least one email address, with no commas."
  }
}

variable "vault_oidc_path" {
  description = "Path the Google sign-in method is mounted at in Vault; its UI callback is /ui/vault/auth/<path>/oidc/callback."
  type        = string
  default     = "oidc"
}

variable "provider_name" {
  description = "Name of Vault's OIDC provider the platform's apps sign in through: issuer https://vault.<infra_domain>/v1/identity/oidc/provider/<name>."
  type        = string
  default     = "platform"
}

variable "admin_group" {
  description = "Name of the Vault identity group of the admins; the apps read it from the groups claim."
  type        = string
  default     = "platform-admins"
}

variable "session_hours" {
  description = "How long a sign-in lasts, in hours, in Vault and in Nomad."
  type        = number
  default     = 8

  validation {
    condition     = var.session_hours >= 1 && var.session_hours <= 24
    error_message = "session_hours must be between 1 and 24."
  }
}
