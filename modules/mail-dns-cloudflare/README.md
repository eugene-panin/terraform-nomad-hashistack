# mail-dns-cloudflare

Publishes the DNS records of the `mail` module in Cloudflare, for the domains
whose zones are there.

```hcl
module "mail_dns" {
  source  = "eugene-panin/hashistack/nomad//modules/mail-dns-cloudflare"
  version = "~> 0.3"

  records = module.mail.dns_records
  domains = ["example.com", "example.org"]
}
```

Each domain in `domains` is looked up as a zone of its own name. Records of
domains left out of `domains` are not touched; publish them with their own
DNS provider from the `dns_records` output of `mail`.

- MX records keep their priority.
- TXT contents are written as quoted strings of at most 255 characters, so a
  2048-bit RSA DKIM key is split the way DNS requires and Cloudflare returns
  it unchanged on the next plan.
- CNAME, A and AAAA records are not proxied: MTA-STS, autoconfig and the TLS
  passthrough to the mail server need the real address.
- Every record carries `comment`, so the ones this module owns stand out in
  the dashboard.

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
original, that host names are not proxied, that each zone is looked up by the
name of its domain, that domains left out of `domains` get no lookup and no
records, and that an MX without a priority, a TXT with a quote and a domain
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
| comment | Comment set on every record, so the records this module owns stand out in the dashboard. | `string` | `"Mail, managed by OpenTofu"` | no |
| domains | Domains of records whose zone is on this Cloudflare account, each the name of its own zone. Records of other domains are left out. Null means every domain in records. | `set(string)` | `null` | no |
| records | DNS records keyed by domain, as the dns\_records output of the mail module returns them. | <pre>map(list(object({<br/>    type     = string<br/>    name     = string<br/>    content  = string<br/>    priority = optional(number)<br/>  })))</pre> | n/a | yes |
| ttl | TTL of the records in seconds; 1 lets Cloudflare choose. | `number` | `1` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| record\_ids | IDs of the Cloudflare records, keyed by "<type> <name>". |
| zone\_ids | Cloudflare zone ID of each domain. |
<!-- END_TF_DOCS -->
