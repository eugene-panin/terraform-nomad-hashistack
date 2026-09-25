consul {
  address = "consul:8500"
  token   = "test-consul-management"

  service_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }

  task_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }
}

vault {
  enabled = true
  address = "http://vault:8200"

  default_identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}

client {
  cpu_total_compute = 2000
  network_interface = "eth0"

  host_network "public" {
    interface = "eth0"
  }
}
