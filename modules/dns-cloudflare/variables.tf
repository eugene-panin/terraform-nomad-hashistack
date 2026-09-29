variable "records" {
  description = "Sets of DNS records keyed by domain, one per module that returns them, such as the dns_records outputs of the root module and of an app. Records of the same domain from different sets are published together. A record's comment overrides comment."
  type = list(map(list(object({
    type     = string
    name     = string
    content  = string
    priority = optional(number)
    comment  = optional(string)
  }))))

  validation {
    condition = alltrue(flatten([
      for set in var.records : [for d, rs in set : [for r in rs : contains(["A", "AAAA", "CNAME", "MX", "TXT"], r.type)]]
    ]))
    error_message = "records supports only A, AAAA, CNAME, MX and TXT."
  }

  validation {
    condition = alltrue(flatten([
      for set in var.records : [for d, rs in set : [for r in rs : r.type != "TXT" || !strcontains(r.content, "\"") && !strcontains(r.content, "\\")]]
    ]))
    error_message = "TXT contents must not contain quotes or backslashes."
  }

  validation {
    condition = alltrue(flatten([
      for set in var.records : [for d, rs in set : [for r in rs : r.type != "MX" || r.priority != null]]
    ]))
    error_message = "Every MX record needs a priority."
  }
}

variable "zones" {
  description = "Zones on this Cloudflare account. A domain of records goes into the zone it is or is under, the longest such: infra.example.com into example.com unless infra.example.com is a zone too. Records of a domain under no zone are left out. Null means every domain is a zone of its own name."
  type        = set(string)
  default     = null
}

variable "domains" {
  description = "Domains of records to publish; records of other domains are left out. Null means every domain of every set in records, or with zones, every one under a zone."
  type        = set(string)
  default     = null

  validation {
    condition     = var.domains == null || alltrue([for d in coalesce(var.domains, []) : anytrue([for set in var.records : contains(keys(set), d)])])
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
