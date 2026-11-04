package core

import (
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/tunnel"
)

func TestRootTunHonorsAndroidUIOptions(t *testing.T) {
	options := RootOptions{Enable: true, IPv6: true, DNSHijacking: false, Stack: "mips", MTU: 8192,
		CongestionController: "bbr", RouteAddress: []string{"8.0.0.0/8", "2001:db8::/32"},
		IncludeUID: []uint32{10190, 10200}, ExcludeUID: []uint32{10300}}
	tun, err := rootTunConfig(options)
	if err != nil {
		t.Fatal(err)
	}
	if tun.Stack != constant.TunMips || tun.MTU != 8192 || tun.CongestionController != "bbr" || len(tun.Inet6Address) != 1 {
		t.Fatalf("UI values lost: %+v", tun)
	}
	if !tun.AutoRoute || !tun.AutoRedirect || !tun.AutoDetectInterface || !reflect.DeepEqual(tun.IncludeInterface, []string{"lo"}) {
		t.Fatal("Root routing must be managed by the native TUN", tun)
	}
	if !reflect.DeepEqual(tun.IncludeUID, options.IncludeUID) || !reflect.DeepEqual(tun.ExcludeUID, options.ExcludeUID) {
		t.Fatal("application filter changed")
	}
	if !reflect.DeepEqual(tun.DNSHijack, []string{"198.18.0.2:53", "[fdfe:dcba:9876::2]:53"}) {
		t.Fatal(tun.DNSHijack)
	}
	if len(tun.RouteAddress) != 4 || tun.RouteAddress[0].String() != "8.0.0.0/8" {
		t.Fatal(tun.RouteAddress)
	}
	options.IPv6 = false
	options.DNSHijacking = true
	options.Stack = "gvisor"
	options.MTU = 0
	tun, err = rootTunConfig(options)
	if err != nil || len(tun.Inet6Address) != 0 || tun.MTU != 9000 || !reflect.DeepEqual(tun.DNSHijack, []string{"any:53"}) {
		t.Fatal(tun, err)
	}
	options.Enable = false
	tun, err = rootTunConfig(options)
	if err != nil || tun.Enable {
		t.Fatal("VPN switch ignored")
	}
}

func TestRootSystemDNSIsCapturedWithoutHijackingOtherResolvers(t *testing.T) {
	options := RootOptions{Enable: true, Stack: "mips", RouteAddress: []string{"8.0.0.0/8"},
		SystemDNS: []string{"192.168.2.1:53", "192.168.2.1:53", "[fe80::5%wlan0]:53"}}
	tun, err := rootTunConfig(options)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(tun.DNSHijack, []string{"198.18.0.2:53", "192.168.2.1:53"}) {
		t.Fatal("system DNS must reach Core while custom DNS keeps the UI policy", tun.DNSHijack)
	}
	if got := tun.RouteAddress[len(tun.RouteAddress)-1].String(); got != "192.168.2.1/32" {
		t.Fatal("private system DNS was lost to LAN bypass", got)
	}
	options.IPv6 = true
	tun, err = rootTunConfig(options)
	if err != nil || tun.DNSHijack[len(tun.DNSHijack)-1] != "[fe80::5]:53" {
		t.Fatal(tun.DNSHijack, err)
	}
	options.DNSHijacking = true
	tun, err = rootTunConfig(options)
	if err != nil || !reflect.DeepEqual(tun.DNSHijack, []string{"any:53"}) {
		t.Fatal(tun.DNSHijack, err)
	}
	options.SystemDNS = []string{"not-an-ip"}
	if _, err := rootTunConfig(options); err == nil {
		t.Fatal("accepted an invalid system DNS endpoint")
	}
}

func TestRootOverlayKeepsProfileAndUISettings(t *testing.T) {
	previous := rootOptions
	defer func() { rootOptions = previous }()
	rootOptions = &RootOptions{Enable: true, Stack: "mips", MTU: 1500}
	cfg := &config.Config{General: &config.General{MixedPort: 7899, AllowLan: true, IPv6: true, Mode: tunnel.Global},
		DNS: &config.DNS{Enable: true, EnhancedMode: constant.DNSMapping, NameServer: []dns.NameServer{{Net: "https", Addr: "dns.example/dns-query"}},
			NameServerPolicy: []dns.Policy{{Domain: "corp.example", NameServers: []dns.NameServer{{Addr: "10.0.0.53"}}}}}}
	for range 3 {
		if err := applyRootOptions(cfg); err != nil {
			t.Fatal(err)
		}
	}
	if cfg.General.MixedPort != 7899 || !cfg.General.AllowLan || !cfg.General.IPv6 || cfg.General.Mode != tunnel.Global {
		t.Fatal("UI general settings overwritten")
	}
	if cfg.DNS.EnhancedMode != constant.DNSMapping || cfg.DNS.NameServer[0].Addr != "dns.example/dns-query" || len(cfg.DNS.NameServerPolicy) != 2 || cfg.DNS.NameServerPolicy[1].Domain != "corp.example" {
		t.Fatalf("DNS settings overwritten: %+v", cfg.DNS)
	}
	cfg.DNS.Enable = false
	if err := applyRootOptions(cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.DNS.Enable || len(cfg.General.Tun.DNSHijack) != 0 {
		t.Fatal("disabled DNS silently enabled")
	}
}

func TestRootRejectsInvalidNetworkOptions(t *testing.T) {
	for _, options := range []RootOptions{{Stack: "typo"}, {Stack: "mips", RouteAddress: []string{"not-a-route"}}} {
		if _, err := rootTunConfig(options); err == nil {
			t.Fatal("accepted invalid option", options)
		}
	}
}

func TestRootPerAppUsesRealDNSWithoutChangingOtherModesOrEnablingDNS(t *testing.T) {
	previous := rootOptions
	defer func() { rootOptions = previous }()
	for _, test := range []struct {
		name       string
		options    *RootOptions
		dnsEnabled bool
		want       constant.DNSMode
	}{
		{"VPN", nil, true, constant.DNSFakeIP},
		{"Root all apps", &RootOptions{Enable: true, Stack: "mips"}, true, constant.DNSFakeIP},
		{"Root per-app", &RootOptions{Enable: true, PerApp: true, Stack: "mips"}, true, constant.DNSMapping},
		{"TUN disabled", &RootOptions{PerApp: true, Stack: "mips"}, true, constant.DNSFakeIP},
		{"DNS disabled", &RootOptions{Enable: true, PerApp: true, Stack: "mips"}, false, constant.DNSFakeIP},
	} {
		t.Run(test.name, func(t *testing.T) {
			rootOptions = test.options
			cfg := &config.Config{General: &config.General{}, DNS: &config.DNS{
				Enable: test.dnsEnabled, EnhancedMode: constant.DNSFakeIP,
				NameServer: []dns.NameServer{{Net: "https", Addr: "dns.example/dns-query"}},
			}}
			if err := applyRootOptions(cfg); err != nil {
				t.Fatal(err)
			}
			if cfg.DNS.EnhancedMode != test.want || cfg.DNS.Enable != test.dnsEnabled || cfg.DNS.NameServer[0].Addr != "dns.example/dns-query" {
				t.Fatalf("unexpected runtime DNS settings: %+v", cfg.DNS)
			}
		})
	}
}
