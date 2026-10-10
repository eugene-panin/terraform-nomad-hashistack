variable "domain" {
  description = "Domain Traefik serves on the internal entrypoint. It gets one wildcard certificate, *.<domain>, through DNS-01."
  type        = string
}

variable "acme_email" {
  description = "Contact address for the ACME account."
  type        = string
}

variable "acme_ca_server" {
  description = "ACME directory URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_ca_certificate" {
  description = "PEM CA the ACME server's own TLS certificate is signed by, for a private ACME server. Null trusts the system store."
  type        = string
  default     = null
}

variable "dns_provider" {
  description = "Provider for the DNS-01 challenge, by its lego name, such as cloudflare."
  type        = string
  default     = "cloudflare"
}

variable "dns_provider_env" {
  description = "Environment the DNS provider needs, such as { CF_DNS_API_TOKEN = \"...\" }. Written to Vault as a write-only value, so it never reaches the state, and read by the job with its own identity."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
}

variable "dns_provider_env_version" {
  description = "Version of dns_provider_env. Raise it to write a changed value to Vault; a write-only value is not compared otherwise."
  type        = number
  default     = 1
}

variable "dns_propagation_check" {
  description = "Wait until the DNS-01 record is visible before asking for validation."
  type        = bool
  default     = true
}

variable "internal" {
  description = "Internal entrypoint: the Nomad host network it binds to and its port. Routers use it unless they name another."
  type = object({
    host_network = optional(string, "default")
    port         = optional(number, 443)
  })
  default = {}
}

variable "internal_tls" {
  description = <<-EOT
    How the internal entrypoint gets its certificate.
    mode "acme-dns" (the default): a wildcard *.<domain> from Let's Encrypt
    through the DNS-01 challenge (needs dns_provider and its token).
    mode "ca": a wildcard *.<domain> signed by the project's own CA, given as
    cert_pem and key_pem — no ACME and no DNS token, for when there is no API
    access to the zone. Browsers trust it through `damstack trust`.
  EOT
  type = object({
    mode     = optional(string, "acme-dns")
    cert_pem = optional(string)
    key_pem  = optional(string)
  })
  default = {}
  validation {
    condition     = contains(["acme-dns", "ca"], var.internal_tls.mode)
    error_message = "internal_tls.mode must be acme-dns or ca."
  }
  validation {
    condition     = var.internal_tls.mode != "ca" || (var.internal_tls.cert_pem != null && var.internal_tls.key_pem != null)
    error_message = "internal_tls.mode ca needs cert_pem and key_pem (a wildcard signed by the project CA)."
  }
}

variable "public" {
  description = "Public entrypoints, HTTP redirecting to HTTPS, with certificates through HTTP-01. Only routers that name public-https use them."
  type = object({
    enabled      = optional(bool, false)
    host_network = optional(string, "public")
    http_port    = optional(number, 80)
    https_port   = optional(number, 443)
  })
  default = {}
}

variable "consul" {
  description = "Consul agent Traefik reads the catalog from, as the task's own identity."
  type = object({
    address = optional(string, "127.0.0.1:8501")
    scheme  = optional(string, "https")
    ca_pem  = optional(string)
  })
  default = {}

  validation {
    condition     = contains(["http", "https"], var.consul.scheme)
    error_message = "consul.scheme must be http or https."
  }
}

variable "dashboard_host" {
  description = "Serve Traefik's dashboard (and its read-only API) on the internal entrypoint at this host name, so only through the private network. Null leaves the dashboard off. It has no login of its own: whoever reaches the internal entrypoint can see the routes."
  type        = string
  default     = null
}

variable "routes" {
  description = "Routes to backends outside Nomad, such as the Nomad, Consul and Vault UIs, on the internal entrypoint, keyed by name."
  type = map(object({
    host = string
    url  = string
  }))
  default = {}
}

variable "backend_ca_pem" {
  description = "PEM CA that signs the certificates of the backends in routes. Null trusts the system store."
  type        = string
  default     = null
}

variable "vault_kv_path" {
  description = "Path of the KV version 2 engine the workload-identity module mounts."
  type        = string
  default     = "secret"
}

variable "namespace" {
  description = "Nomad namespace of the job; also the first segment of its secret path in Vault."
  type        = string
  default     = "default"
}

variable "job_name" {
  description = "Name of the Nomad job; also the second segment of its secret path in Vault."
  type        = string
  default     = "traefik"
}

variable "datacenters" {
  description = "Datacenters the job may run in."
  type        = list(string)
  default     = ["*"]
}

variable "image" {
  description = "The image of Traefik, pinned by the digest of its index for every architecture so that no retagging changes it."
  type        = string
  nullable    = false
  default     = "traefik:v3.7.13@sha256:24841fe2de7304c149343d877d2923b4c8800a38ba015dea9174c23b20e344a0"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must be pinned by its digest: name:tag@sha256:<64 hex digits>."
  }
}
