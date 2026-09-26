locals {
  domains = var.domains == null ? toset(flatten([for set in var.records : keys(set)])) : var.domains

  records = {
    for r in flatten([
      for set in var.records : [
        for d, rs in set : [for r in rs : merge(r, { domain = d })] if contains(local.domains, d)
      ]
      ]) : "${r.type} ${r.name}" => merge(r, {
      content = r.type != "TXT" ? r.content : join(" ", [
        for i in range(0, length(r.content), 255) : "\"${substr(r.content, i, 255)}\""
      ])
    })
  }
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
  comment  = coalesce(each.value.comment, var.comment)
}
