package core

import (
	"path/filepath"

	"github.com/metacubex/mihomo/constant"
)

func setRootCacheFile(directory string) {
	constant.SetCacheFile(filepath.Join(directory, "core-cache.db"))
}
