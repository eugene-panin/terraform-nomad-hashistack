package test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform/v2"
)

func TestTraefikUpgradeFrom013(t *testing.T) {
	startStack(t)

	acmeCA, err := os.ReadFile(pebbleCA)
	if err != nil {
		t.Fatal(err)
	}
	ca := newInternalCA(t)

	old := &terraform.Options{
		TerraformDir:    "fixtures/upgrade/v0",
		TerraformBinary: binary(),
		NoColor:         true,
		Vars: map[string]any{
			"nomad_jwks_url":      nomadJWKSInside,
			"image":               traefikImage,
			"acme_ca_certificate": string(acmeCA),
		},
		EnvVars: stackEnv(),
	}
	current := &terraform.Options{
		TerraformDir:    "fixtures/upgrade/v1",
		TerraformBinary: binary(),
		NoColor:         true,
		PlanFilePath:    filepath.Join(t.TempDir(), "upgrade.tfplan"),
		VarFiles:        []string{ca.varFile(t)},
		Vars: map[string]any{
			"nomad_jwks_url": nomadJWKSInside,
			"image":          traefikImage,
		},
		EnvVars: stackEnv(),
	}
	for _, dir := range []string{old.TerraformDir, current.TerraformDir} {
		t.Cleanup(func() {
			for _, f := range []string{"terraform.tfstate", "terraform.tfstate.backup"} {
				os.Remove(filepath.Join(dir, f))
			}
		})
	}
	t.Cleanup(func() {
		if !keepStack() {
			terraform.DestroyContext(t, context.Background(), current)
		}
	})

	terraform.InitAndApplyContext(t, t.Context(), old)
	waitFor(t, 3*time.Minute, "the traefik of 0.13 is running", func() bool {
		_, ok := runningAllocation(t, "traefik")
		return ok
	})

	state, err := os.ReadFile(filepath.Join(old.TerraformDir, "terraform.tfstate"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(current.TerraformDir, "terraform.tfstate"), state, 0o600); err != nil {
		t.Fatal(err)
	}
	os.Remove(filepath.Join(old.TerraformDir, "terraform.tfstate"))

	plan := terraform.InitAndPlanAndShowWithStructContext(t, t.Context(), current)
	want := map[string]string{
		"module.traefik.nomad_job.traefik":                      "update",
		"module.traefik.nomad_variable.tls[0]":                  "create",
		"module.traefik.vault_kv_secret_v2.acme":                "delete",
		"module.traefik.nomad_dynamic_host_volume.certificates": "forget",
	}
	for address, action := range want {
		change, ok := plan.ResourceChangesMap[address]
		if !ok {
			t.Fatalf("the upgrade plan has no change for %s", address)
		}
		if got := actions(change.Change.Actions); got != action {
			t.Fatalf("the upgrade plan wants %s for %s, not %s", got, address, action)
		}
	}
	for address, change := range plan.ResourceChangesMap {
		if _, ok := want[address]; ok {
			continue
		}
		if got := actions(change.Change.Actions); got != "no-op" && got != "read" {
			t.Fatalf("the upgrade plan wants %s for %s", got, address)
		}
	}

	terraform.ApplyContext(t, t.Context(), current)

	internal := clientVia(traefikInternal, ca.pool)
	runJob(t, webJob)
	waitFor(t, 5*time.Minute, "the upgraded traefik serves the probe with the certificate of the project CA", func() bool {
		status, body, _ := get(t, internal, "https://probe."+internalDomain+"/")
		return status == http.StatusOK && body == "internal"
	})

	if status, _ := call(t, http.MethodGet, vaultAddr+"/v1/kv/data/default/traefik/acme", vaultHeaders(), nil); status != http.StatusNotFound {
		t.Fatalf("the DNS provider secret is still readable after the upgrade: %d", status)
	}
	if volumes := string(mustCall(t, http.MethodGet, nomadAddr+"/v1/volumes?type=host", nil, nil)); !strings.Contains(volumes, `"traefik-certificates"`) {
		t.Fatalf("the volume of 0.13 was deleted: %s", volumes)
	}
	if code := terraform.PlanExitCodeContext(t, t.Context(), &terraform.Options{
		TerraformDir:    current.TerraformDir,
		TerraformBinary: current.TerraformBinary,
		NoColor:         true,
		Vars:            current.Vars,
		VarFiles:        current.VarFiles,
		EnvVars:         current.EnvVars,
	}); code != 0 {
		t.Fatalf("a plan after the upgrade wants changes, exit code %d", code)
	}
}

func actions[T ~string](list []T) string {
	parts := make([]string, len(list))
	for i, a := range list {
		parts[i] = string(a)
	}
	return strings.Join(parts, ",")
}
