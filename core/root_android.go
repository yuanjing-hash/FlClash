//go:build android

package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"core/platform"
	"core/rootbridge"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
)

type RootLaunch struct {
	Init     InitParams                 `json:"init"`
	Setup    SetupParams                `json:"setup"`
	Tun      RootOptions                `json:"tun"`
	Port     int                        `json:"port"`
	Token    string                     `json:"token"`
	AppUID   int                        `json:"appUid"`
	Ready    string                     `json:"ready"`
	Packages map[string]string          `json:"packages"`
	Updates  map[string]json.RawMessage `json:"updates,omitempty"`
}

type rootTunRuntime struct {
	mu         sync.Mutex
	listener   *sing_tun.Listener
	options    LC.Tun
	ready      string
	err        error
	configured bool
}

func (r *rootTunRuntime) update(options LC.Tun) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	options.Sort()
	if r.listener != nil && options.Equal(r.options) {
		r.listener.OnReload()
		return nil
	}
	r.closeLocked()
	r.options = options
	r.err = nil
	if options.Enable {
		r.listener, r.err = sing_tun.New(options, newRootDNSTunnel(tunnel.Tunnel, options), inbound.WithInName(rootTunInboundName))
		if r.err != nil {
			return r.err
		}
	}
	temporary := r.ready + ".tmp"
	if err := os.WriteFile(temporary, []byte(strconv.Itoa(os.Getpid())+"\n"), 0600); err != nil {
		r.err = err
		return err
	}
	r.err = os.Rename(temporary, r.ready)
	r.configured = r.err == nil
	return r.err
}

func (r *rootTunRuntime) closeLocked() {
	_ = os.Remove(r.ready)
	r.configured = false
	if r.listener != nil {
		_ = r.listener.Close()
		r.listener = nil
	}
}

func (r *rootTunRuntime) stop() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.closeLocked()
}

func (r *rootTunRuntime) health() (bool, string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return false, r.err.Error()
	}
	return r.configured && isRunning.Load() && (r.listener != nil || !r.options.Enable), ""
}

func RunRoot(path string, checkOnly bool) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	var launch RootLaunch
	if err := json.NewDecoder(file).Decode(&launch); err != nil {
		return err
	}
	home, err := os.Lstat(launch.Init.HomeDir)
	if err != nil || !home.IsDir() || launch.AppUID < 10000 {
		return errors.New("invalid app home")
	}
	stat := home.Sys().(*syscall.Stat_t)
	if int(stat.Uid) != launch.AppUID || filepath.Clean(launch.Ready) != "/data/adb/flclash-root/run/core-ready" {
		return errors.New("app home owner or root ready path mismatch")
	}
	if _, err := rootTunConfig(launch.Tun); err != nil {
		return err
	}
	if launch.Port < 1024 || launch.Port > 65535 || len(launch.Token) < 32 {
		return errors.New("invalid root control endpoint")
	}
	rootOptions = &launch.Tun
	constant.SetHomeDir(launch.Init.HomeDir)
	setRootCacheFile(filepath.Join(filepath.Dir(launch.Ready), "..", "state"))
	if checkOnly {
		_, err := loadSetupConfig(&launch.Setup)
		return err
	}
	realUid, realGid = launch.AppUID, int(stat.Gid)
	if err := seedRootEpoch(); err != nil {
		return fmt.Errorf("phase=root/route-epoch: %w", err)
	}
	native := &rootTunRuntime{ready: launch.Ready}
	updateRootTun, stopRootTun = native.update, native.stop
	defer handleShutdown()
	process.DefaultPackageNameResolver = rootPackageResolver(launch.Packages, platform.QuerySocketUidFromProcFs)
	networkChanged, stopDiagnostics := startRootNetworkDiagnostics(filepath.Join(filepath.Dir(launch.Ready), "..", "logs"))
	defer stopDiagnostics()
	listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(launch.Port)))
	if err != nil {
		return fmt.Errorf("phase=root/control-listener: %w", err)
	}
	defer listener.Close()
	server := &rootbridge.Server{Token: launch.Token, Events: SetEventListener}
	var launchMu sync.Mutex
	persist := func() {
		data, err := json.Marshal(launch)
		if err == nil {
			err = os.WriteFile(path+".tmp", data, 0600)
		}
		if err == nil {
			err = os.Rename(path+".tmp", path)
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "phase=root/persist-ui-state: %v\n", err)
		}
	}
	updateDnsCapture := func(value string) error {
		var addresses []string
		if value != "" {
			addresses = strings.Split(value, ",")
		}
		if _, err := rootSystemDNS(addresses); err != nil {
			return err
		}
		launchMu.Lock()
		defer launchMu.Unlock()
		configMu.Lock()
		defer configMu.Unlock()
		if slices.Equal(launch.Tun.SystemDNS, addresses) {
			return nil
		}
		launch.Tun.SystemDNS = slices.Clone(addresses)
		if currentConfig != nil {
			if err := applyRootOptions(currentConfig); err != nil {
				return err
			}
			updateListeners(currentConfig)
			bumpRouteEpoch()
		}
		persist()
		networkChanged()
		return nil
	}
	server.Invoke = func(data []byte, reply func([]byte)) {
		var call MethodCall
		if json.Unmarshal(data, &call) == nil {
			switch call.Method {
			case "__root.dnsCapture":
				var value string
				err := json.Unmarshal(call.Arguments, &value)
				if err == nil {
					err = updateDnsCapture(value)
				}
				response := MethodResponse{ID: call.ID, Result: true}
				if err != nil {
					response.Result = nil
					response.Error = &MethodError{Code: "root_dns_capture_failed", Message: err.Error()}
				}
				reply(encodeResponse(response))
				return
			case "__root.health":
				ready, detail := native.health()
				configMu.Lock()
				dnsEnabled := currentConfig != nil && currentConfig.DNS.Enable && launch.Tun.Enable
				configMu.Unlock()
				reply(encodeResponse(MethodResponse{ID: call.ID, Result: map[string]any{"ready": ready, "detail": detail, "dnsEnabled": dnsEnabled}}))
				return
			case "__root.resetNetwork":
				ResetNetwork()
				reply(encodeResponse(MethodResponse{ID: call.ID, Result: true}))
				return
			case "__root.events":
				if string(call.Arguments) == "true" {
					SetEventListener(reply)
				} else {
					SetEventListener(nil)
				}
				reply(encodeResponse(MethodResponse{ID: call.ID, Result: true}))
				return
			case "__root.handoff":
				var calls []MethodCall
				if err := json.Unmarshal(call.Arguments, &calls); err != nil {
					reply(encodeResponse(MethodResponse{ID: call.ID, Error: &MethodError{Code: "invalid_arguments", Message: err.Error()}}))
					return
				}
				for _, replay := range calls {
					if _, valid := methodHandlers[replay.Method]; !valid || replay.Method == crashMethod {
						continue
					}
					request, _ := json.Marshal(replay)
					completed := make(chan []byte, 1)
					server.Invoke(request, func(answer []byte) { completed <- answer })
					var answer MethodResponse
					if err := json.Unmarshal(<-completed, &answer); err != nil || answer.Error != nil {
						if answer.Error == nil {
							answer.Error = &MethodError{Code: "root_handoff_failed", Message: err.Error()}
						}
						reply(encodeResponse(MethodResponse{ID: call.ID, Error: answer.Error}))
						return
					}
					if message, ok := answer.Result.(string); ok && message != "" && (replay.Method == setupConfigMethod || replay.Method == updateConfigMethod) {
						reply(encodeResponse(MethodResponse{ID: call.ID, Error: &MethodError{Code: "root_handoff_failed", Message: message}}))
						return
					}
				}
				reply(encodeResponse(MethodResponse{ID: call.ID, Result: true}))
				return
			}
		}
		InvokeMethod(string(data), func(response []byte) {
			var answer MethodResponse
			valid := json.Unmarshal(response, &answer) == nil && answer.Error == nil
			if message, ok := answer.Result.(string); ok && message != "" && (call.Method == setupConfigMethod || call.Method == updateConfigMethod) {
				valid = false
			}
			if valid {
				if call.Method == watchRouteMethod && string(call.Arguments) == "true" {
					publishRoute(routeState())
				}
				launchMu.Lock()
				switch call.Method {
				case changeProxyMethod:
					var selection ChangeProxyParams
					if result, ok := answer.Result.(map[string]any); ok && result["message"] != "" {
						break
					}
					if json.Unmarshal(call.Arguments, &selection) == nil {
						if launch.Setup.SelectedMap == nil {
							launch.Setup.SelectedMap = map[string]string{}
						}
						launch.Setup.SelectedMap[selection.GroupName] = selection.ProxyName
						persist()
					}
				case setupConfigMethod:
					var setup SetupParams
					if json.Unmarshal(call.Arguments, &setup) == nil {
						setup.Base = nil
						launch.Setup, launch.Updates = setup, nil
						persist()
					}
				case updateConfigMethod:
					var patch map[string]json.RawMessage
					if json.Unmarshal(call.Arguments, &patch) == nil {
						if launch.Updates == nil {
							launch.Updates = map[string]json.RawMessage{}
						}
						for key, value := range patch {
							launch.Updates[key] = value
						}
						persist()
					}
				}
				launchMu.Unlock()
				if call.Method == changeProxyMethod || call.Method == updateConfigMethod || call.Method == setupConfigMethod {
					networkChanged()
				}
			}
			reply(response)
		})
	}
	serveErrors := make(chan error, 1)
	go func() { serveErrors <- server.Serve(listener) }()
	fmt.Println("phase=root/load-config")
	handleInitClash(&launch.Init)
	isRunning.Store(false)
	if err := handleSetupConfig(&launch.Setup); err != nil {
		return fmt.Errorf("phase=root/apply-config: %w", err)
	}
	if len(launch.Updates) > 0 {
		data, _ := json.Marshal(launch.Updates)
		var params UpdateParams
		if err := json.Unmarshal(data, &params); err != nil {
			return err
		}
		if err := updateConfig(&params); err != nil {
			return err
		}
	}
	handleStartListener()
	if ready, detail := native.health(); !ready {
		return fmt.Errorf("phase=root/create-tun: %s", detail)
	}
	fmt.Println("phase=root/ready")
	networkChanged()
	termination := make(chan os.Signal, 1)
	signal.Notify(termination, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(termination)
	select {
	case <-termination:
		return nil
	case err := <-serveErrors:
		return err
	}
}

func seedRootEpoch() error {
	const path = "/data/adb/flclash-root/state/core-epoch"
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	previous, _ := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	if previous >= 1<<53 {
		return errors.New("invalid root route epoch")
	}
	next := max(previous+1, uint64(time.Now().UnixMilli()))
	if err := os.WriteFile(path+".tmp", []byte(strconv.FormatUint(next, 10)), 0600); err != nil {
		return err
	}
	if err := os.Rename(path+".tmp", path); err != nil {
		return err
	}
	currentRoute.mu.Lock()
	currentRoute.epoch = next
	currentRoute.mu.Unlock()
	return nil
}
