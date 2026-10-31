package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
)

const ownedConfig = `proxies:
  - {name: W, type: wireguard, server: 1.1.1.2, port: 1, shikoo-owner: wireguard}
  - {name: O, type: openvpn, server: 1.1.1.4, port: 1194, shikoo-owner: openvpn}
  - {name: A, type: vless, server: 1.1.1.3, port: 443}
proxy-groups:
  - {name: main, type: select, proxies: [W, O, A]}
rules:
  - MATCH,main
`

// tunHost stands in for the platform's tunnel and for mihomo's own tun, which the rule under test chooses between.
type tunHost struct {
	starts, buildingAtStart []string
	mihomo                  []bool
	live                    string
	fail                    map[string]error
}

func hostTun(t *testing.T, pick *string) *tunHost {
	t.Helper()
	h := &tunHost{fail: map[string]error{}}
	home := constant.Path.HomeDir()
	dir := t.TempDir()
	constant.SetHomeDir(dir)
	if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(ownedConfig), 0o600); err != nil {
		t.Fatal(err)
	}
	start, key, closeTun, mihomo, picks := startOwnerTunnel, ownerTunnelKey, closeOwnerTunnel, mihomoTun, pickOf
	pickOf = func(string) string { return *pick }
	mihomoTun = func(conf LC.Tun) { h.mihomo = append(h.mihomo, conf.Enable) }
	ownerTunnelKey = func() string { return h.live }
	closeOwnerTunnel = func() { h.live = "" }
	startOwnerTunnel = func(_, key, core string, mapping map[string]any, _ bool) error {
		h.buildingAtStart = append(h.buildingAtStart, buildingFor("openvpn")+"/"+buildingFor("wireguard"))
		h.starts = append(h.starts, core+":"+fmt.Sprint(mapping["name"]))
		if err := h.fail[core]; err != nil {
			return err
		}
		h.live = key
		return nil
	}
	t.Cleanup(func() {
		ownerFailed = ""
		startOwnerTunnel, ownerTunnelKey, closeOwnerTunnel, mihomoTun, pickOf = start, key, closeTun, mihomo, picks
		constant.SetHomeDir(home)
	})
	return h
}

var tunOn = LC.Tun{Enable: true, Device: "ShikooNet"}

func TestTheOwnerTunnelStartsForAMarkedPickOfEitherCoreInTunModeOnly(t *testing.T) {
	pick := "O"
	h := hostTun(t, &pick)

	recreateOwnerTun(LC.Tun{Device: "ShikooNet"})
	if len(h.starts) != 0 || !slices.Equal(h.mihomo, []bool{false}) {
		t.Fatalf("proxy mode: starts %v, mihomo's tun %v", h.starts, h.mihomo)
	}
	recreateOwnerTun(tunOn)
	recreateOwnerTun(tunOn)
	if !slices.Equal(h.starts, []string{"openvpn:O"}) || !slices.Equal(h.mihomo, []bool{false, false}) {
		t.Fatalf("starts %v, mihomo's tun %v: want one OpenVPN start, mihomo's tun closed first", h.starts, h.mihomo)
	}
	pick = "W"
	recreateOwnerTun(tunOn)
	if !slices.Equal(h.starts, []string{"openvpn:O", "wireguard:W"}) {
		t.Errorf("starts %v: a WireGuard pick after an OpenVPN one must start WireGuard", h.starts)
	}
	pick = "A"
	recreateOwnerTun(tunOn)
	if h.live != "" || !h.mihomo[len(h.mihomo)-1] {
		t.Errorf("an unmarked pick left %q held, mihomo's tun %v: want it closed and mihomo's tun on", h.live, h.mihomo)
	}
}

func TestAnOpenvpnThatWouldNotStartLeavesNoTunnelAtAllAndAWireguardLeavesMihomos(t *testing.T) {
	pick := "O"
	h := hostTun(t, &pick)
	h.fail["openvpn"] = errors.New("no engine")

	recreateOwnerTun(tunOn)
	recreateOwnerTun(tunOn)
	if !slices.Equal(h.mihomo, []bool{false}) || len(h.starts) != 1 {
		t.Fatalf("mihomo's tun %v, starts %v: OpenVPN has no mihomo to fall back to, and one run asks once", h.mihomo, h.starts)
	}
	ownerFailed = ""
	h.fail["openvpn"] = nil
	recreateOwnerTun(tunOn)
	if len(h.starts) != 2 || h.live == "" {
		t.Errorf("starts %v: the next run must ask for the engine again", h.starts)
	}

	pick = "W"
	h.fail["wireguard"] = errors.New("no engine")
	recreateOwnerTun(tunOn)
	if !h.mihomo[len(h.mihomo)-1] {
		t.Errorf("mihomo's tun %v: a WireGuard that would not start leaves its server on mihomo's tun", h.mihomo)
	}
}

func TestARebuildNamesTheServerBeingBuiltForTheCoreBuildingItOnly(t *testing.T) {
	pick := "W"
	h := hostTun(t, &pick)
	*fakeOwner(t, nil) = "W"

	pick = "O"
	recreateOwnerTun(tunOn)
	if !slices.Equal(h.buildingAtStart, []string{"O/"}) {
		t.Errorf("building %v: between WireGuard and OpenVPN only OpenVPN's answer names the new server", h.buildingAtStart)
	}
	if ownerBuilding.Load() != nil || buildingFor("openvpn") != "" {
		t.Errorf("after the rebuild the core still reports %q building", buildingFor("openvpn"))
	}
}

func TestTheCoreSaysAnOwnerSessionsWordAndOmitsItForOneWithNone(t *testing.T) {
	state := ""
	carrying := ""
	registerShikooOwner("session-test", func() string { return carrying }, nil)
	shikooOwnerStates["session-test"] = func() string { return state }
	t.Cleanup(func() {
		delete(shikooOwners, "session-test")
		delete(shikooOwnerStates, "session-test")
	})

	state = stateConnecting
	if got := shikooOwnerNow(); got != (ShikooOwner{}) {
		t.Errorf("a session still connecting with nothing carried: %+v", got)
	}
	carrying, state = "S", stateUp
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "session-test", Server: "S", State: stateUp}) {
		t.Errorf("carrying: %+v", got)
	}
	for _, word := range []string{stateFailed, stateRefused} {
		carrying, state = "", word
		if got := shikooOwnerNow(); got != (ShikooOwner{Core: "session-test", State: word}) {
			t.Errorf("%s with nothing carried: %+v", word, got)
		}
	}
	plain, _ := json.Marshal(ShikooOwner{Core: "wireguard", Server: "wg"})
	if string(plain) != `{"core":"wireguard","server":"wg"}` {
		t.Errorf("an owner with no session word encodes as %s", plain)
	}
}

func TestOpenvpnsStateWordFollowsItsSessionAndItsFailure(t *testing.T) {
	t.Cleanup(func() { ovpnNow.Store(nil); ovpnEnded.Store(nil) })
	if got := ovpnOwnerState(); got != "" {
		t.Fatalf("idle: %q", got)
	}
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov"})
	if got := ovpnOwnerState(); got != stateConnecting {
		t.Errorf("started: %q", got)
	}
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov", Up: true})
	if got := ovpnOwnerState(); got != stateUp {
		t.Errorf("up: %q", got)
	}
	ovpnEnded.Store(&ovpnOutcome{session: 1, state: stateRefused})
	ovpnState(&ovpnStateParams{Session: 1})
	if got := ovpnOwnerState(); got != stateRefused {
		t.Errorf("ended refused: %q", got)
	}
}

func TestAnOpenvpnProfileCanCarryTheServersAddressForItsName(t *testing.T) {
	plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": "vpn.example.com"}), false)
	if err != nil || !strings.Contains(plan.Profile, "remote vpn.example.com 1194\n") {
		t.Fatalf("profile %q, %v", plan.Profile, err)
	}
	pinned := ovpnPinned(ovpnPrepared.Load().config, netip.MustParseAddr("198.51.100.7"))
	want := strings.Replace(plan.Profile, "remote vpn.example.com 1194", "remote 198.51.100.7 1194", 1)
	if pinned != want {
		t.Errorf("pinned %q, want the same profile with only the remote changed", pinned)
	}
}
