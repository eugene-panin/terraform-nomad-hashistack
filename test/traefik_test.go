package test

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform/v2"
)

const (
	traefikDomain   = "hashistack.test"
	traefikInternal = "127.0.0.1:18443"
	traefikHTTP     = "127.0.0.1:18080"
	traefikHTTPS    = "127.0.0.1:19443"
	pebbleRoots     = "https://127.0.0.1:15000/roots/0"
	pebbleCA        = "fixtures/stack/pebble.minica.pem"
	dnsProviderPath = "/bin/true"
)

const webJob = `
job "web" {
  group "internal" {
    network {
      port "http" {}
    }

    service {
      name     = "probe"
      port     = "http"
      provider = "consul"
      tags     = ["traefik.enable=true"]

      check {
        type     = "tcp"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "httpd" {
      driver = "raw_exec"

      config {
        command = "/bin/busybox"
        args    = ["httpd", "-f", "-p", "${NOMAD_PORT_http}", "-h", "local/www"]
      }

      template {
        destination = "local/www/index.html"
        data        = "internal"
      }
    }
  }

  group "public" {
    network {
      port "http" {}
    }

    service {
      name     = "site"
      port     = "http"
      provider = "consul"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.site.rule=Host(` + "`site.example.test`" + `)",
        "traefik.http.routers.site.entrypoints=public-https",
      ]

      check {
        type     = "tcp"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "httpd" {
      driver = "raw_exec"

      config {
        command = "/bin/busybox"
        args    = ["httpd", "-f", "-p", "${NOMAD_PORT_http}", "-h", "local/www"]
      }

      template {
        destination = "local/www/index.html"
        data        = "public"
      }
    }
  }
}
`

func TestTraefik(t *testing.T) {
	startStack(t)

	acmeCA, err := os.ReadFile(pebbleCA)
	if err != nil {
		t.Fatal(err)
	}

	options := &terraform.Options{
		TerraformDir:    "../examples/traefik",
		TerraformBinary: binary(),
		NoColor:         true,
		Vars: map[string]any{
			"nomad_jwks_url":        nomadJWKSInside,
			"vault_kv_path":         "kv",
			"domain":                traefikDomain,
			"acme_email":            "admin@" + traefikDomain,
			"acme_ca_server":        "https://pebble:14000/dir",
			"acme_ca_certificate":   string(acmeCA),
			"dns_provider":          "exec",
			"dns_provider_env":      map[string]string{"EXEC_PATH": dnsProviderPath},
			"dns_propagation_check": false,
			"internal":              map[string]any{"port": 443},
			"public":                map[string]any{"enabled": true, "http_port": 80, "https_port": 9443},
			"consul":                map[string]any{"address": "consul:8500", "scheme": "http"},
			"routes": map[string]any{
				"nomad": map[string]string{"host": "nomad." + traefikDomain, "url": "http://127.0.0.1:4646"},
			},
		},
		EnvVars: map[string]string{
			"CONSUL_HTTP_ADDR":  consulAddr,
			"CONSUL_HTTP_TOKEN": consulToken,
			"VAULT_ADDR":        vaultAddr,
			"VAULT_TOKEN":       vaultToken,
			"NOMAD_ADDR":        nomadAddr,
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

	if state := terraform.ShowContext(t, t.Context(), options); strings.Contains(state, dnsProviderPath) {
		t.Fatal("the DNS provider credentials reached the state")
	}
	secret := string(mustCall(t, http.MethodGet, vaultAddr+"/v1/kv/data/default/traefik/acme", vaultHeaders(), nil))
	if !strings.Contains(secret, dnsProviderPath) {
		t.Fatalf("the DNS provider credentials are not in Vault: %s", secret)
	}

	runJob(t, webJob)
	roots := pebbleRootPool(t)

	internal := clientVia(traefikInternal, roots)
	public := clientVia(traefikHTTPS, roots)

	var wildcard *x509.Certificate
	waitFor(t, 5*time.Minute, "the internal entrypoint serves the probe with a wildcard certificate", func() bool {
		status, body, cert := get(t, internal, "https://probe."+traefikDomain+"/")
		wildcard = cert
		return status == http.StatusOK && body == "internal"
	})
	if !containsName(wildcard, "*."+traefikDomain) || !containsName(wildcard, traefikDomain) {
		t.Fatalf("the internal certificate is not the wildcard: %v", wildcard.DNSNames)
	}

	if status, _, _ := get(t, internal, "https://nomad."+traefikDomain+"/v1/agent/health"); status != http.StatusOK {
		t.Fatalf("the static route to Nomad returned %d", status)
	}

	waitFor(t, 3*time.Minute, "the public entrypoint serves the site with its own certificate", func() bool {
		status, body, cert := get(t, public, "https://site.example.test/")
		return status == http.StatusOK && body == "public" && containsName(cert, "site.example.test")
	})

	insecurePublic := clientVia(traefikHTTPS, nil)
	if status, _, _ := get(t, insecurePublic, "https://probe."+traefikDomain+"/"); status != http.StatusNotFound {
		t.Fatalf("an internal service answered on the public entrypoint with %d", status)
	}
	if status, _, _ := get(t, insecurePublic, "https://nomad."+traefikDomain+"/v1/agent/health"); status != http.StatusNotFound {
		t.Fatalf("a static route answered on the public entrypoint with %d", status)
	}
	if status, _, _ := get(t, internal, "https://site.example.test/"); status != http.StatusNotFound {
		t.Fatalf("a public service answered on the internal entrypoint with %d", status)
	}

	plain := clientVia(traefikHTTP, nil)
	request, err := http.NewRequestWithContext(t.Context(), http.MethodGet, "http://site.example.test/", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := plain.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if location := response.Header.Get("Location"); response.StatusCode/100 != 3 || !strings.HasPrefix(location, "https://site.example.test") {
		t.Fatalf("plain HTTP was not redirected to HTTPS: %d %q", response.StatusCode, location)
	}

	traefik, ok := runningAllocation(t, "traefik")
	if !ok {
		t.Fatal("traefik is not running")
	}
	mustCall(t, http.MethodPost, fmt.Sprintf("%s/v1/allocation/%s/stop", nomadAddr, traefik.ID), nil, nil)
	waitFor(t, 3*time.Minute, "a new traefik allocation serves the probe", func() bool {
		replacement, ok := runningAllocation(t, "traefik")
		if !ok || replacement.ID == traefik.ID {
			return false
		}
		status, _, _ := get(t, internal, "https://probe."+traefikDomain+"/")
		return status == http.StatusOK
	})
	if _, _, cert := get(t, internal, "https://probe."+traefikDomain+"/"); cert == nil || cert.SerialNumber.Cmp(wildcard.SerialNumber) != 0 {
		t.Fatal("a new allocation requested a new certificate instead of reading the ACME storage")
	}
}

func pebbleRootPool(t *testing.T) *x509.CertPool {
	t.Helper()
	ca, err := os.ReadFile(pebbleCA)
	if err != nil {
		t.Fatal(err)
	}
	management := x509.NewCertPool()
	management.AppendCertsFromPEM(ca)
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: management}}}
	response, err := client.Get(pebbleRoots)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	root, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(root) {
		t.Fatalf("pebble returned no root certificate: %s", root)
	}
	return pool
}

func clientVia(address string, roots *x509.CertPool) *http.Client {
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	return &http.Client{
		Timeout: 10 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
				return dialer.DialContext(ctx, network, address)
			},
			TLSClientConfig:   &tls.Config{RootCAs: roots, InsecureSkipVerify: roots == nil},
			DisableKeepAlives: true,
		},
	}
}

func get(t *testing.T, client *http.Client, url string) (int, string, *x509.Certificate) {
	t.Helper()
	request, err := http.NewRequestWithContext(t.Context(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(request)
	if err != nil {
		return 0, "", nil
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return 0, "", nil
	}
	var cert *x509.Certificate
	if response.TLS != nil && len(response.TLS.PeerCertificates) > 0 {
		cert = response.TLS.PeerCertificates[0]
	}
	return response.StatusCode, strings.TrimSpace(string(body)), cert
}

func containsName(cert *x509.Certificate, name string) bool {
	if cert == nil {
		return false
	}
	for _, n := range cert.DNSNames {
		if n == name {
			return true
		}
	}
	return false
}
