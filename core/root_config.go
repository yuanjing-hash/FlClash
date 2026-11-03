package core

import (
	"fmt"
	"net"
	"net/netip"
	"slices"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	LC "github.com/metacubex/mihomo/listener/config"
)

type RootOptions struct {
	Enable               bool     `json:"enable"`
	IPv6                 bool     `json:"ipv6"`
	DNSHijacking         bool     `json:"dnsHijacking"`
	Stack                string   `json:"stack"`
	MTU                  uint32   `json:"mtu"`
	CongestionController string   `json:"congestionController"`
	RouteAddress         []string `json:"routeAddress"`
	IncludeUID           []uint32 `json:"includeUid"`
	ExcludeUID           []uint32 `json:"excludeUid"`
	SystemDNS            []string `json:"systemDns"`
}

var (
	rootOptions   *RootOptions
	updateRootTun func(LC.Tun) error
	stopRootTun   func()
)

func rootTunConfig(options RootOptions) (LC.Tun, error) {
	stack, ok := constant.StackTypeMapping[options.Stack]
	if !ok {
		return LC.Tun{}, fmt.Errorf("unsupported root TUN stack: %s", options.Stack)
	}
	mtu := options.MTU
	if mtu == 0 {
		mtu = 9000
	}
	mtu = max(1280, min(65535, mtu))
	tun := LC.Tun{
		Enable: options.Enable, Device: "flcrtun0", Stack: stack, MTU: mtu,
		AutoRoute: true, AutoRedirect: true, AutoDetectInterface: true, StrictRoute: true,
		IncludeInterface:   []string{"lo"},
		IPRoute2TableIndex: 2022, IPRoute2RuleIndex: 9000,
		Inet4Address: []netip.Prefix{netip.MustParsePrefix("198.18.0.1/30")},
		DNSHijack:    []string{"198.18.0.2:53"},
		IncludeUID:   options.IncludeUID, ExcludeUID: options.ExcludeUID,
		CongestionController: options.CongestionController,
	}
	if options.IPv6 {
		tun.Inet6Address = []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/126")}
		tun.DNSHijack = append(tun.DNSHijack, "[fdfe:dcba:9876::2]:53")
	}
	if options.DNSHijacking {
		tun.DNSHijack = []string{"any:53"}
	}
	for _, value := range options.RouteAddress {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return LC.Tun{}, fmt.Errorf("root route %q: %w", value, err)
		}
		if prefix.Addr().Is4() || options.IPv6 {
			tun.RouteAddress = append(tun.RouteAddress, prefix)
		}
	}
	if len(options.RouteAddress) > 0 {
		tun.RouteAddress = append(tun.RouteAddress, netip.MustParsePrefix("198.18.0.0/30"))
		if options.IPv6 {
			tun.RouteAddress = append(tun.RouteAddress, netip.MustParsePrefix("fdfe:dcba:9876::/126"))
		}
	}
	servers, err := rootSystemDNS(options.SystemDNS)
	if err != nil {
		return LC.Tun{}, err
	}
	for _, address := range servers {
		if !address.Is4() && !options.IPv6 {
			continue
		}
		if !options.DNSHijacking {
			tun.DNSHijack = append(tun.DNSHijack, net.JoinHostPort(address.String(), "53"))
		}
		if len(options.RouteAddress) > 0 {
			tun.RouteAddress = append(tun.RouteAddress, netip.PrefixFrom(address, address.BitLen()))
		}
	}
	return tun, nil
}

func rootSystemDNS(values []string) ([]netip.Addr, error) {
	var addresses []netip.Addr
	for _, value := range values {
		host, _, err := net.SplitHostPort(value)
		if err != nil {
			host = value
		}
		address, err := netip.ParseAddr(host)
		if err != nil {
			return nil, fmt.Errorf("invalid system DNS endpoint %q", value)
		}
		address = address.Unmap().WithZone("")
		if !address.IsUnspecified() && !address.IsLoopback() && !address.IsMulticast() && !slices.Contains(addresses, address) {
			addresses = append(addresses, address)
		}
	}
	return addresses, nil
}

func applyRootOptions(cfg *config.Config) error {
	if rootOptions == nil {
		return nil
	}
	tun, err := rootTunConfig(*rootOptions)
	if err != nil {
		return err
	}
	cfg.General.Tun = tun
	cfg.General.RoutingMark = 0x40000000
	if cfg.DNS.Enable {
		policies := make([]dns.Policy, 0, len(cfg.DNS.NameServerPolicy))
		for _, policy := range cfg.DNS.NameServerPolicy {
			if policy.Domain != "flclash-root-health.invalid" {
				policies = append(policies, policy)
			}
		}
		cfg.DNS.NameServerPolicy = append([]dns.Policy{{
			Domain:      "flclash-root-health.invalid",
			NameServers: []dns.NameServer{{Net: "rcode", Addr: "success"}},
		}}, policies...)
	} else {
		cfg.General.Tun.DNSHijack = nil
	}
	return nil
}
