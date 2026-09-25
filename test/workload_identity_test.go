package test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/core/v2/random"
	"github.com/gruntwork-io/terratest/modules/terraform/v2"
)

const probeJob = `
job "probe" {
  group "probe" {
    service {
      name     = "probe"
      provider = "consul"
    }

    task "probe" {
      driver = "raw_exec"

      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }

      consul {}

      vault {}

      template {
        destination = "local/out.txt"
        data        = <<-EOT
          vault={{ with secret "kv/data/default/probe/config" }}{{ .Data.data.value }}{{ end }}
          consul={{ range services }}{{ .Name }} {{ end }}
        EOT
      }
    }
  }
}
`

const intruderJob = `
job "intruder" {
  group "intruder" {
    task "intruder" {
      driver = "raw_exec"

      config {
        command = "/bin/sleep"
        args    = ["3600"]
      }

      vault {}

      template {
        destination = "local/out.txt"
        data        = "{{ with secret \"kv/data/default/probe/config\" }}{{ .Data.data.value }}{{ end }}"
      }
    }
  }
}
`

func TestWorkloadIdentity(t *testing.T) {
	startStack(t)

	options := &terraform.Options{
		TerraformDir:    "../examples/workload-identity",
		TerraformBinary: binary(),
		NoColor:         true,
		Vars: map[string]any{
			"nomad_jwks_url": nomadJWKSInside,
			"vault_kv_path":  "kv",
		},
		EnvVars: map[string]string{
			"CONSUL_HTTP_ADDR":  consulAddr,
			"CONSUL_HTTP_TOKEN": consulToken,
			"VAULT_ADDR":        vaultAddr,
			"VAULT_TOKEN":       vaultToken,
		},
	}
	t.Cleanup(func() {
		if !keepStack() {
			terraform.DestroyContext(t, context.Background(), options)
		}
	})
	terraform.InitAndApplyContext(t, t.Context(), options)

	if code := terraform.PlanExitCodeContext(t, t.Context(), options); code != 0 {
		t.Fatalf("a second plan wants changes, exit code %d", code)
	}

	value := random.UniqueID()
	mustCall(t, http.MethodPost, vaultAddr+"/v1/kv/data/default/probe/config", vaultHeaders(),
		map[string]any{"data": map[string]string{"value": value}})

	runJob(t, probeJob)

	var probe allocation
	waitFor(t, 3*time.Minute, "the probe job runs", func() bool {
		var ok bool
		probe, ok = runningAllocation(t, "probe")
		return ok
	})

	rendered := string(mustCall(t, http.MethodGet,
		fmt.Sprintf("%s/v1/client/fs/cat/%s?path=probe/local/out.txt", nomadAddr, probe.ID), nil, nil))
	if !strings.Contains(rendered, "vault="+value+"\n") {
		t.Fatalf("the task did not read its secret from Vault with its own identity: %q", rendered)
	}
	if !strings.Contains(rendered, " nomad ") && !strings.Contains(rendered, "=nomad ") {
		t.Fatalf("the task did not read the Consul catalog with its own identity: %q", rendered)
	}

	waitFor(t, time.Minute, "the probe service is in the Consul catalog", func() bool {
		status, body := call(t, http.MethodGet, consulAddr+"/v1/catalog/service/probe", consulHeaders(), nil)
		var instances []struct{ ServiceName string }
		return status == http.StatusOK && json.Unmarshal(body, &instances) == nil &&
			len(instances) == 1 && instances[0].ServiceName == "probe"
	})

	runJob(t, intruderJob)
	waitFor(t, 2*time.Minute, "the intruder job is refused the secret of another job", func() bool {
		for _, a := range allocations(t, "intruder") {
			for _, state := range a.TaskStates {
				for _, event := range state.Events {
					if strings.Contains(event.DisplayMessage, "Missing: vault.read(kv/data/default/probe/config)") {
						return true
					}
				}
			}
		}
		return false
	})
	time.Sleep(15 * time.Second)
	if _, ok := runningAllocation(t, "intruder"); ok {
		t.Fatal("a job read the secret of another job")
	}
}
