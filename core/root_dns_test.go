package core

import (
	"context"
	"net"
	"net/netip"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/tunnel"
	D "github.com/miekg/dns"
)

type rootDnsTestService struct{ queried chan string }

func (s rootDnsTestService) ServeMsg(_ context.Context, query *D.Msg) (*D.Msg, error) {
	s.queried <- query.Question[0].Name
	answer := new(D.Msg).SetReply(query)
	answer.Answer = []D.RR{&D.A{Hdr: D.RR_Header{Name: query.Question[0].Name, Rrtype: D.TypeA, Class: D.ClassINET}, A: net.IPv4(198, 18, 0, 4)}}
	return answer, nil
}

type rootDnsTestTunnel struct {
	rootPacketTunnel
	forwarded chan *constant.Metadata
}

func (r rootDnsTestTunnel) HandleTCPConn(conn net.Conn, metadata *constant.Metadata) {
	r.forwarded <- metadata
	_ = conn.Close()
}

func TestRootRedirectedDnsUsesTheSameCoreServiceInEveryMode(t *testing.T) {
	previousService, previousMode := resolver.DefaultService, tunnel.Mode()
	t.Cleanup(func() { resolver.DefaultService = previousService; tunnel.SetMode(previousMode) })
	for _, mode := range []tunnel.TunnelMode{tunnel.Rule, tunnel.Global, tunnel.Direct} {
		t.Run(mode.String(), func(t *testing.T) {
			tunnel.SetMode(mode)
			for _, target := range []string{"192.168.5.168", "218.2.2.2", "2001:db8::53", "9.9.9.9"} {
				service := rootDnsTestService{queried: make(chan string, 1)}
				resolver.DefaultService = service
				base := rootDnsTestTunnel{forwarded: make(chan *constant.Metadata, 1)}
				hijack := net.JoinHostPort(target, "53")
				if target == "9.9.9.9" {
					hijack = "any:53"
				}
				adapter := newRootDNSTunnel(base, LC.Tun{DNSHijack: []string{hijack}})
				client, server := net.Pipe()
				defer client.Close()
				done := make(chan struct{})
				go func() {
					defer close(done)
					adapter.HandleTCPConn(server, &constant.Metadata{Type: constant.REDIR, InName: rootTunInboundName, DstIP: netip.MustParseAddr(target), DstPort: 53})
				}()
				_ = client.SetDeadline(time.Now().Add(2 * time.Second))
				wire := &D.Conn{Conn: client}
				query := new(D.Msg).SetQuestion("root-dns.test.", D.TypeA)
				if err := wire.WriteMsg(query); err != nil {
					t.Fatal(err)
				}
				answer, err := wire.ReadMsg()
				_ = client.Close()
				<-done
				if err != nil || len(answer.Answer) != 1 || answer.Answer[0].(*D.A).A.String() != "198.18.0.4" {
					t.Fatalf("redirected DNS did not reach Core: %v, %v", answer, err)
				}
				if <-service.queried != "root-dns.test." || len(base.forwarded) != 0 {
					t.Fatal("DNS escaped into the proxy rule path")
				}
			}
		})
	}
}

func TestRootDnsAdapterPreservesUiHijackingScopeAndOtherInbounds(t *testing.T) {
	for _, test := range []struct {
		name, target, inbound string
		port                  uint16
		typeID                constant.Type
		hijack                []string
	}{
		{"custom resolver", "9.9.9.9", rootTunInboundName, 53, constant.REDIR, []string{"192.168.5.168:53"}},
		{"HTTPS", "192.168.5.168", rootTunInboundName, 443, constant.REDIR, []string{"any:53"}},
		{"other listener", "192.168.5.168", "user-listener", 53, constant.REDIR, []string{"any:53"}},
		{"SOCKS", "192.168.5.168", rootTunInboundName, 53, constant.SOCKS5, []string{"any:53"}},
		{"DNS disabled", "192.168.5.168", rootTunInboundName, 53, constant.REDIR, nil},
	} {
		t.Run(test.name, func(t *testing.T) {
			base := rootDnsTestTunnel{forwarded: make(chan *constant.Metadata, 1)}
			adapter := newRootDNSTunnel(base, LC.Tun{DNSHijack: test.hijack})
			client, server := net.Pipe()
			defer client.Close()
			metadata := &constant.Metadata{Type: test.typeID, InName: test.inbound, DstIP: netip.MustParseAddr(test.target), DstPort: test.port}
			adapter.HandleTCPConn(server, metadata)
			if len(base.forwarded) != 1 || <-base.forwarded != metadata {
				t.Fatal("unrelated traffic was intercepted")
			}
		})
	}
}
