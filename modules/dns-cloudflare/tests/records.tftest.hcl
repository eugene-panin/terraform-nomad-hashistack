mock_provider "cloudflare" {}

run "every_record_of_every_domain_is_created_once" {
  command = apply

  variables {
    records = [{
      "example.com" = [
        { type = "MX", name = "example.com", content = "mail.example.com", priority = 10 },
        { type = "TXT", name = "example.com", content = "v=spf1 mx -all" },
        { type = "TXT", name = "s1-rsa._domainkey.example.com", content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxhG0mYzt2WtCg2W5Hvr1yb6oYv3kDEcXq3wJ6XvlJ4I8Fxy0Wc2x0ZX5fA3d1BbLkq8k7aTx6aJt0Lwz3bGmK3zR8uQn2yQv7m1pF4oZr7s0c3E6h9nD2kTqV5tYwXcA8bJ1lP0uH4gM6iN9eR2sK7fS3vB5nW1qZ8xT0yU4oC6jL2dE9aF7hG3kI5mN1pQ8rS0tU2vW4xY6zA8bC0dE2fG4hI6jK8lM0nO2pQ4rS6tU8vW0xY2zA4bC6dE8fG0hIDAQAB" },
        { type = "CNAME", name = "mta-sts.example.com", content = "mail.example.com" },
        { type = "A", name = "*.example.com", content = "10.0.0.1", comment = "Internal names" },
      ]
      "example.org" = [
        { type = "MX", name = "example.org", content = "mail.example.com", priority = 10 },
        { type = "TXT", name = "_dmarc.example.org", content = "v=DMARC1; p=none; rua=mailto:postmaster@example.org" },
      ]
    }]
  }

  assert {
    condition     = length(cloudflare_dns_record.this) == 7
    error_message = "Expected one Cloudflare record per input record."
  }

  assert {
    condition     = cloudflare_dns_record.this["A *.example.com"].comment == "Internal names" && cloudflare_dns_record.this["MX example.com"].comment == "Managed by OpenTofu"
    error_message = "A record's own comment is not kept, or the others do not get the module comment."
  }

  assert {
    condition     = data.cloudflare_zone.this["example.com"].filter.name == "example.com" && data.cloudflare_zone.this["example.org"].filter.name == "example.org"
    error_message = "A zone is not looked up by the name of its domain."
  }

  assert {
    condition     = cloudflare_dns_record.this["MX example.org"].priority == 10 && cloudflare_dns_record.this["MX example.org"].content == "mail.example.com"
    error_message = "The MX record lost its priority or target."
  }

  assert {
    condition     = cloudflare_dns_record.this["TXT example.com"].priority == null
    error_message = "A TXT record got a priority."
  }

  assert {
    condition     = cloudflare_dns_record.this["CNAME mta-sts.example.com"].proxied == false
    error_message = "A mail host name is proxied; MTA-STS and TLS passthrough need the real address."
  }

  assert {
    condition     = cloudflare_dns_record.this["TXT example.com"].content == "\"v=spf1 mx -all\""
    error_message = "A short TXT record is not one quoted string."
  }

  assert {
    condition = alltrue([
      for chunk in regexall("\"([^\"]*)\"", cloudflare_dns_record.this["TXT s1-rsa._domainkey.example.com"].content) : length(chunk[0]) <= 255
    ])
    error_message = "A TXT string is longer than 255 characters."
  }

  assert {
    condition     = length(regexall("\"[^\"]*\"", cloudflare_dns_record.this["TXT s1-rsa._domainkey.example.com"].content)) > 1
    error_message = "A TXT record longer than 255 characters was not split."
  }

  assert {
    condition     = join("", [for chunk in regexall("\"([^\"]*)\"", cloudflare_dns_record.this["TXT s1-rsa._domainkey.example.com"].content) : chunk[0]]) == var.records[0]["example.com"][2].content
    error_message = "The split TXT record does not join back to the original."
  }
}

run "domains_outside_cloudflare_are_left_out" {
  command = apply

  variables {
    records = [{
      "example.com" = [{ type = "MX", name = "example.com", content = "mail.example.com", priority = 10 }]
      "example.es"  = [{ type = "MX", name = "example.es", content = "mail.example.com", priority = 10 }]
    }]
    domains = ["example.com"]
  }

  assert {
    condition     = keys(cloudflare_dns_record.this) == ["MX example.com"] && keys(data.cloudflare_zone.this) == ["example.com"]
    error_message = "A domain not listed in domains got a zone lookup or a record."
  }
}

run "sets_from_several_modules_are_published_together" {
  command = apply

  variables {
    records = [
      {
        "example.com" = [{ type = "A", name = "*.example.com", content = "10.0.0.1" }]
      },
      {
        "example.com" = [{ type = "MX", name = "example.com", content = "mail.example.org", priority = 10 }]
        "example.org" = [{ type = "MX", name = "example.org", content = "mail.example.org", priority = 10 }]
      },
    ]
  }

  assert {
    condition     = keys(cloudflare_dns_record.this) == ["A *.example.com", "MX example.com", "MX example.org"]
    error_message = "Records of one domain from two sets did not both get published."
  }

  assert {
    condition     = keys(data.cloudflare_zone.this) == ["example.com", "example.org"]
    error_message = "A domain of the second set got no zone lookup, or one got two."
  }
}

run "an_mx_without_a_priority_is_refused" {
  command = plan

  variables {
    records = [{ "example.com" = [{ type = "MX", name = "example.com", content = "mail.example.com" }] }]
  }

  expect_failures = [var.records]
}

run "a_txt_with_a_quote_is_refused" {
  command = plan

  variables {
    records = [{ "example.com" = [{ type = "TXT", name = "example.com", content = "v=spf1 \"mx\" -all" }] }]
  }

  expect_failures = [var.records]
}

run "a_domain_missing_from_records_is_refused" {
  command = plan

  variables {
    records = [{ "example.com" = [] }]
    domains = ["example.org"]
  }

  expect_failures = [var.domains]
}

run "a_domain_goes_into_the_zone_it_is_under" {
  command = apply

  variables {
    records = [
      { "infra.example.com" = [{ type = "A", name = "*.infra.example.com", content = "10.0.0.1" }] },
      {
        "example.com"       = [{ type = "MX", name = "example.com", content = "mail.example.com", priority = 10 }]
        "a.lab.example.com" = [{ type = "A", name = "a.lab.example.com", content = "10.0.0.2" }]
        "example.es"        = [{ type = "MX", name = "example.es", content = "mail.example.com", priority = 10 }]
        "notexample.com"    = [{ type = "A", name = "notexample.com", content = "10.0.0.3" }]
      },
    ]
    zones = ["example.com", "lab.example.com"]
  }

  assert {
    condition     = keys(data.cloudflare_zone.this) == ["example.com", "lab.example.com"]
    error_message = "The zones looked up are not the zones the domains are under."
  }

  assert {
    condition     = keys(cloudflare_dns_record.this) == ["A *.infra.example.com", "A a.lab.example.com", "MX example.com"]
    error_message = "A record of a domain under no zone was published, or one under a zone was left out."
  }

  assert {
    condition = (
      cloudflare_dns_record.this["A *.infra.example.com"].zone_id == data.cloudflare_zone.this["example.com"].zone_id &&
      cloudflare_dns_record.this["A a.lab.example.com"].zone_id == data.cloudflare_zone.this["lab.example.com"].zone_id
    )
    error_message = "A record went into another zone than the longest one its domain is under."
  }

  assert {
    condition     = output.zone_ids["infra.example.com"] == data.cloudflare_zone.this["example.com"].zone_id
    error_message = "zone_ids does not give the zone of a domain under it."
  }
}

run "domains_narrow_what_zones_publish" {
  command = apply

  variables {
    records = [{
      "infra.example.com" = [{ type = "A", name = "*.infra.example.com", content = "10.0.0.1" }]
      "example.com"       = [{ type = "MX", name = "example.com", content = "mail.example.com", priority = 10 }]
    }]
    zones   = ["example.com"]
    domains = ["infra.example.com"]
  }

  assert {
    condition     = keys(cloudflare_dns_record.this) == ["A *.infra.example.com"]
    error_message = "A domain left out of domains was published."
  }
}
