variable "role" {
  description = <<-EOT
    What this Traefik serves. "internal": the entrypoint internal on a private host
    network, with a certificate signed by the project CA (tls), the services of the
    Consul catalog at <service>.<domain> and the routes; no ACME. "public": the
    entrypoints public-http and public-https on the public host network, with
    certificates from Let's Encrypt through HTTP-01 (resolver http). Each role is its
    own job, Consul service and names, so one host can run both.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = contains(["internal", "public"], var.role)
    error_message = "role must be internal or public."
  }
}

variable "job_name" {
  description = "Name of the Nomad job and of its Consul service. Null takes traefik for the internal role and traefik-public for the public one."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Nomad namespace of the job."
  type        = string
  default     = "default"
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

variable "internal" {
  description = "Internal role: the Nomad host network the entrypoint internal binds to, and its port."
  type = object({
    host_network = optional(string, "default")
    port         = optional(number, 443)
  })
  default  = {}
  nullable = false
}

variable "domain" {
  description = "Internal role: services of the Consul catalog get Host(<service>.<domain>) unless they name a rule."
  type        = string
  default     = "service.consul"
  nullable    = false
}

variable "tls" {
  description = "Internal role: the certificate of the entrypoint internal, for *.<domain> and <domain>, signed by the project CA (cert_pem may carry the chain). Kept in a Nomad variable the job reads, not in the job."
  type = object({
    cert_pem = string
    key_pem  = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.role != "internal" || var.tls != null
    error_message = "The internal role needs tls: a certificate and key signed by the project CA."
  }
}

variable "routes" {
  description = "Internal role: routes to backends outside Nomad, such as the Nomad, Consul and Vault UIs, keyed by name."
  type = map(object({
    host = string
    url  = string
  }))
  default  = {}
  nullable = false
}

variable "backend_ca_pem" {
  description = "Internal role: PEM CA that signs the certificates of the backends in routes. Null trusts the system store."
  type        = string
  default     = null
}

variable "dashboard_host" {
  description = "Internal role: serve Traefik's dashboard (and its read-only API) at this host name. Null leaves it off. It has no login of its own: whoever reaches the entrypoint internal can see the routes."
  type        = string
  default     = null
}

variable "public" {
  description = "Public role: the Nomad host network of the entrypoints public-http (redirects to HTTPS) and public-https, and their ports."
  type = object({
    host_network = optional(string, "public")
    http_port    = optional(number, 80)
    https_port   = optional(number, 443)
  })
  default  = {}
  nullable = false
}

variable "acme_email" {
  description = "Public role: contact address for the ACME account."
  type        = string
  default     = null

  validation {
    condition     = var.role != "public" || var.acme_email != null
    error_message = "The public role needs acme_email."
  }
}

variable "acme_ca_server" {
  description = "Public role: ACME directory URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  nullable    = false
}

variable "acme_ca_certificate" {
  description = "Public role: PEM CA the ACME server's own TLS certificate is signed by, for a private ACME server. Null trusts the system store."
  type        = string
  default     = null
}
