package core

import (
	"context"
	"errors"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestRootNetworkWatchClosesStaleSocketsAndKeepsUnchangedLinks(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	ticks := make(chan time.Time)
	sampled := make(chan struct{}, 1)
	changed := make(chan struct{}, 8)
	done := make(chan struct{})
	var snapshot atomic.Value
	snapshot.Store("wlan0:192.168.2.10/24")
	go func() {
		defer close(done)
		watchRootNetwork(ctx, ticks, func() string {
			value := snapshot.Load().(string)
			sampled <- struct{}{}
			return value
		}, func() {
			handleResetNetwork()
			changed <- struct{}{}
		})
	}()
	t.Cleanup(func() { cancel(); <-done })
	wait := func(channel <-chan struct{}) {
		t.Helper()
		select {
		case <-channel:
		case <-time.After(3 * time.Second):
			t.Fatal("network observer did not settle")
		}
	}
	wait(sampled)
	sample := func(value string) {
		t.Helper()
		snapshot.Store(value)
		select {
		case ticks <- time.Time{}:
		case <-time.After(3 * time.Second):
			t.Fatal("network observer stopped reading updates")
		}
		wait(sampled)
	}
	local, remote := net.Pipe()
	tracker := statistic.NewTCPTracker(
		outbound.NewConn(local, outbound.NewDirectWithOption(outbound.DirectOption{Name: "network-test"})),
		statistic.DefaultManager, &constant.Metadata{}, nil, 0, 0, true,
	)
	t.Cleanup(func() { _ = tracker.Close(); _ = remote.Close() })
	sample("wlan0:192.168.2.10/24")
	sample("wlan0:192.168.2.10/24")
	if len(changed) != 0 || statistic.DefaultManager.Get(tracker.Info().UUID.String()) == nil {
		t.Fatal("unchanged network interrupted a live connection")
	}
	sample("rmnet_data0:10.0.0.2/30")
	wait(changed)
	_ = remote.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := remote.Read(make([]byte, 1)); !errors.Is(err, io.EOF) || statistic.DefaultManager.Get(tracker.Info().UUID.String()) != nil {
		t.Fatal("Wi-Fi socket survived the cellular handover")
	}
	for _, value := range []string{"rmnet_data0:10.2.0.2/30", "", "rmnet_data0:10.3.0.2/30"} {
		sample(value)
		wait(changed)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("standalone network observer did not stop")
	}
}
