package core

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"slices"
	"strings"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/log"
)

func rootNetworkFingerprint() string {
	finder := dialer.DefaultInterfaceFinder.Load()
	if finder == nil {
		return ""
	}
	iface.FlushCache()
	var names, links []string
	for _, destination := range []netip.Addr{netip.IPv4Unspecified(), netip.IPv6Unspecified()} {
		name := finder.FindInterfaceName(destination)
		if slices.Contains(names, name) {
			continue
		}
		names = append(names, name)
		link, err := iface.ResolveInterface(name)
		if err != nil || name == "flcrtun0" || link.Flags&net.FlagUp == 0 || link.Flags&net.FlagLoopback != 0 {
			continue
		}
		var addresses []string
		for _, address := range link.Addresses {
			addresses = append(addresses, address.String())
		}
		slices.Sort(addresses)
		links = append(links, fmt.Sprintf("%s:%d:%d:%s", name, link.Index, link.MTU, strings.Join(addresses, ",")))
	}
	slices.Sort(links)
	return strings.Join(links, ";")
}

func watchRootNetwork(ctx context.Context, ticks <-chan time.Time, read func() string, changed func()) {
	previous := read()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticks:
			if ctx.Err() != nil {
				return
			}
			current := read()
			if current != previous && ctx.Err() == nil {
				changed()
			}
			previous = current
		}
	}
}

func startRootNetworkMonitor() func() {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	safeGo("root network monitor", func() {
		defer close(done)
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		// The standalone Core must also recover when Android's service is absent.
		watchRootNetwork(ctx, ticker.C, rootNetworkFingerprint, func() {
			log.Infoln("[Root Network] underlying interface or addresses changed; resetting old connections")
			handleResetNetwork()
		})
	})
	return func() {
		cancel()
		<-done
	}
}
