locals {
  internal = var.role == "internal"
  public   = var.role == "public"

  job_name      = coalesce(var.job_name, local.internal ? "traefik" : "traefik-public")
  volume_name   = "${local.job_name}-certificates"
  variable_path = "nomad/jobs/${local.job_name}"

  entrypoints = local.internal ? ["internal"] : ["public-http", "public-https"]
  tag_regex   = "(?i)^traefik\\.(http|tcp|udp)\\.routers\\.[^=]+\\.entrypoints=(.*,)?\\s*${local.internal ? "internal" : "public-https?"}\\s*(,.*)?$"
}

resource "nomad_variable" "tls" {
  count = local.internal ? 1 : 0

  path      = local.variable_path
  namespace = var.namespace
  items = {
    tls_cert = var.tls.cert_pem
    tls_key  = var.tls.key_pem
  }
}

resource "nomad_dynamic_host_volume" "acme_storage" {
  count = local.public ? 1 : 0

  name      = local.volume_name
  namespace = var.namespace
  plugin_id = "mkdir"

  parameters = {
    mode = "0700"
    uid  = "0"
    gid  = "0"
  }

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

resource "nomad_job" "traefik" {
  jobspec = templatefile("${path.module}/templates/traefik.nomad.hcl.tftpl", {
    role                = var.role
    job_name            = local.job_name
    namespace           = var.namespace
    datacenters         = var.datacenters
    image               = var.image
    consul              = var.consul
    constraint          = "TagRegex(`${local.tag_regex}`)"
    internal            = var.internal
    domain              = var.domain
    variable_path       = local.variable_path
    routes              = var.routes
    backend_ca_pem      = var.backend_ca_pem
    dashboard_host      = var.dashboard_host
    public              = var.public
    volume_name         = local.public ? nomad_dynamic_host_volume.acme_storage[0].name : null
    acme_email          = var.acme_email
    acme_ca_server      = var.acme_ca_server
    acme_ca_certificate = var.acme_ca_certificate
  })

  purge_on_destroy = true

  depends_on = [nomad_variable.tls]
}

removed {
  from = nomad_dynamic_host_volume.certificates

  lifecycle {
    destroy = false
  }
}

removed {
  from = nomad_dynamic_host_volume.acme

  lifecycle {
    destroy = false
  }
}
