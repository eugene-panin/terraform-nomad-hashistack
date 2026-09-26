mock_provider "consul" {}
mock_provider "nomad" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "vault" {}

override_resource {
  target = module.mail.tls_private_key.dkim_ed25519
  values = {
    public_key_pem        = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=\n-----END PUBLIC KEY-----\n"
    private_key_pem_pkcs8 = "ed25519-private"
  }
}

override_resource {
  target = module.mail.tls_private_key.dkim_rsa
  values = {
    public_key_pem        = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA\n-----END PUBLIC KEY-----\n"
    private_key_pem_pkcs8 = "rsa-private"
  }
}

variables {
  infra_domain     = "infra.example.com"
  address          = "10.0.0.1"
  ca_pem           = "ca"
  acme_email       = "admin@example.com"
  dns_provider_env = { CF_DNS_API_TOKEN = "token" }
}

run "stack_with_mail" {
  command = apply

  variables {
    mail = {
      hostname   = "mail.example.com"
      domains    = ["example.com", "infra.example.com"]
      mailboxes  = ["info", "sales"]
      acme_email = "postmaster@example.com"
    }
  }

  assert {
    condition = contains(output.dns_records["infra.example.com"], {
      type = "A", name = "*.infra.example.com", content = "10.0.0.1", priority = null, comment = "Internal names, reachable through WireGuard only"
    })
    error_message = "The internal wildcard record is missing or points elsewhere."
  }

  assert {
    condition     = contains([for r in output.dns_records["infra.example.com"] : r.type], "MX") && contains([for r in output.dns_records["example.com"] : "${r.type} ${r.content}"], "MX mail.example.com")
    error_message = "A mail domain, including one that is also the internal domain, lost its mail records."
  }

  assert {
    condition     = alltrue([for r in output.dns_records["example.com"] : r.comment == "Mail, managed by OpenTofu"])
    error_message = "Mail records do not carry the mail comment."
  }

  assert {
    condition = jsonencode(output.mailboxes) == jsonencode({
      "info@example.com"        = ["postmaster@example.com", "abuse@example.com"]
      "sales@example.com"       = []
      "info@infra.example.com"  = ["postmaster@infra.example.com", "abuse@infra.example.com"]
      "sales@infra.example.com" = []
    })
    error_message = "Every domain should get every mailbox, and only the first one postmaster@ and abuse@."
  }

  assert {
    condition     = jsonencode(nonsensitive(keys(output.mail_passwords))) == jsonencode(keys(output.mailboxes))
    error_message = "A mailbox has no generated password."
  }

  assert {
    condition     = output.ui_urls == { consul = "https://consul.infra.example.com", nomad = "https://nomad.infra.example.com", vault = "https://vault.infra.example.com" }
    error_message = "The UI addresses are not under the internal domain."
  }

  assert {
    condition     = output.mail_job_id != null
    error_message = "The mail job was not created."
  }
}

run "stack_without_mail" {
  command = apply

  assert {
    condition     = keys(output.dns_records) == ["infra.example.com"] && length(output.dns_records["infra.example.com"]) == 1
    error_message = "Without mail, only the internal wildcard should be published."
  }

  assert {
    condition     = output.mailboxes == {} && output.mail_job_id == null
    error_message = "Without mail, no mailbox and no mail job should exist."
  }
}

run "empty_mailboxes_are_refused" {
  command = plan

  variables {
    mail = {
      hostname  = "mail.example.com"
      domains   = ["example.com"]
      mailboxes = []
    }
  }

  expect_failures = [var.mail]
}
