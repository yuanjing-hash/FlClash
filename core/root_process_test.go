package core

import (
	"net"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestRootResolvesSocketUidBeforePackageName(t *testing.T) {
	for _, source := range []net.Addr{&net.TCPAddr{IP: net.IPv4(198, 18, 0, 1), Port: 50560}, &net.UDPAddr{IP: net.ParseIP("fdfe:dcba:9876::1"), Port: 50560}} {
		target := &net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: 443}
		metadata := &constant.Metadata{RawSrcAddr: source, RawDstAddr: target}
		resolver := rootPackageResolver(map[string]string{"10368": "example.app"}, func(src, dst net.Addr) int {
			if src != source || dst != target {
				t.Fatal("socket identity lost")
			}
			return 10368
		})
		name, err := resolver(metadata)
		if err != nil || name != "example.app" || metadata.Uid != 10368 {
			t.Fatal(name, metadata.Uid, err)
		}
	}
}

func TestRootKeepsKnownUidAndDoesNotInventAnOwner(t *testing.T) {
	resolver := rootPackageResolver(map[string]string{"10368": "example.app"}, func(net.Addr, net.Addr) int { return -1 })
	metadata := &constant.Metadata{Uid: 10368}
	if name, err := resolver(metadata); err != nil || name != "example.app" {
		t.Fatal(name, err)
	}
	for _, metadata := range []*constant.Metadata{{}, {Uid: 10999}, {RawSrcAddr: &net.TCPAddr{}, RawDstAddr: &net.TCPAddr{}}} {
		if name, err := resolver(metadata); name != "" || err == nil {
			t.Fatal("unknown owner reported as resolved", name, err)
		}
	}
}
