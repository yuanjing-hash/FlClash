package core

import (
	"bytes"
	"encoding/json"
	"net"
	"strings"
	"testing"
	"time"

	"core/rootbridge"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/tunnel"
)

func TestRootTransportControlsTheSameCoreAsUi(t *testing.T) {
	raw := config.DefaultRawConfig()
	raw.DNS.Enable = false
	raw.Proxy = []map[string]any{{"name": "node-a", "type": "direct"}, {"name": "node-b", "type": "direct"}}
	raw.ProxyGroup = []map[string]any{{"name": "group", "type": "select", "proxies": []string{"node-a", "node-b"}}}
	parsed, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	group := parsed.Proxies["group"]
	tunnel.UpdateProxies(parsed.Proxies, parsed.Providers)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	previousMode := tunnel.Mode()
	previousRunning := isRunning.Swap(false)
	t.Cleanup(func() { tunnel.SetMode(previousMode); isRunning.Store(previousRunning) })
	withCurrentConfig(t, parsed)
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	server := &rootbridge.Server{Token: strings.Repeat("x", 64), Events: func(func([]byte)) {}, Invoke: func(data []byte, reply func([]byte)) {
		var call MethodCall
		if err := json.Unmarshal(data, &call); err != nil {
			t.Error(err)
			return
		}
		dispatchMethodCall(&call, reply)
	}}
	go func() { _ = server.Serve(listener) }()
	conn, err := net.Dial("tcp4", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	hello, _ := json.Marshal(map[string]string{"token": server.Token})
	if err := rootbridge.WriteFrame(conn, hello); err != nil {
		t.Fatal(err)
	}
	if _, err := rootbridge.ReadFrame(conn); err != nil {
		t.Fatal(err)
	}
	call := func(method CoreMethod, args any) json.RawMessage {
		t.Helper()
		data, _ := json.Marshal(map[string]any{"id": "ui-1", "method": method, "arguments": args})
		if err := rootbridge.WriteFrame(conn, data); err != nil {
			t.Fatal(err)
		}
		data, err = rootbridge.ReadFrame(conn)
		if err != nil {
			t.Fatal(err)
		}
		var response struct {
			ID     string          `json:"id"`
			Result json.RawMessage `json:"result"`
			Error  *MethodError    `json:"error"`
		}
		if err := json.Unmarshal(data, &response); err != nil {
			t.Fatal(err)
		}
		if response.Error != nil || response.ID != "ui-1" {
			t.Fatalf("%s: %s", method, data)
		}
		return response.Result
	}
	selected := call(changeProxyMethod, &ChangeProxyParams{GroupName: "group", ProxyName: "node-b"})
	if !bytes.Contains(selected, []byte(`"changed":true`)) || groupNow(t, group) != "node-b" {
		t.Fatal("UI selection did not reach the real selector", string(selected))
	}
	proxies := call(getProxiesMethod, nil)
	if !bytes.Contains(proxies, []byte(`"now":"node-b"`)) {
		t.Fatal("UI read another core", string(proxies))
	}
	mode := tunnel.Global
	if got := call(updateConfigMethod, &UpdateParams{Mode: &mode}); string(got) != `""` {
		t.Fatal(string(got))
	}
	if tunnel.Mode() != tunnel.Global || currentConfig.General.Mode != tunnel.Global {
		t.Fatal("UI mode did not reach the running Core")
	}
	for _, method := range []CoreMethod{getConnectionsMethod, getConnectionCountMethod, getExternalProvidersMethod, getMemoryStatsMethod} {
		if len(call(method, nil)) == 0 {
			t.Fatal("missing UI result", method)
		}
	}
	for _, method := range []CoreMethod{getTrafficMethod, getTotalTrafficMethod} {
		if got := call(method, false); !bytes.Contains(got, []byte(`"up"`)) {
			t.Fatal("missing traffic counters", string(got))
		}
	}
}
