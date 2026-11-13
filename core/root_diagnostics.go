package core

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	D "github.com/miekg/dns"
)

type rootNetworkDiagnostics struct {
	mu     sync.Mutex
	events []map[string]string
	dns    []DnsQuery
}

var activeRootNetworkDiagnostics atomic.Pointer[rootNetworkDiagnostics]

func (r *rootNetworkDiagnostics) observeDNS(record dns.QueryRecord) {
	err := record.Err
	record.Err = nil
	if record.Msg != nil {
		reply := *record.Msg
		reply.Answer = nil
		for _, answer := range record.Msg.Answer {
			switch answer.(type) {
			case *D.A, *D.AAAA, *D.CNAME:
				reply.Answer = append(reply.Answer, answer)
			}
			if len(reply.Answer) == 4 {
				break
			}
		}
		record.Msg = &reply
	}
	query := newDnsQuery(record)
	query.Domain = query.Domain[:min(len(query.Domain), 253)]
	query.Initiator = query.Initiator[:min(len(query.Initiator), 32)]
	for i, answer := range query.Answers {
		query.Answers[i] = answer[:min(len(answer), 253)]
	}
	query.Upstream = ""
	if upstream, parseErr := url.Parse(record.Upstream); parseErr == nil && upstream.Host != "" {
		query.Upstream = upstream.Scheme + "://" + upstream.Host
		query.Upstream = query.Upstream[:min(len(query.Upstream), 256)]
	}
	if err != nil {
		query.Error = probeErrorKind(err)
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.dns) == 16 {
		copy(r.dns, r.dns[1:])
		r.dns = r.dns[:15]
	}
	r.dns = append(r.dns, query)
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
	state["outboundInterface"] = dialer.DefaultInterface.Load()
	state["routingMark"] = dialer.DefaultRoutingMark.Load()
	state["cacheFile"] = constant.Path.Cache()
	if cfg := currentConfig; cfg != nil {
		state["proxyCount"], state["ruleCount"] = len(cfg.Proxies), len(cfg.Rules)
		state["findProcessMode"] = cfg.General.FindProcessMode.String()
		state["dnsEnabled"], state["dnsMode"] = cfg.DNS.Enable, cfg.DNS.EnhancedMode.String()
		state["ntpEnabled"], state["ntpWriteToSystem"] = cfg.NTP.Enable, cfg.NTP.WriteToSystem
		state["dnsHijack"] = cfg.General.Tun.DNSHijack
		state["tunEnabled"], state["tunDevice"] = cfg.General.Tun.Enable, cfg.General.Tun.Device
		state["includeUID"], state["excludeUID"] = cfg.General.Tun.IncludeUID, cfg.General.Tun.ExcludeUID
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
	state["recentDNS"] = append([]DnsQuery(nil), r.dns...)
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
	activeRootNetworkDiagnostics.Store(recorder)
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
			activeRootNetworkDiagnostics.CompareAndSwap(recorder, nil)
			log.UnSubscribe(subscription)
			<-drained
			close(stop)
			<-stopped
		}
}
