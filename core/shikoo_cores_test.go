package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

const shikooCoresYaml = `
proxies:
  - {name: a, type: http, server: 1.1.1.1, port: 1, shikoo-core: fake}
  - {name: b, type: http, server: 1.1.1.2, port: 1}
  - {name: c, type: http, server: 1.1.1.3, port: 1, shikoo-core: absent}
  - {name: d, type: http, server: 1.1.1.4, port: 1, shikoo-core: fake}
`

type fakeShikooCore struct {
	got     [][]string
	stopped int
	err     error
	short   bool
}

func (f *fakeShikooCore) start(proxies []map[string]any) ([]map[string]any, func(), error) {
	var names []string
	var out []map[string]any
	for i, proxy := range proxies {
		if _, marked := proxy[shikooCoreKey]; marked {
			return nil, nil, errors.New("the marker reached the core")
		}
		names = append(names, proxy["name"].(string))
		out = append(out, map[string]any{
			"name": proxy["name"], "type": "socks5", "server": "127.0.0.1", "port": 20000 + i,
		})
	}
	f.got = append(f.got, names)
	if f.err != nil {
		return nil, nil, f.err
	}
	if f.short {
		out = out[:1]
	}
	return out, func() { f.stopped++ }, nil
}

func useFakeShikooCore(t *testing.T) *fakeShikooCore {
	t.Helper()
	fake := &fakeShikooCore{}
	registerShikooCore("fake", fake.start)
	t.Cleanup(func() {
		delete(shikooCores, "fake")
		shikooCoresRunning, shikooCoresStarting = nil, nil
	})
	return fake
}

func parseShikooCores(t *testing.T, yaml string) *config.Config {
	t.Helper()
	raw, err := config.UnmarshalRawConfig([]byte(yaml))
	if err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	cfg, err := shikooCoresParse(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return cfg
}

func proxyTypes(cfg *config.Config, names ...string) []constant.AdapterType {
	var types []constant.AdapterType
	for _, name := range names {
		types = append(types, cfg.Proxies[name].Type())
	}
	return types
}

func TestShikooCoresHandMarkedProxiesToTheirCore(t *testing.T) {
	fake := useFakeShikooCore(t)

	cfg := parseShikooCores(t, shikooCoresYaml)

	if len(fake.got) != 1 || len(fake.got[0]) != 2 || fake.got[0][0] != "a" || fake.got[0][1] != "d" {
		t.Fatalf("the core got %v, want [[a d]] in config order", fake.got)
	}
	want := []constant.AdapterType{constant.Socks5, constant.Http, constant.Http, constant.Socks5}
	got := proxyTypes(cfg, "a", "b", "c", "d")
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("types = %v, want %v: an absent core leaves its proxy to mihomo", got, want)
		}
	}
}

func TestShikooCoresLeaveAFailedCoreToMihomo(t *testing.T) {
	for _, tc := range []struct {
		name  string
		set   func(*fakeShikooCore)
		stops int
	}{
		{"an error", func(f *fakeShikooCore) { f.err = errors.New("no") }, 0},
		{"too few replacements", func(f *fakeShikooCore) { f.short = true }, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fake := useFakeShikooCore(t)
			tc.set(fake)

			cfg := parseShikooCores(t, shikooCoresYaml)

			if got := proxyTypes(cfg, "a", "d"); got[0] != constant.Http || got[1] != constant.Http {
				t.Errorf("types = %v, want mihomo's own http for both", got)
			}
			if fake.stopped != tc.stops || len(shikooCoresStarting) != 0 {
				t.Errorf("stopped %d, starting %d; want %d and none", fake.stopped, len(shikooCoresStarting), tc.stops)
			}
		})
	}
}

func TestShikooCoresStopThePreviousGenerationOnCommit(t *testing.T) {
	fake := useFakeShikooCore(t)

	parseShikooCores(t, shikooCoresYaml)
	shikooCoresCommit()
	if fake.stopped != 0 {
		t.Fatalf("the generation in use was stopped on its own commit")
	}
	parseShikooCores(t, shikooCoresYaml)
	if fake.stopped != 0 {
		t.Fatalf("the generation in use was stopped before mihomo held the next one")
	}
	shikooCoresCommit()
	if fake.stopped != 1 {
		t.Fatalf("stopped %d after the second commit, want the first generation only", fake.stopped)
	}
}

func TestShikooCoresStopAGenerationWhoseConfigFails(t *testing.T) {
	fake := useFakeShikooCore(t)
	raw, err := config.UnmarshalRawConfig([]byte(shikooCoresYaml +
		"proxy-groups:\n  - {name: g, type: select, proxies: [missing]}\n"))
	if err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if _, err := shikooCoresParse(raw); err == nil {
		t.Fatal("a group naming a missing proxy parsed")
	}

	if fake.stopped != 1 || len(shikooCoresStarting) != 0 {
		t.Errorf("stopped %d, starting %d; want the started core stopped", fake.stopped, len(shikooCoresStarting))
	}
}

func TestLoadConfigGoesThroughTheShikooCores(t *testing.T) {
	fake := useFakeShikooCore(t)
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte(shikooCoresYaml), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	cfg, err := loadConfig(path)

	if err != nil {
		t.Fatalf("loadConfig = %v", err)
	}
	if len(fake.got) != 1 || cfg.Proxies["a"].Type() != constant.Socks5 {
		t.Errorf("loadConfig skipped the cores: got %v, a is %v", fake.got, cfg.Proxies["a"].Type())
	}
}
