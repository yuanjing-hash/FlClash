package core

import (
	LC "github.com/metacubex/mihomo/listener/config"
	tun "github.com/metacubex/sing-tun"
	"github.com/metacubex/sing/common/ranges"
)

type rootBypassRule struct {
	family   int
	start    uint32
	end      uint32
	priority int
	target   int
}

func rootBypassPolicy(options LC.Tun) []rootBypassRule {
	if !options.Enable {
		return nil
	}
	uidRanges := func(uids []uint32) []ranges.Range[uint32] {
		result := make([]ranges.Range[uint32], 0, len(uids))
		for _, uid := range uids {
			result = append(result, ranges.NewSingle(uid))
		}
		return result
	}
	filters := tun.Options{IncludeUID: uidRanges(options.IncludeUID), ExcludeUID: uidRanges(options.ExcludeUID)}
	var rules []rootBypassRule
	for _, uid := range filters.ExcludedRanges() {
		// Native strict routing blocks disabled IPv6 before its UID exemptions.
		for _, family := range []int{4, 6} {
			rules = append(rules, rootBypassRule{family, uid.Start, uid.End, options.IPRoute2RuleIndex - 9, options.IPRoute2RuleIndex + 11})
		}
	}
	return rules
}
