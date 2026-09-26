# dns-cloudflare

Publishes DNS records in Cloudflare, for the domains whose zones are there.
The records come in sets, one per module: the `dns_records` output of the
root module (the internal wildcard) and those of the apps, such as the mail
records of `eugene-panin/stalwart/nomad`. Records of one domain from
different sets are published together.

```hcl
module "dns" {
  source  = "eugene-panin/hashistack/nomad//modules/dns-cloudflare"
  version = "~> 0.6"

  records = [module.stack.dns_records, module.mail.dns_records]
  domains = ["infra.example.com", "example.com"]
}
```

Each domain in `domains` is looked up as a zone of its own name. Records of
domains left out of `domains` are not touched; publish them with their own
DNS provider.

- MX records keep their priority.
- TXT contents are written as quoted strings of at most 255 characters, so a
  2048-bit RSA DKIM key is split the way DNS requires and Cloudflare returns
  it unchanged on the next plan.
- CNAME, A and AAAA records are not proxied: MTA-STS, autoconfig and the TLS
  passthrough to the mail server need the real address.
- Every record carries a comment, its own or `comment`, so the ones this
  module owns stand out in the dashboard.

## Records made by hand

A record that already exists with the same name and type makes the create
fail. Adopt it into the state from the root module instead, with an `import`
block per record into `module.<name>.cloudflare_dns_record.this["<type> <name>"]`
and the id `<zone_id>/<record_id>`; the `zone_ids` output gives the zone.

## Tested

`tofu test` with a mocked Cloudflare provider checks that every input record
becomes exactly one Cloudflare record of the same type, name and target,
that MX keeps its priority and nothing else gets one, that a long TXT record
is split into quoted strings of at most 255 characters that join back to the
original, that host names are not proxied, that a record keeps its own comment
and the others get `comment`, that each zone is looked up by the
name of its domain, that domains left out of `domains` get no lookup and no
records, that records of one domain from two sets are all published, and that an MX without a priority, a TXT with a quote and a domain
missing from `records` are refused. Each check fails when its part of the
module is removed.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9 |
| cloudflare | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| cloudflare | >= 5.0, < 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| comment | Comment set on every record that has none of its own, so the records this module owns stand out in the dashboard. | `string` | `"Managed by OpenTofu"` | no |
| domains | Domains of records whose zone is on this Cloudflare account, each the name of its own zone. Records of other domains are left out. Null means every domain of every set in records. | `set(string)` | `null` | no |
| records | Sets of DNS records keyed by domain, one per module that returns them, such as the dns\_records outputs of the root module and of an app. Records of the same domain from different sets are published together. A record's comment overrides comment. | <pre>list(map(list(object({<br/>    type     = string<br/>    name     = string<br/>    content  = string<br/>    priority = optional(number)<br/>    comment  = optional(string)<br/>  }))))</pre> | n/a | yes |
| ttl | TTL of the records in seconds; 1 lets Cloudflare choose. | `number` | `1` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| record\_ids | IDs of the Cloudflare records, keyed by "<type> <name>". |
| zone\_ids | Cloudflare zone ID of each domain. |
<!-- END_TF_DOCS -->
