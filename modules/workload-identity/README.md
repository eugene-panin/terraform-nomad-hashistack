# workload-identity

Lets Nomad workloads log in to Consul and Vault with the identity Nomad signs
for them, instead of a token handed to the job. It is the Consul and Vault
half of workload identity; the Nomad half, the `service_identity`,
`task_identity` and `default_identity` blocks on the agents, comes from the
`nomad` role of
[`eugene_panin.hashistack`](https://github.com/eugene-panin/ansible-collection-hashistack).

```hcl
module "workload_identity" {
  source  = "eugene-panin/hashistack/nomad//modules/workload-identity"
  version = "~> 0.3"

  nomad_jwks_url    = "https://10.0.0.10:4646/.well-known/jwks.json"
  nomad_jwks_ca_pem = file("ca.pem")
}
```

## What it creates

In Consul, a JWT auth method that checks identities against Nomad's keys, and
two binding rules. A service gets a token for the service it names, and so
can register itself and nothing else. A task gets a role whose policy is
`consul_task_policy_rules`, by default reading services and nodes.

In Vault, a JWT auth method with a default role, a KV version 2 engine, and a
policy templated on the identity: a job reads `<kv path>/<namespace>/<job>`
and below, and no other job's secrets.

```hcl
task "app" {
  vault {}

  template {
    destination = "secrets/app.env"
    env         = true
    data        = <<-EOT
      {{ with secret "secret/data/default/app/config" }}API_KEY={{ .Data.data.api_key }}{{ end }}
    EOT
  }
}
```

## Tested

The test runs Consul, Vault and Nomad in Docker, applies the module and checks
a second plan is empty. It then runs a job whose service must land in the
Consul catalog and whose template reads its own secret from Vault and the
Consul catalog with the job's identity, and a second job that asks for the
first job's secret and must be refused.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9 |
| consul | >= 2.21, < 3.0 |
| vault | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| consul | >= 2.21, < 3.0 |
| vault | >= 5.0, < 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| consul\_auth\_method\_name | Name of the Consul auth method. It must match the auth method the Nomad agents are configured with, nomad-workloads by default in both. | `string` | `"nomad-workloads"` | no |
| consul\_task\_policy\_rules | Consul ACL rules for tasks, the identity a task's template and Consul block use. Services get a service identity of their own and are not affected. | `string` | `"service_prefix \"\" {\n  policy = \"read\"\n}\nnode_prefix \"\" {\n  policy = \"read\"\n}\n"` | no |
| create\_vault\_kv\_mount | Mount the KV engine at vault\_kv\_path. Turn off when a KV version 2 engine is already mounted there. | `bool` | `true` | no |
| nomad\_jwks\_ca\_pem | PEM CA that signs the certificate of the JWKS endpoint. Null trusts the system store, as for a plain http endpoint. | `string` | `null` | no |
| nomad\_jwks\_url | URL of the JWKS endpoint of the Nomad servers, such as https://10.0.0.10:4646/.well-known/jwks.json. Consul and Vault fetch the keys that sign workload identities from it. | `string` | n/a | yes |
| vault\_jwt\_path | Path to mount the Vault JWT auth method at. It must match nomad\_vault\_jwt\_auth\_path on the Nomad agents, jwt-nomad by default in both. | `string` | `"jwt-nomad"` | no |
| vault\_kv\_path | Path of the KV version 2 engine workloads read their secrets from. A job reads <path>/<namespace>/<job>/*. | `string` | `"secret"` | no |
| vault\_role\_name | Name of the Vault role workloads log in with; also the auth method's default role. | `string` | `"nomad-workloads"` | no |
| vault\_token\_period | Period of the Vault tokens workloads get, in seconds. Nomad renews them while the task runs. | `number` | `1800` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| consul\_auth\_method\_name | Name of the Consul auth method Nomad workloads log in with. |
| consul\_task\_policy\_name | Name of the Consul policy tasks get; attach more rules to it by replacing consul\_task\_policy\_rules. |
| vault\_jwt\_accessor | Accessor of the Vault JWT auth method, for policies that template on workload identity metadata. |
| vault\_jwt\_path | Path of the Vault JWT auth method. |
| vault\_kv\_path | Path of the KV version 2 engine; a job reads <path>/<namespace>/<job>/*. |
| vault\_role\_name | Name of the Vault role Nomad workloads log in with. |
<!-- END_TF_DOCS -->
