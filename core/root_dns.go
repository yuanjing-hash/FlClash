package core

import (
	"context"
	"net"
	"net/netip"
	"strings"

	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/provider"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
)

const rootTunInboundName = "DEFAULT-TUN"

type rootPacketTunnel interface {
	constant.Tunnel
	provider.Tunnel
}

type rootDNSTunnel struct {
	rootPacketTunnel
	dns sing_tun.ListenerHandler
}

func newRootDNSTunnel(tunnel rootPacketTunnel, options LC.Tun) *rootDNSTunnel {
	r := &rootDNSTunnel{rootPacketTunnel: tunnel}
	for _, target := range options.DNSHijack {
		address, err := netip.ParseAddrPort(strings.Replace(target, "any", "0.0.0.0", 1))
		if err == nil {
			r.dns.DnsAddrPorts = append(r.dns.DnsAddrPorts, address)
		}
	}
	return r
}

func (r *rootDNSTunnel) HandleTCPConn(conn net.Conn, metadata *constant.Metadata) {
	// Auto-redirect's REDIR handler bypasses sing-tun's TCP DNS handler.
	if metadata.Type == constant.REDIR && metadata.InName == rootTunInboundName &&
		r.dns.ShouldHijackDns(netip.AddrPortFrom(metadata.DstIP, metadata.DstPort)) {
		_ = resolver.RelayDnsConn(context.Background(), conn, resolver.DefaultDnsReadTimeout)
		return
	}
	r.rootPacketTunnel.HandleTCPConn(conn, metadata)
}
