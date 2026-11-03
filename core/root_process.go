package core

import (
	"net"
	"strconv"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
)

func rootPackageResolver(packages map[string]string, lookup func(net.Addr, net.Addr) int) process.PackageNameResolver {
	return func(metadata *constant.Metadata) (string, error) {
		if metadata.Uid == 0 {
			if metadata.RawSrcAddr == nil || metadata.RawDstAddr == nil {
				return "", process.ErrInvalidNetwork
			}
			uid := lookup(metadata.RawSrcAddr, metadata.RawDstAddr)
			if uid < 0 {
				return "", process.ErrNotFound
			}
			metadata.Uid = uint32(uid)
		}
		name := packages[strconv.FormatUint(uint64(metadata.Uid), 10)]
		if name == "" {
			return "", process.ErrNotFound
		}
		return name, nil
	}
}
