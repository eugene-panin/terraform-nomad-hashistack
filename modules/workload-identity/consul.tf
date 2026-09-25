resource "consul_acl_auth_method" "this" {
  name        = var.consul_auth_method_name
  type        = "jwt"
  description = "Nomad workload identities"

  config_json = jsonencode(merge(
    {
      JWKSURL          = var.nomad_jwks_url
      JWTSupportedAlgs = ["RS256"]
      BoundAudiences   = ["consul.io"]
      ClaimMappings = {
        nomad_namespace = "nomad_namespace"
        nomad_job_id    = "nomad_job_id"
        nomad_task      = "nomad_task"
        nomad_service   = "nomad_service"
      }
    },
    var.nomad_jwks_ca_pem == null ? {} : { JWKSCACert = var.nomad_jwks_ca_pem },
  ))
}

resource "consul_acl_binding_rule" "services" {
  auth_method = consul_acl_auth_method.this.name
  description = "A Nomad service registers as the service it names"
  bind_type   = "service"
  bind_name   = "$${value.nomad_service}"
  selector    = "\"nomad_service\" in value"
}

resource "consul_acl_policy" "tasks" {
  name        = "${var.consul_auth_method_name}-tasks"
  description = "What a Nomad task may read from Consul"
  rules       = var.consul_task_policy_rules
}

resource "consul_acl_role" "tasks" {
  name        = "${var.consul_auth_method_name}-tasks"
  description = "Nomad tasks"
  policies    = [consul_acl_policy.tasks.id]
}

resource "consul_acl_binding_rule" "tasks" {
  auth_method = consul_acl_auth_method.this.name
  description = "A Nomad task gets the tasks role"
  bind_type   = "role"
  bind_name   = consul_acl_role.tasks.name
  selector    = "\"nomad_service\" not in value"
}
