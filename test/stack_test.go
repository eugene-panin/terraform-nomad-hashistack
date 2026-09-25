package test

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"path/filepath"
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
	strictDir       = "fixtures/stack/pebble-strict/generated"
)

func startStack(t *testing.T) {
	t.Helper()
	generateStrictPebbleCertificate(t)
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
	setConsulAgentToken(t)
	waitFor(t, 2*time.Minute, "Vault is unsealed", func() bool {
		status, _ := call(t, http.MethodGet, vaultAddr+"/v1/sys/health", nil, nil)
		return status == http.StatusOK
	})
	waitFor(t, 2*time.Minute, "Nomad has a ready node", func() bool {
		status, body := call(t, http.MethodGet, nomadAddr+"/v1/nodes", nil, nil)
		return status == http.StatusOK && bytes.Contains(body, []byte(`"Status":"ready"`))
	})
}

func setConsulAgentToken(t *testing.T) {
	t.Helper()
	var self struct {
		Config struct{ NodeName, Datacenter string }
	}
	if err := json.Unmarshal(mustCall(t, http.MethodGet, consulAddr+"/v1/agent/self", consulHeaders(), nil), &self); err != nil {
		t.Fatal(err)
	}
	var token struct{ SecretID string }
	created := mustCall(t, http.MethodPut, consulAddr+"/v1/acl/token", consulHeaders(), map[string]any{
		"Description":    "agent token of " + self.Config.NodeName,
		"NodeIdentities": []map[string]string{{"NodeName": self.Config.NodeName, "Datacenter": self.Config.Datacenter}},
	})
	if err := json.Unmarshal(created, &token); err != nil {
		t.Fatal(err)
	}
	mustCall(t, http.MethodPut, consulAddr+"/v1/agent/token/agent", consulHeaders(), map[string]string{"Token": token.SecretID})
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

func generateStrictPebbleCertificate(t *testing.T) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(strictDir, "cert.pem")); err == nil {
		return
	}
	if err := os.MkdirAll(strictDir, 0o755); err != nil {
		t.Fatal(err)
	}
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "hashistack test ACME CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	leafTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "pebble-strict"},
		DNSNames:     []string{"pebble-strict", "localhost"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().AddDate(10, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caTemplate, &key.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	files := map[string]*pem.Block{
		"ca.pem":   {Type: "CERTIFICATE", Bytes: caDER},
		"cert.pem": {Type: "CERTIFICATE", Bytes: leafDER},
		"key.pem":  {Type: "PRIVATE KEY", Bytes: keyDER},
	}
	for name, block := range files {
		if err := os.WriteFile(filepath.Join(strictDir, name), pem.EncodeToMemory(block), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
