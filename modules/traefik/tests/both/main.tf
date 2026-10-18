module "internal" {
  source = "../.."

  role = "internal"
  tls  = { cert_pem = "CERT", key_pem = "KEY" }
}

module "public" {
  source = "../.."

  role       = "public"
  acme_email = "admin@example.com"
}

output "internal" {
  value = module.internal
}

output "public" {
  value = module.public
}
