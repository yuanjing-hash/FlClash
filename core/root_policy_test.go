package core

import (
	"reflect"
	"testing"

	LC "github.com/metacubex/mihomo/listener/config"
)

func TestRootApplicationBypassCoversBothFamiliesWithIPv6Disabled(t *testing.T) {
	options := LC.Tun{Enable: true, StrictRoute: true, IPRoute2RuleIndex: 9000, ExcludeUID: []uint32{10200, 10201, 10200}}
	rules := rootBypassPolicy(options)
	want := []rootBypassRule{{4, 10200, 10201, 8991, 9011}, {6, 10200, 10201, 8991, 9011}}
	if !reflect.DeepEqual(rules, want) {
		t.Fatalf("excluded applications must keep native IPv4 and IPv6: %+v", rules)
	}
	for _, rule := range rules {
		if rule.priority >= options.IPRoute2RuleIndex || rule.target <= options.IPRoute2RuleIndex+10 {
			t.Fatal("application bypass must skip every native capture and strict-route rule", rule)
		}
		if rule.start <= 10199 || rule.end >= 10202 {
			t.Fatal("an unselected application bypassed capture", rule)
		}
	}
}

func TestRootApplicationWhitelistKeepsOnlySelectedUIDsCaptured(t *testing.T) {
	options := LC.Tun{Enable: true, IncludeUID: []uint32{0, 1051, 10190, 10200}, ExcludeUID: []uint32{10200}}
	rules := rootBypassPolicy(options)
	for _, family := range []int{4, 6} {
		for uid, bypass := range map[uint32]bool{0: false, 1051: false, 10190: false, 10200: true, 10191: true, 99999: true} {
			matched := false
			for _, rule := range rules {
				matched = matched || rule.family == family && rule.start <= uid && uid <= rule.end
			}
			if matched != bypass {
				t.Fatalf("IPv%d UID %d bypass=%v, want %v", family, uid, matched, bypass)
			}
		}
	}
	options.IncludeUID = nil
	options.ExcludeUID = nil
	if len(rootBypassPolicy(options)) != 0 {
		t.Fatal("all-app mode must not add application bypasses")
	}
	options.Enable = false
	options.ExcludeUID = []uint32{10200}
	if len(rootBypassPolicy(options)) != 0 {
		t.Fatal("disabled TUN must not change routing")
	}
}
