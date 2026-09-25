locals {
  secret_name = "${var.namespace}/${var.job_name}/acme"
  volume_name = "${var.job_name}-acme"
}

resource "vault_kv_secret_v2" "acme" {
  mount                = var.vault_kv_path
  name                 = local.secret_name
  data_json_wo         = jsonencode(var.dns_provider_env)
  data_json_wo_version = var.dns_provider_env_version
}

resource "nomad_dynamic_host_volume" "acme" {
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

resource "nomad_job" "traefik" {
  jobspec = templatefile("${path.module}/templates/traefik.nomad.hcl.tftpl", {
    job_name            = var.job_name
    namespace           = var.namespace
    datacenters         = var.datacenters
    volume_name         = nomad_dynamic_host_volume.acme.name
    traefik_version     = var.traefik_version
    domain              = var.domain
    acme_email          = var.acme_email
    acme_ca_server      = var.acme_ca_server
    acme_ca_certificate = var.acme_ca_certificate
    dns_provider        = var.dns_provider
    dns_disable_checks  = !var.dns_propagation_check
    internal            = var.internal
    public              = var.public
    consul              = var.consul
    routes              = var.routes
    backend_ca_pem      = var.backend_ca_pem
    secret_path         = "${var.vault_kv_path}/data/${local.secret_name}"
  })

  purge_on_destroy = true

  depends_on = [vault_kv_secret_v2.acme]
}
