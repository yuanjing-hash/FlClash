package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type rootNetworkDiagnostics struct {
	mu     sync.Mutex
	events []map[string]string
}

func (r *rootNetworkDiagnostics) observe(event log.Event) {
	failedLookup := strings.HasPrefix(event.Payload, "[Metadata PreHandle]") ||
		strings.HasPrefix(event.Payload, "[Process] find process error") ||
		(strings.HasPrefix(event.Payload, "[DNS]") && strings.Contains(event.Payload, " error:"))
	if event.LogLevel < log.WARNING && !failedLookup {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.events) == 32 {
		copy(r.events, r.events[1:])
		r.events = r.events[:31]
	}
	payload := event.Payload
	if len(payload) > 1024 {
		payload = payload[:1024]
	}
	r.events = append(r.events, map[string]string{"at": time.Now().UTC().Format(time.RFC3339Nano), "level": event.Type(), "message": payload})
}

func rootNetworkState() map[string]any {
	if !configMu.TryLock() {
		return nil
	}
	defer configMu.Unlock()
	if !selectMu.TryLock() {
		return nil
	}
	defer selectMu.Unlock()
	state := map[string]any{"mode": tunnel.Mode().String(), "sniffing": tunnel.IsSniffing(), "running": isRunning.Load()}
	state["cacheFile"] = constant.Path.Cache()
	if cfg := currentConfig; cfg != nil {
		state["proxyCount"], state["ruleCount"] = len(cfg.Proxies), len(cfg.Rules)
		state["findProcessMode"] = cfg.General.FindProcessMode.String()
		state["dnsEnabled"], state["dnsMode"] = cfg.DNS.Enable, cfg.DNS.EnhancedMode.String()
		state["dnsHijack"] = cfg.General.Tun.DNSHijack
		if cfg.Profile != nil {
			state["storeFakeIP"] = cfg.Profile.StoreFakeIP
			if cfg.Profile.StoreFakeIP && cfg.DNS.Enable && cfg.DNS.EnhancedMode == constant.DNSFakeIP {
				state["fakeIPStoreReady"] = cachefile.Cache().DB != nil
			}
		}
	}
	var chain []string
	seen := map[string]bool{}
	for proxy := lookupProxy(globalProxyName); proxy != nil && len(chain) < 16 && !seen[proxy.Name()]; {
		seen[proxy.Name()] = true
		chain = append(chain, proxy.Name())
		switch proxy.Type() {
		case constant.Selector, constant.URLTest, constant.Fallback:
			proxy = proxy.Unwrap(nil, false)
		default:
			proxy = nil
		}
	}
	state["globalChain"] = chain
	connections := make([]map[string]any, 0, 32)
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		info := tracker.Info()
		metadata := info.Metadata
		connections = append(connections, map[string]any{
			"uid": metadata.Uid, "process": metadata.Process, "network": metadata.NetWork.String(),
			"host": metadata.Host, "sniffHost": metadata.SniffHost, "destination": metadata.RemoteAddress(),
			"chains": info.Chain, "rule": info.Rule, "upload": info.UploadTotal.Load(), "download": info.DownloadTotal.Load(),
		})
		return len(connections) < 32
	})
	state["connections"] = connections
	return state
}

func (r *rootNetworkDiagnostics) save(path string) {
	state := rootNetworkState()
	if state == nil {
		return
	}
	r.mu.Lock()
	state["recentErrors"] = append([]map[string]string(nil), r.events...)
	r.mu.Unlock()
	state["at"] = time.Now().UTC().Format(time.RFC3339Nano)
	data, err := json.MarshalIndent(state, "", "  ")
	if err == nil {
		err = os.WriteFile(path+".tmp", data, 0600)
	}
	if err == nil {
		_ = os.Rename(path+".tmp", path)
	}
}

func startRootNetworkDiagnostics(directory string) (func(), func()) {
	path := filepath.Join(directory, "network-state.json")
	_ = os.Rename(path, filepath.Join(directory, "network-state.previous.json"))
	recorder := &rootNetworkDiagnostics{}
	subscription := log.Subscribe()
	drained := make(chan struct{})
	safeGo("root diagnostic log", func() {
		defer close(drained)
		for event := range subscription {
			recorder.observe(event)
		}
	})
	changed, stop, stopped := make(chan struct{}, 1), make(chan struct{}), make(chan struct{})
	safeGo("root network diagnostics", func() {
		defer close(stopped)
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
			case <-changed:
			case <-stop:
				recorder.save(path)
				return
			}
			recorder.save(path)
		}
	})
	return func() {
			select {
			case changed <- struct{}{}:
			default:
			}
		}, func() {
			log.UnSubscribe(subscription)
			<-drained
			close(stop)
			<-stopped
		}
}
