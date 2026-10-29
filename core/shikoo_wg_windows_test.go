//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	singtun "github.com/metacubex/sing-tun"
	"golang.zx2c4.com/wireguard/conn/bindtest"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/tuntest"
)

func TestWindowsReportsWhatTheOfficialEngineCarries(t *testing.T) {
	owner, ok := shikooOwners["wireguard"]
	if !ok || owner.ping == nil {
		t.Fatal("the official engine is not registered with its own ping")
	}
	if got := owner.carrying(); got != "" {
		t.Errorf("an engine that never started carries %q", got)
	}
	ownerRunning.Store(&wgOwner{server: "wg"})
	t.Cleanup(func() { ownerRunning.Store(nil) })
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "wireguard", Server: "wg"}) {
		t.Errorf("the core reports %+v, want wireguard carrying wg", got)
	}
	if delay := owner.ping(&TestDelayParams{ProxyName: "other"}); delay.Value != -1 {
		t.Errorf("a server the engine does not carry got %d, want -1 at once", delay.Value)
	}
}

// The engine's start holds configMu for seconds (the endpoint's DNS, wintun, routes); the app waits 2 s at most.
func TestTheCoreSaysWhatTheEngineCarriesWhileTheTunnelIsBeingBuilt(t *testing.T) {
	ownerRunning.Store(&wgOwner{server: "wg"})
	t.Cleanup(func() { ownerRunning.Store(nil) })
	fake := &fakeConn{}
	defer swapConn(swapConn(fake))
	configMu.Lock()
	defer configMu.Unlock()
	answered := make(chan struct{})
	go func() {
		methodHandlers[shikooOwnerMethod](&MethodCall{ID: "1", Method: shikooOwnerMethod}, MethodResponse{ID: "1"})
		close(answered)
	}()
	select {
	case <-answered:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("no answer within 200 ms while configMu is held")
	}
	var answer struct{ Result ShikooOwner }
	frames := fake.frames(t)
	if len(frames) != 1 || json.Unmarshal(frames[0], &answer) != nil ||
		answer.Result != (ShikooOwner{Core: "wireguard", Server: "wg"}) {
		t.Errorf("answer %q", frames)
	}
}

type tunWiring struct {
	starts, carryingAtStart []string
	mihomo                  []bool
	fail                    bool
}

const wiredConfig = `proxies:
  - {name: W, type: wireguard, server: 1.1.1.2, port: 1, shikoo-owner: wireguard}
  - {name: A, type: vless, server: 1.1.1.3, port: 443}
proxy-groups:
  - {name: main, type: select, proxies: [W, A]}
rules:
`

// wireTun stands in for wintun and mihomo's tun; the engine runs on an in-memory tun and bind, which open no socket.
func wireTun(t *testing.T, pick *string) (*tunWiring, func(rules string)) {
	t.Helper()
	w := &tunWiring{}
	home := constant.Path.HomeDir()
	dir := t.TempDir()
	constant.SetHomeDir(dir)
	write := func(rules string) {
		if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(wiredConfig+rules), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("  - MATCH,main\n")
	start, mihomo, picks := startOwnerTunnel, mihomoTun, pickOf
	pickOf = func(string) string { return *pick }
	mihomoTun = func(conf LC.Tun) { w.mihomo = append(w.mihomo, conf.Enable) }
	startOwnerTunnel = func(_, key string, mapping map[string]any, _ bool) error {
		w.carryingAtStart = append(w.carryingAtStart, windowsCarrying())
		if w.fail {
			return errors.New("no engine")
		}
		dev := device.NewDevice(tuntest.NewChannelTUN().TUN(), bindtest.NewChannelBinds()[0],
			device.NewLogger(device.LogLevelSilent, ""))
		ownerRunning.Store(&wgOwner{server: fmt.Sprint(mapping["name"]), dev: dev})
		ownerTun = &ownerTunnel{key: key}
		w.starts = append(w.starts, key)
		return nil
	}
	t.Cleanup(func() {
		stopOwnerTun()
		startOwnerTunnel, mihomoTun, pickOf = start, mihomo, picks
		constant.SetHomeDir(home)
	})
	return w, write
}

func TestWindowsTunnelGoesToTheEngineOnlyForAMarkedPickInTunMode(t *testing.T) {
	pick := "W"
	w, _ := wireTun(t, &pick)
	on := LC.Tun{Enable: true, Device: "ShikooNet"}

	reCreateTun(LC.Tun{Device: "ShikooNet"})
	if len(w.starts) != 0 || !slices.Equal(w.mihomo, []bool{false}) {
		t.Fatalf("proxy mode: starts %v, mihomo's tun %v", w.starts, w.mihomo)
	}
	reCreateTun(on)
	reCreateTun(on)
	if len(w.starts) != 1 || ownerServer() != "W" || !slices.Equal(w.mihomo, []bool{false, false}) {
		t.Fatalf("starts %v, carrying %q, mihomo's tun %v: want one start, mihomo's tun closed first",
			w.starts, ownerServer(), w.mihomo)
	}
	if w.carryingAtStart[0] != "" {
		t.Errorf("a first start reported %q before the engine ran", w.carryingAtStart[0])
	}
	pick = "A"
	reCreateTun(on)
	if ownerServer() != "" || !w.mihomo[len(w.mihomo)-1] {
		t.Errorf("an unmarked pick left the engine carrying %q, mihomo's tun %v", ownerServer(), w.mihomo)
	}
}

func TestGoRebuildingTheEngineForANewKeyIsNoDeathToTheAppsWatch(t *testing.T) {
	pick := "W"
	w, write := wireTun(t, &pick)
	on := LC.Tun{Enable: true, Device: "ShikooNet"}
	reCreateTun(on)

	write("  - RULE-SET,shikoo-ir-ip,DIRECT,no-resolve\n  - MATCH,main\n")
	reCreateTun(on)
	if len(w.starts) != 2 || w.starts[0] == w.starts[1] {
		t.Fatalf("starts %v: the Iranian switch must rebuild the engine", w.starts)
	}
	if w.carryingAtStart[1] != "W" {
		t.Errorf("between the old engine and the new one Go reported %q, which the watch reads as a death",
			w.carryingAtStart[1])
	}
	if ownerBuilding.Load() != nil || windowsCarrying() != "W" {
		t.Errorf("after the rebuild Go reports %q", windowsCarrying())
	}
}

func TestARebuildThatFailsStopsReportingTheServer(t *testing.T) {
	pick := "W"
	w, write := wireTun(t, &pick)
	on := LC.Tun{Enable: true, Device: "ShikooNet"}
	reCreateTun(on)
	w.fail = true

	write("  - RULE-SET,shikoo-ir-ip,DIRECT,no-resolve\n  - MATCH,main\n")
	reCreateTun(on)
	if got := windowsCarrying(); got != "" {
		t.Errorf("after a failed rebuild Go still reports %q while mihomo carries the server", got)
	}
}

func TestAWindowsEngineThatWouldNotStartLeavesTheServerOnMihomosTunUntilTheNextRun(t *testing.T) {
	pick := "W"
	w, _ := wireTun(t, &pick)
	on := LC.Tun{Enable: true, Device: "ShikooNet"}
	w.fail = true

	reCreateTun(on)
	if windowsCarrying() != "" || !slices.Equal(w.mihomo, []bool{false, true}) {
		t.Fatalf("carrying %q, mihomo's tun %v: want mihomo's tun back on", windowsCarrying(), w.mihomo)
	}
	reCreateTun(on)
	if len(w.carryingAtStart) != 1 {
		t.Errorf("%d starts: an apply in the same run tried the engine again", len(w.carryingAtStart))
	}
	stopOwnerTun()
	w.fail = false
	reCreateTun(on)
	if len(w.starts) != 1 || ownerServer() != "W" {
		t.Errorf("starts %v: the next run must ask for the engine again", w.starts)
	}
}

func TestAWindowsTunnelWithoutIPv6TakesIPv6InWithNoIPv6DNS(t *testing.T) {
	v4, _, err := wgPlan(wgMapping(t, map[string]any{"dns": []string{"1.1.1.1", "2606:4700:4700::1111"}}),
		nil, windowsSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	options := wintunOptions("ShikooNet", v4)
	if len(options.Inet6Address) != 1 || singtun.HasNextAddress(options.Inet6Address[0], 1) ||
		!slices.Equal(options.Inet6RouteAddress, []netip.Prefix{netip.MustParsePrefix("::/0")}) {
		t.Errorf("IPv6 address %v, routes %v: IPv6 must come into the tunnel with no address sing-tun makes a DNS of",
			options.Inet6Address, options.Inet6RouteAddress)
	}
	if slices.ContainsFunc(options.DNSServers, netip.Addr.Is6) {
		t.Errorf("DNS %v: an IPv6 server the tunnel cannot reach", options.DNSServers)
	}

	dual, _, err := wgPlan(wgMapping(t, map[string]any{"ipv6": "fd00::2"}), nil, windowsSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	options = wintunOptions("ShikooNet", dual)
	if !slices.Equal(options.Inet6Address, []netip.Prefix{netip.MustParsePrefix("fd00::2/128")}) ||
		!slices.Contains(options.Inet6RouteAddress, netip.MustParsePrefix("::/0")) {
		t.Errorf("a tunnel with its own IPv6 got %v, routes %v", options.Inet6Address, options.Inet6RouteAddress)
	}
}

func TestAWindowsTunnelWithoutIPv4TakesIPv4InWithNoIPv4DNS(t *testing.T) {
	v6, _, err := wgPlan(wgMapping(t, map[string]any{"ip": nil, "ipv6": "fd00::2"}), nil, windowsSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	options := wintunOptions("ShikooNet", v6)
	if len(options.Inet4Address) != 1 || singtun.HasNextAddress(options.Inet4Address[0], 1) ||
		!slices.Equal(options.Inet4RouteAddress, []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0")}) {
		t.Errorf("IPv4 address %v, routes %v: IPv4 must come into the tunnel with no address sing-tun makes a DNS of",
			options.Inet4Address, options.Inet4RouteAddress)
	}
	if slices.ContainsFunc(options.DNSServers, netip.Addr.Is4) {
		t.Errorf("DNS %v: an IPv4 server the tunnel cannot reach", options.DNSServers)
	}
}
