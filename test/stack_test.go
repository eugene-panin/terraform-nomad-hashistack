package test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/docker/v2"
)

const (
	consulAddr      = "http://127.0.0.1:18500"
	consulToken     = "test-consul-management"
	vaultAddr       = "http://127.0.0.1:18200"
	vaultToken      = "test-vault-root"
	nomadAddr       = "http://127.0.0.1:14646"
	nomadJWKSInside = "http://nomad:4646/.well-known/jwks.json"
)

func startStack(t *testing.T) {
	t.Helper()
	options := &docker.Options{WorkingDir: "fixtures/stack"}
	t.Cleanup(func() {
		if keepStack() {
			return
		}
		docker.RunDockerComposeContext(t, context.Background(), options, "down", "--volumes", "--remove-orphans")
	})
	docker.RunDockerComposeContext(t, t.Context(), options, "up", "--detach")

	waitFor(t, 2*time.Minute, "Consul has a leader", func() bool {
		status, body := call(t, http.MethodGet, consulAddr+"/v1/status/leader", consulHeaders(), nil)
		return status == http.StatusOK && len(body) > 2
	})
	waitFor(t, 2*time.Minute, "Vault is unsealed", func() bool {
		status, _ := call(t, http.MethodGet, vaultAddr+"/v1/sys/health", nil, nil)
		return status == http.StatusOK
	})
	waitFor(t, 2*time.Minute, "Nomad has a ready node", func() bool {
		status, body := call(t, http.MethodGet, nomadAddr+"/v1/nodes", nil, nil)
		return status == http.StatusOK && bytes.Contains(body, []byte(`"Status":"ready"`))
	})
}

func keepStack() bool {
	return os.Getenv("KEEP_STACK") != ""
}

func consulHeaders() map[string]string {
	return map[string]string{"X-Consul-Token": consulToken}
}

func vaultHeaders() map[string]string {
	return map[string]string{"X-Vault-Token": vaultToken}
}

func call(t *testing.T, method, url string, headers map[string]string, body any) (int, []byte) {
	t.Helper()
	var reader io.Reader
	switch b := body.(type) {
	case nil:
	case string:
		reader = strings.NewReader(b)
	default:
		encoded, err := json.Marshal(b)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(t.Context(), method, url, reader)
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range headers {
		request.Header.Set(k, v)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return 0, nil
	}
	defer response.Body.Close()
	payload, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response.StatusCode, payload
}

func mustCall(t *testing.T, method, url string, headers map[string]string, body any) []byte {
	t.Helper()
	status, payload := call(t, method, url, headers, body)
	if status < 200 || status > 299 {
		t.Fatalf("%s %s returned %d: %s", method, url, status, payload)
	}
	return payload
}

func waitFor(t *testing.T, timeout time.Duration, what string, ready func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if ready() {
			return
		}
		time.Sleep(2 * time.Second)
	}
	t.Fatalf("timed out waiting until %s", what)
}

func runJob(t *testing.T, hcl string) {
	t.Helper()
	var job map[string]any
	parsed := mustCall(t, http.MethodPost, nomadAddr+"/v1/jobs/parse", nil,
		map[string]any{"JobHCL": hcl, "Canonicalize": true})
	if err := json.Unmarshal(parsed, &job); err != nil {
		t.Fatal(err)
	}
	mustCall(t, http.MethodPost, nomadAddr+"/v1/jobs", nil, map[string]any{"Job": job})
}

type allocation struct {
	ID           string
	ClientStatus string
	TaskStates   map[string]struct {
		Events []struct {
			DisplayMessage string
		}
	}
}

func allocations(t *testing.T, job string) []allocation {
	t.Helper()
	var allocs []allocation
	payload := mustCall(t, http.MethodGet, fmt.Sprintf("%s/v1/job/%s/allocations", nomadAddr, job), nil, nil)
	if err := json.Unmarshal(payload, &allocs); err != nil {
		t.Fatal(err)
	}
	return allocs
}

func runningAllocation(t *testing.T, job string) (allocation, bool) {
	t.Helper()
	for _, a := range allocations(t, job) {
		if a.ClientStatus == "running" {
			return a, true
		}
	}
	return allocation{}, false
}
