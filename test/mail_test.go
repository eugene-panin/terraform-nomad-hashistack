package test

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/smtp"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/emersion/go-msgauth/dkim"
	"github.com/gruntwork-io/terratest/modules/terraform/v2"
)

const (
	mailHost        = "mail.example.test"
	mailSMTP        = "127.0.0.1:10025"
	mailSubmissions = "127.0.0.1:10465"
	mailIMAPS       = "127.0.0.1:10993"
	strictRoots     = "https://127.0.0.1:15001/roots/0"
)

type dnsRecord struct {
	Type    string
	Name    string
	Content string
}

func TestMail(t *testing.T) {
	startStack(t)

	minica, err := os.ReadFile(pebbleCA)
	if err != nil {
		t.Fatal(err)
	}
	strictCA, err := os.ReadFile(filepath.Join(strictDir, "ca.pem"))
	if err != nil {
		t.Fatal(err)
	}

	vars := map[string]any{
		"nomad_jwks_url": nomadJWKSInside,
		"vault_kv_path":  "kv",
		"traefik": map[string]any{
			"domain":                traefikDomain,
			"acme_email":            "admin@" + traefikDomain,
			"acme_ca_server":        "https://pebble:14000/dir",
			"acme_ca_certificate":   string(minica),
			"dns_provider":          "exec",
			"dns_propagation_check": false,
			"internal":              map[string]any{"port": 443},
			"public":                map[string]any{"http_port": 80, "https_port": 9443},
			"consul":                map[string]any{"address": "consul:8500", "scheme": "http"},
		},
		"dns_provider_env": map[string]string{"EXEC_PATH": dnsProviderPath},
		"mail": map[string]any{
			"hostname": mailHost,
			"domains":  []string{"example.test", "second.test"},
			"accounts": map[string]any{
				"info@example.test": map[string]any{"aliases": []string{"postmaster@example.test"}},
				"info@second.test":  map[string]any{"aliases": []string{"postmaster@second.test"}},
			},
			"acme_email":          "admin@example.test",
			"acme_ca_server":      "https://pebble-strict:14000/dir",
			"acme_ca_certificate": string(strictCA),
			"mta_sts_mode":        "enforce",
		},
	}
	encoded, err := json.Marshal(vars)
	if err != nil {
		t.Fatal(err)
	}
	varFile := filepath.Join(t.TempDir(), "mail.tfvars.json")
	if err := os.WriteFile(varFile, encoded, 0o600); err != nil {
		t.Fatal(err)
	}

	options := &terraform.Options{
		TerraformDir:    "../examples/mail",
		TerraformBinary: binary(),
		NoColor:         true,
		VarFiles:        []string{varFile},
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

	var passwords map[string]string
	if err := json.Unmarshal([]byte(terraform.OutputJSONContext(t, t.Context(), options, "passwords")), &passwords); err != nil {
		t.Fatal(err)
	}
	var records map[string][]dnsRecord
	if err := json.Unmarshal([]byte(terraform.OutputJSONContext(t, t.Context(), options, "dns_records")), &records); err != nil {
		t.Fatal(err)
	}

	roots := strictRootPool(t, strictCA)

	var serial string
	waitFor(t, 5*time.Minute, "Stalwart serves a certificate for its host name on the submission port", func() bool {
		cert, err := peerCertificate(mailSubmissions, mailHost, roots)
		if err != nil {
			return false
		}
		serial = cert.SerialNumber.String()
		return true
	})

	mtaSts := clientVia(traefikHTTPS, roots)
	waitFor(t, 3*time.Minute, "the MTA-STS policy of the second domain is served through Traefik", func() bool {
		status, body, _ := get(t, mtaSts, "https://mta-sts.second.test/.well-known/mta-sts.txt")
		return status == http.StatusOK && strings.Contains(body, "mx: "+mailHost) && strings.Contains(body, "mode: enforce")
	})

	inbound := fmt.Sprintf("inbound-%d", time.Now().UnixNano())
	if err := sendPlain(mailSMTP, "probe@sender.invalid", "postmaster@second.test", inbound); err != nil {
		t.Fatalf("the server refused mail from outside to an alias: %v", err)
	}

	outbound := fmt.Sprintf("outbound-%d", time.Now().UnixNano())
	if err := sendAuthenticated(mailSubmissions, roots, "info@example.test", passwords["info@example.test"], "info@second.test", outbound); err != nil {
		t.Fatalf("an account could not send through submission: %v", err)
	}
	if err := sendAuthenticated(mailSubmissions, roots, "info@example.test", "wrong-password", "info@second.test", "refused"); err == nil {
		t.Fatal("submission accepted a wrong password")
	}

	jmap, err := http.NewRequestWithContext(t.Context(), http.MethodGet, "https://"+mailHost+"/jmap/session", nil)
	if err != nil {
		t.Fatal(err)
	}
	jmap.SetBasicAuth("info@example.test", passwords["info@example.test"])
	session, err := mtaSts.Do(jmap)
	if err != nil {
		t.Fatal(err)
	}
	session.Body.Close()
	if session.StatusCode != http.StatusOK {
		t.Fatalf("a JMAP session through Traefik returned %d", session.StatusCode)
	}
	running, ok := runningAllocation(t, "mail")
	if !ok {
		t.Fatal("the mail job is not running")
	}
	waitFor(t, 30*time.Second, "Stalwart logs the JMAP login with the port Traefik received it on", func() bool {
		logs := string(mustCall(t, http.MethodGet,
			fmt.Sprintf("%s/v1/client/fs/logs/%s?task=stalwart&type=stderr&origin=start&plain=true", nomadAddr, running.ID), nil, nil))
		for _, line := range strings.Split(logs, "\n") {
			if strings.Contains(line, "auth.success") && strings.Contains(line, `listenerId = "https"`) && strings.Contains(line, "localPort = 9443,") {
				return true
			}
		}
		return false
	})

	var messages []string
	waitFor(t, 2*time.Minute, "both messages reach the second mailbox", func() bool {
		messages, err = fetchAll(mailIMAPS, roots, "info@second.test", passwords["info@second.test"])
		return err == nil && findMessage(messages, inbound) != "" && findMessage(messages, outbound) != ""
	})

	signed := findMessage(messages, outbound)
	verifications, err := dkim.VerifyWithOptions(strings.NewReader(signed), &dkim.VerifyOptions{
		LookupTXT: func(name string) ([]string, error) {
			for _, r := range records["example.test"] {
				if r.Type == "TXT" && r.Name == name {
					return []string{r.Content}, nil
				}
			}
			return nil, fmt.Errorf("no TXT record %s in the module output", name)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, v := range verifications {
		if v.Err != nil {
			t.Fatalf("a DKIM signature by %s does not verify against the published key: %v", v.Domain, v.Err)
		}
		if v.Domain != "example.test" {
			t.Fatalf("outgoing mail is signed for %s, want example.test", v.Domain)
		}
	}
	if len(verifications) != 2 {
		t.Fatalf("outgoing mail carries %d DKIM signatures, want an Ed25519 and an RSA one", len(verifications))
	}

	stalwart, ok := runningAllocation(t, "mail")
	if !ok {
		t.Fatal("the mail job is not running")
	}
	mustCall(t, http.MethodPost, fmt.Sprintf("%s/v1/allocation/%s/stop", nomadAddr, stalwart.ID), nil, nil)
	waitFor(t, 5*time.Minute, "a new mail allocation serves the submission port", func() bool {
		replacement, ok := runningAllocation(t, "mail")
		if !ok || replacement.ID == stalwart.ID {
			return false
		}
		_, err := peerCertificate(mailSubmissions, mailHost, roots)
		return err == nil
	})
	cert, err := peerCertificate(mailSubmissions, mailHost, roots)
	if err != nil {
		t.Fatal(err)
	}
	if cert.SerialNumber.String() != serial {
		t.Fatal("a new allocation requested a new certificate instead of reading the store")
	}
	after, err := fetchAll(mailIMAPS, roots, "info@second.test", passwords["info@second.test"])
	if err != nil {
		t.Fatal(err)
	}
	if findMessage(after, inbound) == "" || findMessage(after, outbound) == "" {
		t.Fatal("a new allocation lost the mailbox")
	}
	waitFor(t, time.Minute, "six requests in a row through Traefik reach the new allocation, none the stopped one", func() bool {
		for i := 0; i < 6; i++ {
			if status, _, _ := get(t, mtaSts, "https://mta-sts.second.test/.well-known/mta-sts.txt"); status != http.StatusOK {
				return false
			}
		}
		return true
	})
}

func strictRootPool(t *testing.T, ca []byte) *x509.CertPool {
	t.Helper()
	management := x509.NewCertPool()
	management.AppendCertsFromPEM(ca)
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: management, ServerName: "pebble-strict"}}}
	response, err := client.Get(strictRoots)
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

func peerCertificate(address, name string, roots *x509.CertPool) (*x509.Certificate, error) {
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", address, &tls.Config{ServerName: name, RootCAs: roots})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	return conn.ConnectionState().PeerCertificates[0], nil
}

func message(from, to, subject string) []byte {
	return []byte(fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nMessage-ID: <%s@probe>\r\nDate: %s\r\n\r\n%s\r\n",
		from, to, subject, subject, time.Now().Format(time.RFC1123Z), subject))
}

func sendPlain(address, from, to, subject string) error {
	client, err := smtp.Dial(address)
	if err != nil {
		return err
	}
	defer client.Close()
	if err := client.Hello("probe.sender.invalid"); err != nil {
		return err
	}
	return deliver(client, from, to, message(from, to, subject))
}

func sendAuthenticated(address string, roots *x509.CertPool, user, password, to, subject string) error {
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", address, &tls.Config{ServerName: mailHost, RootCAs: roots})
	if err != nil {
		return err
	}
	client, err := smtp.NewClient(conn, mailHost)
	if err != nil {
		return err
	}
	defer client.Close()
	if err := client.Auth(smtp.PlainAuth("", user, password, mailHost)); err != nil {
		return err
	}
	return deliver(client, user, to, message(user, to, subject))
}

func deliver(client *smtp.Client, from, to string, body []byte) error {
	if err := client.Mail(from); err != nil {
		return err
	}
	if err := client.Rcpt(to); err != nil {
		return err
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(body); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return client.Quit()
}

type imapSession struct {
	conn   net.Conn
	reader *bufio.Reader
	tag    int
}

func (s *imapSession) command(format string, args ...any) ([]string, [][]byte, error) {
	s.tag++
	tag := fmt.Sprintf("a%d", s.tag)
	if _, err := fmt.Fprintf(s.conn, "%s %s\r\n", tag, fmt.Sprintf(format, args...)); err != nil {
		return nil, nil, err
	}
	var lines []string
	var literals [][]byte
	for {
		line, err := s.reader.ReadString('\n')
		if err != nil {
			return nil, nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if open := strings.LastIndex(line, "{"); open >= 0 && strings.HasSuffix(line, "}") {
			size, err := strconv.Atoi(line[open+1 : len(line)-1])
			if err == nil {
				literal := make([]byte, size)
				if _, err := io.ReadFull(s.reader, literal); err != nil {
					return nil, nil, err
				}
				literals = append(literals, literal)
			}
		}
		lines = append(lines, line)
		if strings.HasPrefix(line, tag+" ") {
			if !strings.HasPrefix(line, tag+" OK") {
				return lines, literals, fmt.Errorf("IMAP %s", line)
			}
			return lines, literals, nil
		}
	}
}

func fetchAll(address string, roots *x509.CertPool, user, password string) ([]string, error) {
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 5 * time.Second}, "tcp", address, &tls.Config{ServerName: mailHost, RootCAs: roots})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(30 * time.Second))
	session := &imapSession{conn: conn, reader: bufio.NewReader(conn)}
	if _, err := session.reader.ReadString('\n'); err != nil {
		return nil, err
	}
	if _, _, err := session.command("LOGIN %q %q", user, password); err != nil {
		return nil, err
	}
	listing, _, err := session.command(`LIST "" "*"`)
	if err != nil {
		return nil, err
	}
	var messages []string
	for _, line := range listing {
		if !strings.HasPrefix(line, "* LIST") {
			continue
		}
		name := line[strings.LastIndex(line, " ")+1:]
		if quoted := strings.Index(line, `"/" `); quoted >= 0 {
			name = line[quoted+4:]
		}
		selected, _, err := session.command("EXAMINE %s", name)
		if err != nil {
			return nil, err
		}
		if !bytes.Contains([]byte(strings.Join(selected, "\n")), []byte(" EXISTS")) || strings.Contains(strings.Join(selected, "\n"), "* 0 EXISTS") {
			continue
		}
		_, literals, err := session.command("FETCH 1:* BODY.PEEK[]")
		if err != nil {
			return nil, err
		}
		for _, l := range literals {
			messages = append(messages, string(l))
		}
	}
	return messages, nil
}

func findMessage(messages []string, subject string) string {
	for _, m := range messages {
		if strings.Contains(m, "Subject: "+subject+"\r\n") {
			return m
		}
	}
	return ""
}
