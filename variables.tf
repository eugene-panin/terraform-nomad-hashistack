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
  description = "Contact address for the ACME account of Traefik."
  type        = string
}

variable "dns_provider" {
  description = "Provider Traefik answers the DNS-01 challenge of the internal wildcard with, by its lego name."
  type        = string
  default     = "cloudflare"
}

variable "dns_provider_env" {
  description = "Environment of the DNS provider, such as { CF_DNS_API_TOKEN = \"...\" }. Written to Vault as a write-only value, never to the state. Empty when internal_tls.mode is ca."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  default     = {}
}

variable "internal_tls" {
  description = "How the internal entrypoint gets its certificate: mode acme-dns (a Let's Encrypt wildcard through DNS-01, the default) or ca (a wildcard signed by the project CA, given as cert_pem and key_pem — no ACME, no DNS token)."
  type = object({
    mode     = optional(string, "acme-dns")
    cert_pem = optional(string)
    key_pem  = optional(string)
  })
  default = {}
}

variable "dns_provider_env_version" {
  description = "Raise to write a changed dns_provider_env to Vault."
  type        = number
  default     = 1
}

variable "public" {
  description = "Open the public HTTP and HTTPS entrypoints of Traefik, for apps that serve the internet."
  type        = bool
  default     = true
}

variable "traefik_dashboard" {
  description = "Serve Traefik's dashboard at traefik.<infra_domain>, like the Consul, Nomad and Vault UIs: on the internal entrypoint, through the private network only. It has no login of its own."
  type        = bool
  default     = false
}
