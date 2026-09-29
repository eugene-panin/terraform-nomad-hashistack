locals {
  all_domains = toset(flatten([for set in var.records : keys(set)]))

  zone_of = var.zones == null ? { for d in local.all_domains : d => d } : {
    for d, zs in {
      for d in local.all_domains : d => [for z in var.zones : z if d == z || endswith(d, ".${z}")]
    } : d => [for z in zs : z if length(z) == max([for c in zs : length(c)]...)][0] if length(zs) > 0
  }

  domains = var.domains == null ? toset(keys(local.zone_of)) : toset([for d in var.domains : d if contains(keys(local.zone_of), d)])

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
  for_each = toset([for d in local.domains : local.zone_of[d]])

  filter = {
    name = each.key
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.records

  zone_id  = data.cloudflare_zone.this[local.zone_of[each.value.domain]].zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = each.value.type == "MX" ? each.value.priority : null
  proxied  = contains(["A", "AAAA", "CNAME"], each.value.type) ? false : null
  ttl      = var.ttl
  comment  = coalesce(each.value.comment, var.comment)
}
