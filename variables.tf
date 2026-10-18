variable "address" {
  description = "Private address the Consul, Vault and Nomad servers listen on, as the hashistack Ansible collection sets them up."
  type        = string
}

variable "ca_pem" {
  description = "PEM CA that signs the TLS certificates of Consul, Vault and Nomad; it also signs the certificate of the internal entrypoint."
  type        = string
}

variable "ca_key_pem" {
  description = "PEM private key of ca_pem. It signs the certificate of the internal entrypoint, for *.service.consul and service.consul; the CA must allow the consul DNS subtree."
  type        = string
  sensitive   = true
}

variable "traefik_dashboard" {
  description = "Serve Traefik's dashboard at traefik.service.consul, like the Consul, Nomad and Vault UIs: on the internal entrypoint, through the private network only. It has no login of its own."
  type        = bool
  default     = false
}
