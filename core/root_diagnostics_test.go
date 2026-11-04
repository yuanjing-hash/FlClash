package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
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
