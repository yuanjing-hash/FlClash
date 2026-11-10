package core

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	D "github.com/miekg/dns"
)

func TestRootDiagnosticReportsActualGlobalSelectionAndKeepsCredentialsPrivate(t *testing.T) {
	raw := config.DefaultRawConfig()
	raw.DNS.Enable = false
	raw.NTP.Enable = true
	raw.Proxy = []map[string]any{{"name": "node-a", "type": "direct"}, {"name": "node-b", "type": "direct"}}
	raw.ProxyGroup = []map[string]any{
		{"name": "choice", "type": "select", "proxies": []string{"node-a", "node-b"}},
		{"name": "GLOBAL", "type": "select", "proxies": []string{"choice"}},
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	cfg.Controller.Secret = "never-export-controller-secret"
	cfg.General.Tun, err = rootTunConfig(RootOptions{Enable: true, PerApp: true, Stack: "mips", ExcludeUID: []uint32{10314}})
	if err != nil {
		t.Fatal(err)
	}
	withCurrentConfig(t, cfg)
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	previousMode := tunnel.Mode()
	t.Cleanup(func() { tunnel.SetMode(previousMode) })
	tunnel.SetMode(tunnel.Global)
	patchSelectGroup(map[string]string{"choice": "node-b", "GLOBAL": "choice"})
	state := rootNetworkState()
	if state["mode"] != "global" || !reflect.DeepEqual(state["globalChain"], []string{"GLOBAL", "choice", "node-b"}) {
		t.Fatal("diagnostic did not read the running selector", state)
	}
	if state["dnsEnabled"] != false || state["proxyCount"] != len(cfg.Proxies) {
		t.Fatal("live settings lost", state)
	}
	if state["ntpEnabled"] != true || state["ntpWriteToSystem"] != false {
		t.Fatal("live system time policy lost", state)
	}
	if state["tunEnabled"] != true || state["tunDevice"] != "flcrtun0" ||
		!reflect.DeepEqual(state["excludeUID"], []uint32{10314}) {
		t.Fatal("actual application capture policy lost", state)
	}
	data, err := json.Marshal(state)
	if err != nil || strings.Contains(string(data), "never-export") {
		t.Fatal("credentials in diagnostic", err)
	}
}

func TestRootDiagnosticBoundsErrorsAndRetainsTheStoppedSession(t *testing.T) {
	recorder := &rootNetworkDiagnostics{}
	recorder.observe(log.Event{LogLevel: log.DEBUG, Payload: "ignored"})
	for i := range 40 {
		recorder.observe(log.Event{LogLevel: log.WARNING, Payload: fmt.Sprintf("error-%d %s", i, strings.Repeat("x", 2048))})
	}
	if len(recorder.events) != 32 || !strings.HasPrefix(recorder.events[0]["message"], "error-8 ") || len(recorder.events[0]["message"]) != 1024 {
		t.Fatal("unbounded or incorrectly ordered error history")
	}
	directory := t.TempDir()
	path := filepath.Join(directory, "network-state.json")
	if err := os.WriteFile(path, []byte(`{"mode":"previous-session"}`), 0600); err != nil {
		t.Fatal(err)
	}
	changed, stop := startRootNetworkDiagnostics(directory)
	log.Warnln("root diagnostic test: failed connection")
	deadline := time.Now().Add(2 * time.Second)
	for {
		changed()
		data, err := os.ReadFile(path)
		if err == nil && strings.Contains(string(data), "failed connection") {
			break
		}
		if time.Now().After(deadline) {
			stop()
			t.Fatal("diagnostic did not observe the warning before shutdown")
		}
		time.Sleep(time.Millisecond)
	}
	stop()
	previous, err := os.ReadFile(filepath.Join(directory, "network-state.previous.json"))
	if err != nil || !strings.Contains(string(previous), "previous-session") {
		t.Fatal("previous runtime diagnostic lost", err)
	}
	data, err := os.ReadFile(path)
	if err != nil || !json.Valid(data) || !strings.Contains(string(data), "failed connection") {
		t.Fatal("stopped runtime diagnostic lost", string(data), err)
	}
}

func TestRootDiagnosticDoesNotWaitForAConfigMutation(t *testing.T) {
	configMu.Lock()
	defer configMu.Unlock()
	if state := rootNetworkState(); state != nil {
		t.Fatal("busy runtime was sampled")
	}
	path := filepath.Join(t.TempDir(), "network-state.json")
	previous := []byte(`{"mode":"last-observed"}`)
	if err := os.WriteFile(path, previous, 0600); err != nil {
		t.Fatal(err)
	}
	(&rootNetworkDiagnostics{}).save(path)
	data, err := os.ReadFile(path)
	if err != nil || string(data) != string(previous) {
		t.Fatal("busy sample replaced the last complete diagnostic", err)
	}
}

func TestRootDiagnosticKeepsDnsAndFakeIpFailuresEvenAtLowLogLevels(t *testing.T) {
	recorder := &rootNetworkDiagnostics{}
	for _, payload := range []string{
		"[Metadata PreHandle] error: fake DNS record missing",
		"[Process] find process error for connection: process not found",
		"[DNS] resolve example.test error: timeout",
	} {
		recorder.observe(log.Event{LogLevel: log.DEBUG, Payload: payload})
	}
	recorder.observe(log.Event{LogLevel: log.DEBUG, Payload: "[DNS] example.test --> 192.0.2.1"})
	if len(recorder.events) != 3 {
		t.Fatal("failed pre-routing connections disappeared", recorder.events)
	}
}

func TestRootDiagnosticRetainsDNSRepliesThroughTheCoreHookAfterStopping(t *testing.T) {
	directory := t.TempDir()
	_, stop := startRootNetworkDiagnostics(directory)
	query := new(D.Msg)
	query.SetQuestion("images.example.test.", D.TypeA)
	reply := new(D.Msg)
	reply.SetReply(query)
	answer, err := D.NewRR("images.example.test. 60 IN A 192.0.2.1")
	if err != nil {
		t.Fatal(err)
	}
	reply.Answer = []D.RR{answer}
	dns.DefaultQueryNotify(dns.QueryRecord{
		Question: query.Question[0], Msg: reply, Initiator: "app",
		Upstream: "https://user:private-password@resolver.test/private-path?key=private-key#proxy",
		Cached:   true, Start: time.Now(),
	})
	stop()
	if activeRootNetworkDiagnostics.Load() != nil {
		t.Fatal("stopped session still receives DNS diagnostics")
	}
	data, err := os.ReadFile(filepath.Join(directory, "network-state.json"))
	if err != nil {
		t.Fatal(err)
	}
	var state struct {
		DNS []DnsQuery `json:"recentDNS"`
	}
	if err := json.Unmarshal(data, &state); err != nil {
		t.Fatal(err)
	}
	if len(state.DNS) != 1 {
		t.Fatal("DNS replies disappeared with the running session", string(data))
	}
	recorded := state.DNS[0]
	if recorded.Domain != "images.example.test" || recorded.Type != "A" || recorded.Rcode != "NOERROR" ||
		!recorded.Cached || recorded.Upstream != "https://resolver.test" ||
		!reflect.DeepEqual(recorded.Answers, []string{"192.0.2.1"}) {
		t.Fatal("actual DNS answer lost", recorded)
	}
	if strings.Contains(string(data), "private-") || strings.Contains(string(data), "user:") {
		t.Fatal("resolver credentials in diagnostic")
	}
}

func TestRootDiagnosticBoundsDNSRepliesWithoutMutatingTheResponse(t *testing.T) {
	recorder := &rootNetworkDiagnostics{}
	reply := new(D.Msg)
	label := strings.Repeat("x", 60)
	target := strings.Join([]string{label, label, label, label}, ".")
	for range 10 {
		answer, err := D.NewRR(fmt.Sprintf("images.test. 60 IN CNAME %s.", target))
		if err != nil {
			t.Fatal(err)
		}
		reply.Answer = append(reply.Answer, answer)
	}
	text, err := D.NewRR(`images.test. 60 IN TXT "private-value"`)
	if err != nil {
		t.Fatal(err)
	}
	reply.Answer = append([]D.RR{text}, reply.Answer...)
	for i := range 24 {
		recorder.observeDNS(dns.QueryRecord{
			Question: dnsQuestion(fmt.Sprintf("images-%d.%s", i, strings.Repeat("x", 300)), D.TypeA),
			Msg:      reply, Initiator: strings.Repeat("app", 30), Start: time.Now(),
		})
	}
	if len(reply.Answer) != 11 {
		t.Fatal("diagnostic changed the live DNS response")
	}
	if len(recorder.dns) != 16 || !strings.HasPrefix(recorder.dns[0].Domain, "images-8.") {
		t.Fatal("incorrect DNS history bound or order")
	}
	for _, query := range recorder.dns {
		if len(query.Domain) > 253 || len(query.Initiator) > 32 || len(query.Answers) != 4 {
			t.Fatal("unbounded DNS record", query)
		}
	}
	data, err := json.Marshal(recorder.dns)
	if err != nil || len(data) > 24*1024 || strings.Contains(string(data), "private-value") {
		t.Fatal("DNS history exceeds its export budget or includes TXT data", len(data), err)
	}
}

func TestRootDiagnosticKeepsDNSFailuresWithoutCopyingCredentials(t *testing.T) {
	recorder := &rootNetworkDiagnostics{}
	for _, err := range []error{fmt.Errorf("https://user:private-password@resolver.test: %w", context.DeadlineExceeded), fmt.Errorf("private-error")} {
		recorder.observeDNS(dns.QueryRecord{
			Question: dnsQuestion("images.test", D.TypeAAAA), Err: err, Start: time.Now(),
		})
	}
	if recorder.dns[0].Error != "timeout" || recorder.dns[1].Error != "failed" {
		t.Fatal("DNS failure kind lost", recorder.dns)
	}
	data, err := json.Marshal(recorder.dns)
	if err != nil || strings.Contains(string(data), "private-") {
		t.Fatal("credentials in DNS failure diagnostic", err)
	}
}
