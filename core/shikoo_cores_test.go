package main

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"net"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"syscall"
	"testing"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
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
	rename  bool
	gens    int

	// The address mihomo held for proxy "a" as each generation stopped.
	heldAtStop []string
}

func (f *fakeShikooCore) start(proxies []map[string]any) ([]map[string]any, func(), error) {
	gen := f.gens
	f.gens++
	var names []string
	var out []map[string]any
	for i, proxy := range proxies {
		if _, marked := proxy[shikooCoreKey]; marked {
			return nil, nil, errors.New("the marker reached the core")
		}
		names = append(names, fmt.Sprint(proxy["name"]))
		name := proxy["name"]
		if f.rename {
			name = fmt.Sprint(name, "-moved")
		}
		out = append(out, map[string]any{
			"name": name, "type": "socks5", "server": "127.0.0.1", "port": 20000 + 10*gen + i,
		})
	}
	f.got = append(f.got, names)
	if f.err != nil {
		return nil, nil, f.err
	}
	if f.short {
		out = out[:1]
	}
	return out, func() {
		f.stopped++
		if held := tunnel.Proxies()["a"]; held != nil {
			f.heldAtStop = append(f.heldAtStop, held.Addr())
		}
	}, nil
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
		if proxy, ok := cfg.Proxies[name]; ok {
			types = append(types, proxy.Type())
		} else {
			types = append(types, -1)
		}
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
		{"replacements under other names", func(f *fakeShikooCore) { f.rename = true }, 1},
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

func TestApplyConfigStopsTheOldCoresOnlyOnceMihomoHoldsTheNewConfig(t *testing.T) {
	fake := useFakeShikooCore(t)
	home, previous := t.TempDir(), constant.Path.HomeDir()
	constant.SetHomeDir(home)
	withCurrentConfig(t, nil)
	t.Cleanup(func() {
		constant.SetHomeDir(previous)
		tunnel.UpdateProxies(nil, nil)
	})
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(shikooCoresYaml), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	for range 2 {
		if err := applyConfig(&SetupParams{}); err != nil {
			t.Fatalf("applyConfig = %v", err)
		}
	}

	if len(fake.heldAtStop) != 1 || fake.heldAtStop[0] != "127.0.0.1:20010" {
		t.Errorf("as the first generation stopped mihomo held a at %v, want the second generation (127.0.0.1:20010)",
			fake.heldAtStop)
	}
}

func TestHandleShutdownStopsTheShikooCores(t *testing.T) {
	fake := useFakeShikooCore(t)
	parseShikooCores(t, shikooCoresYaml)
	shikooCoresCommit()
	parseShikooCores(t, shikooCoresYaml)
	withCurrentConfig(t, &config.Config{General: &config.General{}, Controller: &config.Controller{}})
	isInit.Store(true)

	handleShutdown()

	if fake.stopped != 2 || len(shikooCoresRunning)+len(shikooCoresStarting) != 0 {
		t.Errorf("stopped %d of 2 generations; %d running, %d starting left", fake.stopped,
			len(shikooCoresRunning), len(shikooCoresStarting))
	}
}

func TestShikooCoresKeepAServerNamedByABareNumber(t *testing.T) {
	fake := useFakeShikooCore(t)

	cfg := parseShikooCores(t, "proxies:\n  - {name: 7, type: http, server: 1.1.1.1, port: 1, shikoo-core: fake}\n")

	if got := proxyTypes(cfg, "7"); got[0] != constant.Socks5 || fake.stopped != 0 {
		t.Errorf("type %v, stopped %d: a core that keeps the name 7 as YAML read it must still carry the server", got, fake.stopped)
	}
}

// appliedHome writes yaml as the config.yaml applyConfig reads, applies it once, and undoes it all after the test.
func appliedHome(t *testing.T, yaml string) {
	t.Helper()
	home, previous := t.TempDir(), constant.Path.HomeDir()
	constant.SetHomeDir(home)
	withCurrentConfig(t, nil)
	wasInit := isInit.Load()
	isInit.Store(true)
	t.Cleanup(func() {
		constant.SetHomeDir(previous)
		tunnel.UpdateProxies(nil, nil)
		isInit.Store(wasInit)
	})
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(yaml), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := applyConfig(&SetupParams{}); err != nil {
		t.Fatalf("applyConfig = %v", err)
	}
}

// hookSockets stands for the tunnel coming up: from now on every socket mihomo's dialer makes goes through the hook.
func hookSockets(t *testing.T) *atomic.Int32 {
	t.Helper()
	var hooked atomic.Int32
	previous := dialer.DefaultSocketHook
	dialer.DefaultSocketHook = func(string, string, syscall.RawConn) error {
		hooked.Add(1)
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = previous })
	return &hooked
}

func TestOnceTheTunnelIsUpACoreDialsItsServerSocketsAgainThroughTheHook(t *testing.T) {
	server, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	var opened int
	registerShikooCore("sockets", func(proxies []map[string]any) ([]map[string]any, func(), error) {
		conn, err := dialer.DialContext(context.Background(), "udp", server.LocalAddr().String())
		if err != nil {
			return nil, nil, err
		}
		opened++
		var out []map[string]any
		for i, proxy := range proxies {
			out = append(out, map[string]any{
				"name": proxy["name"], "type": "socks5", "server": "127.0.0.1", "port": 21000 + 10*opened + i,
			})
		}
		return out, func() { _ = conn.Close() }, nil
	})
	t.Cleanup(func() {
		delete(shikooCores, "sockets")
		shikooCoresShutdown()
	})
	appliedHome(t, `
proxies:
  - {name: a, type: http, server: 1.1.1.1, port: 1, shikoo-core: sockets}
  - {name: b, type: http, server: 1.1.1.2, port: 1}
proxy-groups:
  - {name: G, type: select, proxies: [a, b]}
`)
	patchSelectGroup(map[string]string{"G": "b"})
	hooked := hookSockets(t)

	shikooCoresAfterTun()

	if opened != 2 || hooked.Load() == 0 {
		t.Errorf("%d generations, %d sockets through the hook: the server socket must be dialed again with the hook on",
			opened, hooked.Load())
	}
	if held := tunnel.Proxies()["a"].Addr(); held != "127.0.0.1:21020" {
		t.Errorf("mihomo holds a at %s, want the new generation (127.0.0.1:21020)", held)
	}
	selector := tunnel.Proxies()["G"].(interface{ Adapter() constant.ProxyAdapter }).Adapter().(*outboundgroup.Selector)
	if now := selector.Now(); now != "b" {
		t.Errorf("the group holds %q after the rebuild, want the pick b", now)
	}
}

func TestWithNoCoreBehindMihomoTheTunnelRebuildsNothing(t *testing.T) {
	appliedHome(t, `
proxies:
  - {name: b, type: http, server: 1.1.1.2, port: 1}
`)
	running := currentConfig

	shikooCoresAfterTun()

	if currentConfig != running {
		t.Error("applied again with only mihomo's own clients, which dial lazily")
	}
}

func useCountingCore(t *testing.T) *int {
	t.Helper()
	generations := 0
	registerShikooCore("counting", func(proxies []map[string]any) ([]map[string]any, func(), error) {
		generations++
		var out []map[string]any
		for i, proxy := range proxies {
			out = append(out, map[string]any{
				"name": proxy["name"], "type": "socks5", "server": "127.0.0.1", "port": 22000 + 10*generations + i,
			})
		}
		return out, func() {}, nil
	})
	t.Cleanup(func() {
		delete(shikooCores, "counting")
		shikooCoresShutdown()
	})
	return &generations
}

func TestTheRebuildKeepsEveryPickTheLastApplyHadAndTheSelectGroupsMadeSince(t *testing.T) {
	useCountingCore(t)
	appliedHome(t, `
proxies:
  - {name: a, type: http, server: 1.1.1.1, port: 1, shikoo-core: counting}
  - {name: b, type: http, server: 1.1.1.2, port: 1}
  - {name: c, type: http, server: 1.1.1.3, port: 1}
proxy-groups:
  - {name: OUT, type: select, proxies: [IN, b]}
  - {name: IN, type: select, proxies: [a, c]}
  - {name: AUTO, type: url-test, proxies: [a, b, c], url: "http://127.0.0.1:1/", interval: 3600, lazy: true}
`)
	if err := applyConfig(&SetupParams{SelectedMap: map[string]string{"OUT": "IN", "AUTO": "b"}}); err != nil {
		t.Fatalf("applyConfig = %v", err)
	}
	patchSelectGroup(map[string]string{"IN": "c"})

	shikooCoresAfterTun()

	got := map[string]string{}
	for _, name := range []string{"OUT", "IN", "AUTO"} {
		got[name] = groupNow(t, tunnel.Proxies()[name])
	}
	if want := map[string]string{"OUT": "IN", "IN": "c", "AUTO": "b"}; !maps.Equal(got, want) {
		t.Errorf("after the rebuild %v, want %v: the url-test pick of the last apply and the select pick since", got, want)
	}
}

func TestTheRebuildRunsWhatGoAppliedNotAConfigFileDartIsWriting(t *testing.T) {
	generations := useCountingCore(t)
	appliedHome(t, `
proxies:
  - {name: a, type: http, server: 1.1.1.1, port: 1, shikoo-core: counting}
  - {name: b, type: http, server: 1.1.1.2, port: 1}
proxy-groups:
  - {name: G, type: select, proxies: [a, b]}
`)
	torn := []byte("proxies:\n  - {name: a, type: http, ser")
	if err := os.WriteFile(filepath.Join(constant.Path.HomeDir(), "config.yaml"), torn, 0o600); err != nil {
		t.Fatal(err)
	}

	shikooCoresAfterTun()

	if _, ok := tunnel.Proxies()["G"]; !ok || *generations != 2 {
		t.Errorf("group G kept: %v, %d generations: the rebuild must run the config Go last applied", ok, *generations)
	}
}

func TestLoopbackPortsAreNeverTheSameTwice(t *testing.T) {
	held, release, err := loopbackPorts(1)
	if err != nil {
		t.Fatal(err)
	}
	release()
	t.Cleanup(func() { forgetPorts(held...) })
	for range 2000 {
		ports, release, err := loopbackPorts(4)
		if err != nil {
			t.Fatal(err)
		}
		release()
		forgetPorts(ports...)
		if len(slices.Compact(slices.Sorted(slices.Values(ports)))) != 4 || slices.Contains(ports, held[0]) {
			t.Fatalf("ports %v: one twice, or the still-taken %d", ports, held[0])
		}
	}
}
