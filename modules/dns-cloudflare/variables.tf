variable "records" {
  description = "DNS records keyed by domain, as the dns_records outputs of the root module and the mail module return them. A record's comment overrides comment."
  type = map(list(object({
    type     = string
    name     = string
    content  = string
    priority = optional(number)
    comment  = optional(string)
  })))

  validation {
    condition = alltrue(flatten([
      for d, rs in var.records : [for r in rs : contains(["A", "AAAA", "CNAME", "MX", "TXT"], r.type)]
    ]))
    error_message = "records supports only A, AAAA, CNAME, MX and TXT."
  }

  validation {
    condition = alltrue(flatten([
      for d, rs in var.records : [for r in rs : r.type != "TXT" || !strcontains(r.content, "\"") && !strcontains(r.content, "\\")]
    ]))
    error_message = "TXT contents must not contain quotes or backslashes."
  }

  validation {
    condition = alltrue(flatten([
      for d, rs in var.records : [for r in rs : r.type != "MX" || r.priority != null]
    ]))
    error_message = "Every MX record needs a priority."
  }
}

variable "domains" {
  description = "Domains of records whose zone is on this Cloudflare account, each the name of its own zone. Records of other domains are left out. Null means every domain in records."
  type        = set(string)
  default     = null

  validation {
    condition     = var.domains == null || alltrue([for d in coalesce(var.domains, []) : contains(keys(var.records), d)])
    error_message = "Every domain in domains must be a key of records."
  }
}

variable "ttl" {
  description = "TTL of the records in seconds; 1 lets Cloudflare choose."
  type        = number
  default     = 1
}

variable "comment" {
  description = "Comment set on every record that has none of its own, so the records this module owns stand out in the dashboard."
  type        = string
  default     = "Managed by OpenTofu"
}
