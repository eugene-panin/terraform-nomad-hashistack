locals {
  domains = var.domains == null ? toset(keys(var.records)) : var.domains

  records = merge([
    for d in local.domains : {
      for r in var.records[d] : "${r.type} ${r.name}" => merge(r, {
        domain = d
        content = r.type != "TXT" ? r.content : join(" ", [
          for i in range(0, length(r.content), 255) : "\"${substr(r.content, i, 255)}\""
        ])
      })
    }
  ]...)
}

data "cloudflare_zone" "this" {
  for_each = local.domains

  filter = {
    name = each.key
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.records

  zone_id  = data.cloudflare_zone.this[each.value.domain].zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = each.value.type == "MX" ? each.value.priority : null
  proxied  = contains(["A", "AAAA", "CNAME"], each.value.type) ? false : null
  ttl      = var.ttl
  comment  = var.comment
}
