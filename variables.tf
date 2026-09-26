variable "infra_domain" {
  description = "Domain of the internal names. Traefik serves *.<infra_domain> with a DNS-01 wildcard, and the Consul, Nomad and Vault UIs as consul., nomad. and vault.<infra_domain>."
  type        = string
}

variable "address" {
  description = "Private address the Consul, Vault and Nomad servers listen on, as the hashistack Ansible collection sets them up; the internal names point to it."
  type        = string
}

variable "ca_pem" {
  description = "PEM CA that signs the TLS certificates of Consul, Vault and Nomad."
  type        = string
}

variable "acme_email" {
  description = "Contact address for the ACME account of Traefik, and of the mail server unless mail.acme_email is set."
  type        = string
}

variable "dns_provider" {
  description = "Provider Traefik answers the DNS-01 challenge of the internal wildcard with, by its lego name."
  type        = string
  default     = "cloudflare"
}

variable "dns_provider_env" {
  description = "Environment of the DNS provider, such as { CF_DNS_API_TOKEN = \"...\" }. Written to Vault as a write-only value, never to the state."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
}

variable "dns_provider_env_version" {
  description = "Raise to write a changed dns_provider_env to Vault."
  type        = number
  default     = 1
}

variable "public" {
  description = "Open the public HTTP and HTTPS entrypoints of Traefik, for sites and for the mail server's certificates and MTA-STS."
  type        = bool
  default     = true
}

variable "mail" {
  description = "Mail server, or null for none. Every domain gets every mailbox in mailboxes; the first mailbox of a domain also receives postmaster@ and abuse@."
  type = object({
    hostname     = string
    domains      = set(string)
    mailboxes    = optional(list(string), ["info"])
    acme_email   = optional(string)
    dmarc_policy = optional(string, "none")
    mta_sts_mode = optional(string, "testing")
  })
  default = null

  validation {
    condition     = var.mail == null || length(try(var.mail.mailboxes, [])) > 0
    error_message = "mail.mailboxes must name at least one mailbox."
  }
}
