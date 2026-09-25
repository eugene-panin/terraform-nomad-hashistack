mock_provider "cloudflare" {}

run "every_record_of_every_domain_is_created_once" {
  command = apply

  variables {
    records = {
      "example.com" = [
        { type = "MX", name = "example.com", content = "mail.example.com", priority = 10 },
        { type = "TXT", name = "example.com", content = "v=spf1 mx -all" },
        { type = "TXT", name = "s1-rsa._domainkey.example.com", content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxhG0mYzt2WtCg2W5Hvr1yb6oYv3kDEcXq3wJ6XvlJ4I8Fxy0Wc2x0ZX5fA3d1BbLkq8k7aTx6aJt0Lwz3bGmK3zR8uQn2yQv7m1pF4oZr7s0c3E6h9nD2kTqV5tYwXcA8bJ1lP0uH4gM6iN9eR2sK7fS3vB5nW1qZ8xT0yU4oC6jL2dE9aF7hG3kI5mN1pQ8rS0tU2vW4xY6zA8bC0dE2fG4hI6jK8lM0nO2pQ4rS6tU8vW0xY2zA4bC6dE8fG0hIDAQAB" },
        { type = "CNAME", name = "mta-sts.example.com", content = "mail.example.com" },
      ]
      "example.org" = [
        { type = "MX", name = "example.org", content = "mail.example.com", priority = 10 },
        { type = "TXT", name = "_dmarc.example.org", content = "v=DMARC1; p=none; rua=mailto:postmaster@example.org" },
      ]
    }
  }

  assert {
    condition     = length(cloudflare_dns_record.this) == 6
    error_message = "Expected one Cloudflare record per input record."
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
    condition     = join("", [for chunk in regexall("\"([^\"]*)\"", cloudflare_dns_record.this["TXT s1-rsa._domainkey.example.com"].content) : chunk[0]]) == var.records["example.com"][2].content
    error_message = "The split TXT record does not join back to the original."
  }
}

run "domains_outside_cloudflare_are_left_out" {
  command = apply

  variables {
    records = {
      "example.com" = [{ type = "MX", name = "example.com", content = "mail.example.com", priority = 10 }]
      "example.es"  = [{ type = "MX", name = "example.es", content = "mail.example.com", priority = 10 }]
    }
    domains = ["example.com"]
  }

  assert {
    condition     = keys(cloudflare_dns_record.this) == ["MX example.com"] && keys(data.cloudflare_zone.this) == ["example.com"]
    error_message = "A domain not listed in domains got a zone lookup or a record."
  }
}

run "an_mx_without_a_priority_is_refused" {
  command = plan

  variables {
    records = { "example.com" = [{ type = "MX", name = "example.com", content = "mail.example.com" }] }
  }

  expect_failures = [var.records]
}

run "a_txt_with_a_quote_is_refused" {
  command = plan

  variables {
    records = { "example.com" = [{ type = "TXT", name = "example.com", content = "v=spf1 \"mx\" -all" }] }
  }

  expect_failures = [var.records]
}

run "a_domain_missing_from_records_is_refused" {
  command = plan

  variables {
    records = { "example.com" = [] }
    domains = ["example.org"]
  }

  expect_failures = [var.domains]
}
