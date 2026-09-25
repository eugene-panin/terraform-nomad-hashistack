variable "hostname" {
  description = "Host name of the mail server: the MX of every domain, the name in the SMTP greeting and the one clients connect to. It must be inside one of domains."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a lowercase fully qualified domain name."
  }

  validation {
    condition     = anytrue([for d in var.domains : endswith(var.hostname, ".${d}")])
    error_message = "hostname must be inside one of domains."
  }
}

variable "domains" {
  description = "Mail domains the server accepts mail for and signs mail from."
  type        = set(string)

  validation {
    condition     = length(var.domains) > 0
    error_message = "domains must name at least one domain."
  }
}

variable "accounts" {
  description = "Mailboxes keyed by address, each with the alias addresses it also receives. Every address must be in one of domains. Passwords are generated and returned by the passwords output."
  type = map(object({
    aliases = optional(set(string), [])
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for address, account in var.accounts : [
        for a in concat([address], tolist(account.aliases)) : contains(var.domains, try(split("@", a)[1], ""))
      ]
    ]))
    error_message = "Every account and alias address must be in one of domains."
  }
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

variable "public_host_network" {
  description = "Nomad host network the SMTP, submission and IMAP ports bind to, on their standard numbers."
  type        = string
  default     = "public"
}

variable "internal_host_network" {
  description = "Nomad host network of the HTTPS listener Traefik passes TLS through to."
  type        = string
  default     = "default"
}

variable "traefik" {
  description = "Traefik entrypoint that passes TLS for the mail host names through to Stalwart, and the TCP servers transport that sends the PROXY protocol header."
  type = object({
    entrypoint        = optional(string, "public-https")
    servers_transport = optional(string, "proxy-protocol@file")
  })
  default = {}
}

variable "dkim_selector" {
  description = "Prefix of the DKIM selectors; each domain signs with <prefix>-ed25519 and <prefix>-rsa. Change it to rotate the keys."
  type        = string
  default     = "s1"
}

variable "dmarc_policy" {
  description = "DMARC policy published for every domain."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy must be none, quarantine or reject."
  }
}

variable "mta_sts_mode" {
  description = "MTA-STS mode served for every domain."
  type        = string
  default     = "testing"

  validation {
    condition     = contains(["testing", "enforce"], var.mta_sts_mode)
    error_message = "mta_sts_mode must be testing or enforce."
  }
}

variable "stalwart" {
  description = "Stalwart release and the SHA-256 of its musl tarball per machine architecture, as uname -m prints it. The release publishes no checksums file."
  type = object({
    version = string
    sha256  = map(string)
    cli     = string
  })
  default = {
    version = "0.16.23"
    sha256 = {
      x86_64  = "c5b78035eb354a1c12b42f1664eaf57b58a5a8dfb3b7ad926ef329f87d7863c2"
      aarch64 = "8629b7d2a05e83d48e51dfada4318992e296c7583f11be6c080498e5d11d440a"
    }
    cli = "1.0.12"
  }
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
  description = "Name of the Nomad job and its Consul service; also the second segment of its secret path in Vault."
  type        = string
  default     = "mail"
}

variable "datacenters" {
  description = "Datacenters the job may run in."
  type        = list(string)
  default     = ["*"]
}
