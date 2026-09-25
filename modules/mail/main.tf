locals {
  secret_name = "${var.namespace}/${var.job_name}/config"
  volume_name = "${var.job_name}-data"

  domain_ids = { for d in var.domains : d => "domain-${replace(d, ".", "-")}" }

  host_domains = [for d in var.domains : d if endswith(var.hostname, ".${d}")]
  host_domain  = one([for d in local.host_domains : d if length(d) == max([for h in local.host_domains : length(h)]...)])
  host_label   = trimsuffix(var.hostname, ".${local.host_domain}")

  service_labels = ["mta-sts", "autoconfig", "autodiscover"]
  tls_names = concat([var.hostname], flatten([
    for d in sort(tolist(var.domains)) : [for l in local.service_labels : "${l}.${d}"]
  ]))

  accounts = {
    for address, account in var.accounts : address => {
      name    = split("@", address)[0]
      domain  = split("@", address)[1]
      aliases = [for a in sort(tolist(account.aliases)) : { name = split("@", a)[0], domain = split("@", a)[1] }]
    }
  }

  dkim_public = {
    for d in var.domains : d => {
      ed25519 = substr(replace(replace(replace(tls_private_key.dkim_ed25519[d].public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", ""), 16, 44)
      rsa     = replace(replace(replace(tls_private_key.dkim_rsa[d].public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", "")
    }
  }

  plan = [
    {
      "@type" = "upsert"
      object  = "Tracer"
      matchOn = ["@type"]
      value   = { stdout = { "@type" = "Stdout", level = "info", ansi = false, buffered = false, enable = true } }
    },
    {
      "@type" = "upsert"
      object  = "AcmeProvider"
      matchOn = ["directory"]
      value = {
        acme = {
          directory     = var.acme_ca_server
          challengeType = "TlsAlpn01"
          contact       = { (var.acme_email) = true }
        }
      }
    },
    {
      "@type" = "upsert"
      object  = "Domain"
      matchOn = ["name"]
      value = {
        for d, id in local.domain_ids : id => {
          name           = d
          dkimManagement = { "@type" = "Manual" }
          certificateManagement = {
            "@type"                 = "Automatic"
            acmeProviderId          = "#acme"
            subjectAlternativeNames = { for l in concat(local.service_labels, d == local.host_domain ? [local.host_label] : []) : l => true }
          }
        }
      }
    },
    {
      "@type" = "upsert"
      object  = "DkimSignature"
      matchOn = ["selector", "domainId"]
      value = merge([
        for d, id in local.domain_ids : {
          "${id}-ed25519" = {
            "@type"    = "Dkim1Ed25519Sha256"
            domainId   = "#${id}"
            selector   = "${var.dkim_selector}-ed25519"
            privateKey = { "@type" = "Text", secret = tls_private_key.dkim_ed25519[d].private_key_pem_pkcs8 }
          }
          "${id}-rsa" = {
            "@type"    = "Dkim1RsaSha256"
            domainId   = "#${id}"
            selector   = "${var.dkim_selector}-rsa"
            privateKey = { "@type" = "Text", secret = tls_private_key.dkim_rsa[d].private_key_pem_pkcs8 }
          }
        }
      ]...)
    },
    {
      "@type" = "upsert"
      object  = "Account"
      matchOn = ["name", "domainId"]
      value = {
        for address, a in local.accounts : "account-${replace(replace(address, "@", "-at-"), ".", "-")}" => {
          "@type"     = "User"
          name        = a.name
          domainId    = "#${local.domain_ids[a.domain]}"
          roles       = { "@type" = "User" }
          credentials = { "0" = { "@type" = "Password", secret = random_password.account[address].bcrypt_hash } }
          aliases     = { for i, alias in a.aliases : tostring(i) => { name = alias.name, domainId = "#${local.domain_ids[alias.domain]}" } }
        }
      }
    },
    {
      "@type" = "update"
      object  = "SystemSettings"
      value = {
        defaultDomainId = "#${local.domain_ids[local.host_domain]}"
        defaultHostname = var.hostname
      }
    },
    {
      "@type" = "update"
      object  = "MtaSts"
      value = {
        mode    = var.mta_sts_mode
        mxHosts = { (var.hostname) = true }
      }
    },
  ]

  config = {
    plan              = join("\n", [for operation in local.plan : jsonencode(operation)])
    recovery_password = random_password.recovery.result
  }
  config_version = parseint(substr(sha256(jsonencode(local.config)), 0, 12), 16)
}

resource "tls_private_key" "dkim_ed25519" {
  for_each = var.domains

  algorithm = "ED25519"
}

resource "tls_private_key" "dkim_rsa" {
  for_each = var.domains

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_password" "account" {
  for_each = var.accounts

  length  = 32
  special = false
}

resource "random_password" "recovery" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "config" {
  mount                = var.vault_kv_path
  name                 = local.secret_name
  data_json_wo         = jsonencode(local.config)
  data_json_wo_version = local.config_version
}

resource "nomad_dynamic_host_volume" "data" {
  name      = local.volume_name
  namespace = var.namespace
  plugin_id = "mkdir"

  parameters = {
    mode = "0700"
    uid  = "65534"
    gid  = "65534"
  }

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

resource "nomad_job" "mail" {
  jobspec = templatefile("${path.module}/templates/mail.nomad.hcl.tftpl", {
    job_name            = var.job_name
    namespace           = var.namespace
    datacenters         = var.datacenters
    volume_name         = nomad_dynamic_host_volume.data.name
    config_version      = local.config_version
    secret_path         = "${var.vault_kv_path}/data/${local.secret_name}"
    public_host_network = var.public_host_network
    internal_network    = var.internal_host_network
    traefik             = var.traefik
    tls_names           = local.tls_names
    acme_ca_certificate = var.acme_ca_certificate
    stalwart            = var.stalwart
  })

  purge_on_destroy = true

  depends_on = [vault_kv_secret_v2.config]
}
