package core

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/bbolt"
	"github.com/metacubex/mihomo/component/fakeip"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
)

type rootCacheResult struct {
	Blocked bool   `json:"blocked"`
	Address string `json:"address"`
	Host    string `json:"host"`
	Cache   string `json:"cache"`
	Home    string `json:"home"`
}

func TestRootCacheProcess(t *testing.T) {
	mode := os.Getenv("FLCLASH_ROOT_CACHE_TEST_MODE")
	if mode == "" {
		t.Skip("subprocess helper")
	}
	home := os.Getenv("FLCLASH_ROOT_CACHE_TEST_HOME")
	constant.SetHomeDir(home)
	if mode == "root" {
		setRootCacheFile(filepath.Join(home, "root-state"))
	}
	result := rootCacheResult{Cache: constant.Path.Cache(), Home: constant.Path.HomeDir()}
	cache := cachefile.Cache()
	result.Blocked = cache.DB == nil
	if !result.Blocked {
		pool, err := fakeip.New(fakeip.Options{IPNet: netip.MustParsePrefix("198.18.0.1/16"), Persistence: true})
		if err != nil {
			t.Fatal(err)
		}
		address := pool.Lookup("root-mode.example")
		result.Address = address.String()
		result.Host, _ = pool.LookBack(address)
		pool.StoreState()
		if err := cache.Close(); err != nil {
			t.Fatal(err)
		}
	}
	data, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	fmt.Printf("ROOT_CACHE_RESULT %s\n", data)
}

func TestRootCacheDoesNotContendWithTheEmbeddedCoreAndKeepsFakeIPMappings(t *testing.T) {
	home := t.TempDir()
	state := filepath.Join(home, "root-state")
	if err := os.Mkdir(state, 0700); err != nil {
		t.Fatal(err)
	}
	embedded, err := bbolt.Open(filepath.Join(home, "cache.db"), 0600, &bbolt.Options{Timeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	defer embedded.Close()
	run := func(mode string) rootCacheResult {
		t.Helper()
		command := exec.Command(os.Args[0], "-test.run=^TestRootCacheProcess$", "-test.count=1")
		command.Env = append(os.Environ(), "FLCLASH_ROOT_CACHE_TEST_MODE="+mode, "FLCLASH_ROOT_CACHE_TEST_HOME="+home)
		output, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("cache subprocess: %v\n%s", err, output)
		}
		for line := range strings.SplitSeq(string(output), "\n") {
			if data, ok := strings.CutPrefix(line, "ROOT_CACHE_RESULT "); ok {
				var result rootCacheResult
				if err := json.Unmarshal([]byte(data), &result); err != nil {
					t.Fatal(err)
				}
				return result
			}
		}
		t.Fatalf("cache result missing: %s", output)
		return rootCacheResult{}
	}
	if !run("shared").Blocked {
		t.Fatal("the old shared-cache lock conflict did not reproduce")
	}
	first, restarted := run("root"), run("root")
	for _, result := range []rootCacheResult{first, restarted} {
		if result.Blocked || result.Host != "root-mode.example" || result.Home != home || result.Cache != filepath.Join(state, "core-cache.db") {
			t.Fatalf("Root cache ownership or FakeIP mapping lost: %+v", result)
		}
	}
	if first.Address != restarted.Address || first.Address == "" {
		t.Fatal("Root restart lost its persistent FakeIP mapping", first, restarted)
	}
}
