package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"maps"
	"net/netip"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go4.org/netipx"
	wgconn "golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
	"golang.zx2c4.com/wireguard/tun/tuntest"
)

func wgKeyPair(t *testing.T) (private, public []byte) {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return key.Bytes(), key.PublicKey().Bytes()
}

func wgMapping(t *testing.T, set map[string]any) map[string]any {
	t.Helper()
	private, _ := wgKeyPair(t)
	_, server := wgKeyPair(t)
	mapping := map[string]any{
		"name":        "wg",
		"type":        "wireguard",
		"server":      "203.0.113.7",
		"port":        51820,
		"ip":          "10.13.13.2",
		"private-key": b64(private),
		"public-key":  b64(server),
	}
	for key, value := range set {
		mapping[key] = value
	}
	return mapping
}

func noResolve(host string) (netip.Addr, error) { return netip.ParseAddr(host) }

func uapiLines(prepared *wgPrepared) []string { return strings.Split(prepared.uapi, "\n") }

func TestWireGuardPlanFillsWhatTheMappingLeavesOutLikeTheOfficialApp(t *testing.T) {
	mapping := wgMapping(t, nil)
	plan, prepared, err := wgPlan(mapping, nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	want := &ownerPlan{
		Addresses: []string{"10.13.13.2/32"},
		DNS:       []string{"1.1.1.1", "8.8.8.8"},
		MTU:       1280,
		Routes:    []string{"0.0.0.0/0"},
		Excluded:  []string{},
	}
	if got, _ := json.Marshal(plan); string(got) != string(must(json.Marshal(want))) {
		t.Fatalf("plan = %s, want %s", got, must(json.Marshal(want)))
	}
	lines := uapiLines(prepared)
	for _, line := range []string{
		"endpoint=203.0.113.7:51820",
		"persistent_keepalive_interval=100",
		"allowed_ip=0.0.0.0/0",
		"public_key=" + hex.EncodeToString(must(base64.StdEncoding.DecodeString(mapping["public-key"].(string)))),
	} {
		if !slices.Contains(lines, line) {
			t.Errorf("uapi lacks %q:\n%s", line, prepared.uapi)
		}
	}
	if prepared.server != "wg" {
		t.Errorf("server = %q", prepared.server)
	}
}

func TestWireGuardPlanKeepsWhatTheMappingSays(t *testing.T) {
	plan, prepared, err := wgPlan(wgMapping(t, map[string]any{
		"mtu":                  1420,
		"persistent-keepalive": 0,
		"dns":                  []any{"9.9.9.9", "https://1.1.1.1/dns-query"},
		"ipv6":                 "fd00::2",
	}), nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	if plan.MTU != 1420 || !slices.Equal(plan.DNS, []string{"9.9.9.9"}) {
		t.Errorf("mtu %d dns %v", plan.MTU, plan.DNS)
	}
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0", "::/0"}) ||
		!slices.Equal(plan.Addresses, []string{"10.13.13.2/32", "fd00::2/128"}) {
		t.Errorf("routes %v addresses %v", plan.Routes, plan.Addresses)
	}
	if !slices.Contains(uapiLines(prepared), "persistent_keepalive_interval=0") {
		t.Errorf("the panel's 0 was replaced:\n%s", prepared.uapi)
	}
}

func TestWireGuardPlanResolvesTheEndpointBeforeTheTunnel(t *testing.T) {
	_, prepared, err := wgPlan(wgMapping(t, map[string]any{"server": "wg.example"}), nil, 35,
		func(host string) (netip.Addr, error) {
			if host != "wg.example" {
				t.Errorf("resolved %q", host)
			}
			return netip.MustParseAddr("198.51.100.4"), nil
		})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(uapiLines(prepared), "endpoint=198.51.100.4:51820") {
		t.Errorf("uapi:\n%s", prepared.uapi)
	}
}

func TestWireGuardPlanRefusesWhatTheOfficialEngineCannotCarry(t *testing.T) {
	for name, set := range map[string]map[string]any{
		"vless":    {"type": "vless"},
		"amnezia":  {"amnezia-wg-option": map[string]any{"jc": 4}},
		"reserved": {"reserved": []any{1, 2, 3}},
		"bad key":  {"private-key": "c2hvcnQ="},
		"no ip":    {"ip": ""},
	} {
		if _, _, err := wgPlan(wgMapping(t, set), nil, 35, noResolve); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
}

func testIran(t *testing.T) *netipx.IPSet {
	t.Helper()
	var b netipx.IPSetBuilder
	b.AddPrefix(netip.MustParsePrefix("2.144.0.0/14"))
	b.AddPrefix(netip.MustParsePrefix("5.22.0.0/17"))
	b.AddPrefix(netip.MustParsePrefix("2a01:5ec0::/29"))
	set, err := b.IPSet()
	if err != nil {
		t.Fatal(err)
	}
	return set
}

func TestIranianRangesAreExcludedRoutesFromAndroid13(t *testing.T) {
	plan, _, err := wgPlan(wgMapping(t, nil), testIran(t), excludeRouteSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0"}) {
		t.Errorf("routes %v", plan.Routes)
	}
	// The IPv6 range stays out: this tunnel has no IPv6 route to cut it from.
	if !slices.Equal(plan.Excluded, []string{"2.144.0.0/14", "5.22.0.0/17"}) {
		t.Errorf("excluded %v", plan.Excluded)
	}
}

func TestIranianRangesAreCutOutOfTheRoutesBelowAndroid13(t *testing.T) {
	plan, _, err := wgPlan(wgMapping(t, nil), testIran(t), excludeRouteSdk-1, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Excluded) != 0 {
		t.Errorf("excluded %v", plan.Excluded)
	}
	var b netipx.IPSetBuilder
	for _, route := range plan.Routes {
		b.AddPrefix(netip.MustParsePrefix(route))
	}
	routes := must(b.IPSet())
	for ip, inside := range map[string]bool{"2.146.1.1": false, "5.22.100.1": false, "5.22.200.1": true, "1.1.1.1": true} {
		if routes.Contains(netip.MustParseAddr(ip)) != inside {
			t.Errorf("%s in the tunnel = %v, want %v", ip, !inside, inside)
		}
	}
}

func TestTheShippedIranianSetGivesARouteListAndroidTakes(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for ip, inside := range map[string]bool{"2.144.0.1": true, "5.160.0.1": true, "1.1.1.1": false, "8.8.8.8": false} {
		if iran.Contains(netip.MustParseAddr(ip)) != inside {
			t.Errorf("%s Iranian = %v", ip, !inside)
		}
	}
	all := float64(addresses(iran.Prefixes()))
	from13, _, _ := wgPlan(wgMapping(t, nil), iran, excludeRouteSdk, noResolve)
	if n := len(from13.Routes) + len(from13.Excluded); n > wgExcludedBudget || n < wgExcludedBudget/2 {
		t.Errorf("Android 13+: %d routes", n)
	}
	excluded := addresses(parsePrefixes(from13.Excluded))
	below13, _, _ := wgPlan(wgMapping(t, nil), iran, excludeRouteSdk-1, noResolve)
	if n := len(below13.Routes); n > wgRoutesBudget || n <= wgExcludedBudget {
		t.Errorf("below 13: %d routes", n)
	}
	around := addresses([]netip.Prefix{netip.MustParsePrefix("0.0.0.0/0")}) - addresses(parsePrefixes(below13.Routes))
	t.Logf("Android 13+: %d excluded, %.0f%% of Iran's addresses; below 13: %d routes, %.0f%%",
		len(from13.Excluded), 100*float64(excluded)/all, len(below13.Routes), 100*float64(around)/all)
	for _, plan := range []*ownerPlan{from13, below13} {
		var b netipx.IPSetBuilder
		for _, route := range plan.Routes {
			b.AddPrefix(netip.MustParsePrefix(route))
		}
		for _, route := range plan.Excluded {
			b.RemovePrefix(netip.MustParsePrefix(route))
		}
		tunnel := must(b.IPSet())
		if tunnel.Contains(netip.MustParseAddr("2.144.0.1")) || !tunnel.Contains(netip.MustParseAddr("1.1.1.1")) {
			t.Error("a wide Iranian block rides the tunnel, or a foreign one does not")
		}
	}
}

func TestTheSitesBlocksAreAllInTheShippedIranianSet(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range iranFirst {
		if !iran.ContainsPrefix(p) {
			t.Errorf("%s left the shipped Iranian set: its site would ride the server again", p)
		}
	}
}

func TestTheSitesBlocksGoOutFirstWithinTheRouteBudget(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for _, sdk := range []int{excludeRouteSdk, excludeRouteSdk - 1, windowsSdk} {
		plan, _, err := wgPlan(wgMapping(t, nil), iran, sdk, noResolve)
		if err != nil {
			t.Fatal(err)
		}
		if n := len(plan.Routes) + len(plan.Excluded); n > budgetFor(sdk) {
			t.Errorf("sdk %d: %d routes", sdk, n)
		}
		var b netipx.IPSetBuilder
		for _, route := range plan.Routes {
			b.AddPrefix(netip.MustParsePrefix(route))
		}
		for _, route := range plan.Excluded {
			b.RemovePrefix(netip.MustParsePrefix(route))
		}
		tunnel := must(b.IPSet())
		for _, p := range iranFirst {
			if tunnel.OverlapsPrefix(p) {
				t.Errorf("sdk %d: %s still rides the tunnel", sdk, p)
			}
		}
	}
}

// Shecan's answers of 2026-10-23: every Shaparak gateway that resolved, then Sadad, Behpardakht and key sites.
func TestThePaymentGatewaysAndKeyAppsLeaveTheTunnel(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for _, sdk := range []int{excludeRouteSdk, excludeRouteSdk - 1, windowsSdk} {
		plan, _, err := wgPlan(wgMapping(t, nil), iran, sdk, noResolve)
		if err != nil {
			t.Fatal(err)
		}
		var b netipx.IPSetBuilder
		for _, route := range plan.Routes {
			b.AddPrefix(netip.MustParsePrefix(route))
		}
		for _, route := range plan.Excluded {
			b.RemovePrefix(netip.MustParsePrefix(route))
		}
		tunnel := must(b.IPSet())
		for _, ip := range []string{"185.167.73.34", "91.240.182.20", "212.80.25.62", "185.132.124.159", "185.79.62.3",
			"91.232.66.12", "185.210.200.12", "185.203.160.31", "87.107.134.3", "78.157.33.101", "185.60.32.60",
			"193.3.31.85", "185.25.172.22", "185.203.160.10", "185.132.124.157", "92.42.50.130", "45.89.201.10",
			"185.120.222.22", "46.102.128.10", "195.225.232.37", "212.16.67.13", "91.207.138.45", "185.231.114.218",
			"45.157.244.26", "185.78.23.170"} {
			if tunnel.Contains(netip.MustParseAddr(ip)) {
				t.Errorf("sdk %d: %s rides the tunnel", sdk, ip)
			}
		}
	}
}

func TestASitesBlockOutsideTheIranianSetStaysInTheTunnel(t *testing.T) {
	var b netipx.IPSetBuilder
	b.AddPrefix(netip.MustParsePrefix("2.144.0.0/14"))
	b.AddPrefix(netip.MustParsePrefix("185.143.232.0/23"))
	iran := must(b.IPSet())
	plan, _, err := wgPlan(wgMapping(t, nil), iran, excludeRouteSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(plan.Excluded, []string{"2.144.0.0/14", "185.143.232.0/23"}) {
		t.Errorf("excluded %v: only what the Iranian set holds may leave the tunnel", plan.Excluded)
	}
}

func TestTheWidestIranianBlocksGoFirstWithinTheRouteBudget(t *testing.T) {
	var b netipx.IPSetBuilder
	b.AddPrefix(netip.MustParsePrefix("2.176.0.0/12"))
	for i := range 600 {
		b.AddPrefix(netip.PrefixFrom(netip.AddrFrom4([4]byte{185, byte(i / 256), byte(i % 256), 0}), 24))
	}
	iran := must(b.IPSet())
	for _, sdk := range []int{excludeRouteSdk, excludeRouteSdk - 1, windowsSdk} {
		plan, _, err := wgPlan(wgMapping(t, nil), iran, sdk, noResolve)
		if err != nil {
			t.Fatal(err)
		}
		if n := len(plan.Routes) + len(plan.Excluded); n > budgetFor(sdk) {
			t.Errorf("sdk %d: %d routes", sdk, n)
		}
		if sdk >= excludeRouteSdk && !slices.Contains(plan.Excluded, "2.176.0.0/12") {
			t.Errorf("sdk %d: the /12 is not out: %v", sdk, plan.Excluded[:3])
		}
		if sdk < excludeRouteSdk && slices.ContainsFunc(plan.Routes, func(r string) bool {
			return netip.MustParsePrefix(r).Contains(netip.MustParseAddr("2.176.0.1"))
		}) {
			t.Errorf("sdk %d: the /12 is still routed", sdk)
		}
	}
}

func budgetFor(sdk int) int {
	if sdk >= excludeRouteSdk {
		return wgExcludedBudget
	}
	return wgRoutesBudget
}

func TestTheRouteBudgetChangesAtAndroid13(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for sdk, budget := range map[int]int{32: wgRoutesBudget, 33: wgExcludedBudget} {
		plan, _, err := wgPlan(wgMapping(t, nil), iran, sdk, noResolve)
		if err != nil {
			t.Fatal(err)
		}
		// Filled to the cap: a whole tier that did not fit left a quarter of it unused.
		n := len(plan.Routes) + len(plan.Excluded)
		if n > budget || n < budget-32 || sdk >= excludeRouteSdk && n != budget {
			t.Errorf("sdk %d: %d routes, want the budget of %d filled", sdk, n, budget)
		}
	}
}

func TestAnIPv6AddressKeepsIranianIPv4OutOfTheTunnel(t *testing.T) {
	iran, err := readIPSet("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	for _, sdk := range []int{excludeRouteSdk, excludeRouteSdk - 1, windowsSdk} {
		without := iranianIPv4Out(t, wgMapping(t, nil), iran, sdk)
		with := iranianIPv4Out(t, wgMapping(t, map[string]any{"ipv6": "fd00::2"}), iran, sdk)
		if with < without*98/100 {
			t.Errorf("sdk %d: with IPv6 %d of Iran's IPv4 addresses leave the tunnel, without %d", sdk, with, without)
		}
	}
}

func iranianIPv4Out(t *testing.T, mapping map[string]any, iran *netipx.IPSet, sdk int) uint64 {
	t.Helper()
	plan, _, err := wgPlan(mapping, iran, sdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	var b netipx.IPSetBuilder
	if sdk >= excludeRouteSdk {
		for _, e := range plan.Excluded {
			b.AddPrefix(netip.MustParsePrefix(e))
		}
	} else {
		b.AddPrefix(netip.MustParsePrefix("0.0.0.0/0"))
		for _, r := range plan.Routes {
			b.RemovePrefix(netip.MustParsePrefix(r))
		}
	}
	return addresses(must(b.IPSet()).Prefixes())
}

func TestOnePeerTakesEveryFamilyWhateverAllowedIPsSays(t *testing.T) {
	_, prepared, err := wgPlan(wgMapping(t, map[string]any{"allowed-ips": []any{"10.0.0.0/8"}}), nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	lines := uapiLines(prepared)
	if !slices.Contains(lines, "allowed_ip=0.0.0.0/0") || slices.Contains(lines, "allowed_ip=10.0.0.0/8") {
		t.Errorf("the peer's allowed IPs:\n%s", prepared.uapi)
	}
}

// The literal Kotlin's Core.prepareOwner sends; VpnOptionsTest pins the same key on its side.
func TestPrepareOwnerReadsTheKeysKotlinSends(t *testing.T) {
	var params PrepareOwnerParams
	if err := json.Unmarshal([]byte(`{"core":"wireguard","server":"Germany 5","iran-direct":true}`), &params); err != nil ||
		params != (PrepareOwnerParams{Core: "wireguard", Server: "Germany 5", IranDirect: true}) {
		t.Errorf("read %+v (%v)", params, err)
	}
}

func TestAnEngineWhoseDeviceClosedCarriesNothing(t *testing.T) {
	startTestOwner(t)
	ownerRunning.Load().dev.Close()
	for deadline := time.Now().Add(2 * time.Second); ownerServer() != ""; time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("a dead engine still says it carries its server")
		}
	}
}

func parsePrefixes(values []string) []netip.Prefix {
	out := make([]netip.Prefix, len(values))
	for i, value := range values {
		out[i] = netip.MustParsePrefix(value)
	}
	return out
}

func addresses(prefixes []netip.Prefix) uint64 {
	var n uint64
	for _, p := range prefixes {
		if p.Addr().Is4() {
			n += 1 << (32 - p.Bits())
		}
	}
	return n
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

// wgServer is a WireGuard peer on loopback with an in-memory tun, standing in for the panel's server.
func wgServer(t *testing.T, client []byte) (*device.Device, *tuntest.ChannelTUN, []byte, int) {
	t.Helper()
	private, public := wgKeyPair(t)
	channel := tuntest.NewChannelTUN()
	dev := device.NewDevice(channel.TUN(), wgconn.NewDefaultBind(), device.NewLogger(device.LogLevelError, "server: "))
	uapi := "private_key=" + hex.EncodeToString(private) + "\nlisten_port=0\npublic_key=" + hex.EncodeToString(client) +
		"\nallowed_ip=10.13.13.2/32\n"
	if err := dev.IpcSet(uapi); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}
	state := must(dev.IpcGet())
	_, after, _ := strings.Cut(state, "listen_port=")
	port, _ := strconv.Atoi(strings.SplitN(after, "\n", 2)[0])
	return dev, channel, public, port
}

func startTestOwner(t *testing.T, set ...map[string]any) (*device.Device, *tuntest.ChannelTUN, *tuntest.ChannelTUN) {
	t.Helper()
	clientTun := tuntest.NewChannelTUN()
	server, serverTun := startTestOwnerOn(t, clientTun.TUN(), set...)
	return server, serverTun, clientTun
}

func startTestOwnerOn(t *testing.T, client tun.Device, set ...map[string]any) (*device.Device, *tuntest.ChannelTUN) {
	t.Helper()
	private, public := wgKeyPair(t)
	server, serverTun, serverPublic, port := wgServer(t, public)
	t.Cleanup(server.Close)
	mapping := map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": port, "ip": "10.13.13.2",
		"private-key": b64(private), "public-key": b64(serverPublic),
	}
	for _, more := range set {
		maps.Copy(mapping, more)
	}
	_, prepared, err := wgPlan(mapping, nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	ownerMu.Lock()
	ownerPrepared = prepared
	ownerMu.Unlock()
	if err := startOwner(client, wgconn.NewDefaultBind()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(stopOwner)
	return server, serverTun
}

func TestTheOwnerAnswersItsServersPingWithAHandshake(t *testing.T) {
	server, _, _ := startTestOwner(t)
	registerOwner("wireguard-test")
	t.Cleanup(func() { delete(shikooOwners, "wireguard-test") })
	if delay := ownerPing(&TestDelayParams{ProxyName: "wg", Timeout: 3000}); delay.Value <= 0 || delay.Name != "wg" {
		t.Fatalf("answer %+v, want a delay for wg", delay)
	}

	carried := func() string { return shikooOwnerNow().Server }
	if got := carried(); got != "wg" {
		t.Errorf("Dart's question got %q, want the owner's server", got)
	}
	// At once: a handshake for it would answer late, or at once from the engine's own fresh handshake.
	asked := time.Now()
	if delay := ownerPing(&TestDelayParams{ProxyName: "other", Timeout: 3000}); delay.Value != -1 || time.Since(asked) > time.Second {
		t.Errorf("the owner answered %d after %v for a server it does not hold", delay.Value, time.Since(asked))
	}
	server.Close()
	ownerRunning.Load().asked.Store(time.Now().Add(-device.RekeyTimeout).UnixNano())
	if delay := ownerPing(&TestDelayParams{ProxyName: "wg", Timeout: 300}); delay.Value != -1 {
		t.Errorf("a server that is gone answered %d", delay.Value)
	}
	stopOwner()
	if got := carried(); got != "" {
		t.Errorf("with no owner Dart's question got %q", got)
	}
	if delay := ownerPing(&TestDelayParams{ProxyName: "wg", Timeout: 300}); delay.Value != -1 {
		t.Errorf("a stopped owner answered %d", delay.Value)
	}
}

// The app's first check comes seconds after connect, inside wireguard-go's 5 s without a new initiation.
func TestAPingRightAfterTheEnginesHandshakeTimesThatHandshake(t *testing.T) {
	startTestOwner(t)
	owner := ownerRunning.Load()
	for deadline := time.Now().Add(3 * time.Second); owner.lastHandshake().IsZero(); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the engine never shook hands")
		}
	}
	took := owner.lastHandshake().Sub(time.Unix(0, owner.asked.Load()))
	asked := time.Now()
	delay := owner.testDelay(&TestDelayParams{ProxyName: "wg", Timeout: 3000})
	if delay.Value <= 0 || int64(delay.Value) != max(took.Milliseconds(), 1) || time.Since(asked) > time.Second {
		t.Errorf("answered %d after %v, want the engine's own handshake (%v) at once", delay.Value, time.Since(asked), took)
	}
}

func TestUpSendsNoInitiationBeforeTheEnginesOwn(t *testing.T) {
	private, public := wgKeyPair(t)
	server, _, serverPublic, port := wgServer(t, public)
	t.Cleanup(server.Close)
	_, prepared, err := wgPlan(map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": port, "ip": "10.13.13.2",
		"private-key": b64(private), "public-key": b64(serverPublic), "persistent-keepalive": 25,
	}, nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	dev, err := upWithoutKeepalive(tuntest.NewChannelTUN().TUN(), wgconn.NewDefaultBind(), prepared)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(dev.Close)
	time.Sleep(300 * time.Millisecond)
	if at := (&wgOwner{dev: dev}).lastHandshake(); !at.IsZero() {
		t.Errorf("Up shook hands at %v, before the engine could stamp its own ask", at)
	}
}

// Windows' adapter never sends EventUp, so only the engine's own Up brings the device up there.
func TestUpOnWindowsWintunSendsNoInitiationBeforeTheEnginesOwn(t *testing.T) {
	private, public := wgKeyPair(t)
	server, _, serverPublic, port := wgServer(t, public)
	t.Cleanup(server.Close)
	_, prepared, err := wgPlan(map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": port, "ip": "10.13.13.2",
		"private-key": b64(private), "public-key": b64(serverPublic), "persistent-keepalive": 25,
	}, nil, windowsSdk, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	dev, err := upWithoutKeepalive(newWinTun(newFakeWintun(), "ShikooNet", 1280), wgconn.NewDefaultBind(), prepared)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(dev.Close)
	time.Sleep(300 * time.Millisecond)
	if at := (&wgOwner{dev: dev}).lastHandshake(); !at.IsZero() {
		t.Errorf("Up shook hands at %v, before the engine could stamp its own ask", at)
	}
}

func TestTheEngineShakesHandsAtStartWithoutAKeepalive(t *testing.T) {
	startTestOwner(t, map[string]any{"persistent-keepalive": 0})
	owner := ownerRunning.Load()
	for deadline := time.Now().Add(3 * time.Second); owner.lastHandshake().IsZero(); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("no handshake at start: the first ping would wait for one that never leaves")
		}
	}
}

// A rekey or a retry of wireguard-go's own, with the engine's last ask older than RekeyTimeout.
func TestAPingRightAfterWireGuardsOwnInitiationWaitsItOut(t *testing.T) {
	startTestOwner(t)
	owner := ownerRunning.Load()
	for deadline := time.Now().Add(3 * time.Second); owner.lastHandshake().IsZero(); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the engine never shook hands")
		}
	}
	owner.asked.Store(time.Now().Add(-device.RekeyTimeout).UnixNano())
	if delay := owner.testDelay(&TestDelayParams{ProxyName: "wg", Timeout: 8000}); delay.Value <= 0 {
		t.Errorf("a healthy server answered %d", delay.Value)
	}
}

func TestTheOwnerCarriesPacketsAndCountsThem(t *testing.T) {
	_, serverTun, clientTun := startTestOwner(t)
	up, down := statistic.DefaultManager.Total()
	out := tuntest.Ping(netip.MustParseAddr("10.13.13.1"), netip.MustParseAddr("10.13.13.2"))
	clientTun.Outbound <- out
	select {
	case got := <-serverTun.Inbound:
		if string(got) != string(out) {
			t.Fatal("the server got another packet")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no packet reached the server")
	}
	back := tuntest.Ping(netip.MustParseAddr("10.13.13.2"), netip.MustParseAddr("10.13.13.1"))
	serverTun.Outbound <- back
	select {
	case <-clientTun.Inbound:
	case <-time.After(5 * time.Second):
		t.Fatal("no packet came back")
	}
	upNow, downNow := statistic.DefaultManager.Total()
	if upNow-up < int64(len(out)) || downNow-down < int64(len(back)) {
		t.Errorf("counted up %d down %d, want at least %d and %d", upNow-up, downNow-down, len(out), len(back))
	}
}

// handleStartOwner stops the last tunnel between the plan and the start.
func TestStopTunStopsTheOwnerButKeepsTheNextPlan(t *testing.T) {
	startTestOwner(t)
	next := &wgPrepared{server: "next"}
	ownerMu.Lock()
	ownerPrepared = next
	ownerMu.Unlock()
	stopOwner()
	if ownerServer() != "" || ownerPrepared != next {
		t.Error("the stop took the owner's place wrong")
	}
	ownerMu.Lock()
	ownerPrepared = nil
	ownerMu.Unlock()
	if err := startOwner(tuntest.NewChannelTUN().TUN(), wgconn.NewDefaultBind()); err == nil {
		t.Error("started with nothing prepared")
	}
}

type closeSpy struct {
	C.Proxy
	carryingAtClose *[]string
}

func (spy closeSpy) Close() error {
	*spy.carryingAtClose = append(*spy.carryingAtClose, ownerServer())
	return nil
}

// Once carrying, so the gate already refuses that client when its earlier session is closed.
func TestStartingTheOwnerClosesMihomosEarlierClientOfItsServer(t *testing.T) {
	var closes []string
	proxies, providers := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{"wg": closeSpy{adapter.NewProxy(outbound.NewDirect()), &closes}}, providers)
	t.Cleanup(func() { tunnel.UpdateProxies(proxies, providers) })
	startTestOwner(t)
	if !slices.Equal(closes, []string{"wg"}) {
		t.Errorf("mihomo's client of the server was closed %d times, the engine carrying %q", len(closes), closes)
	}
}

// fakeWintun is sing-tun's WinTun over channels, as tuntest.ChannelTUN is wireguard-go's tun.
type fakeWintun struct {
	outbound, inbound chan []byte
	closed            chan struct{}
	once              sync.Once
}

func newFakeWintun() *fakeWintun {
	return &fakeWintun{outbound: make(chan []byte), inbound: make(chan []byte, 8), closed: make(chan struct{})}
}

func (f *fakeWintun) ReadPacket() ([]byte, func(), error) {
	select {
	case packet := <-f.outbound:
		return packet, func() {}, nil
	case <-f.closed:
		return nil, nil, os.ErrClosed
	}
}

func (f *fakeWintun) Read([]byte) (int, error) {
	return 0, errors.New("the engine reads whole packets")
}

func (f *fakeWintun) Write(packet []byte) (int, error) {
	f.inbound <- slices.Clone(packet)
	return len(packet), nil
}

func (f *fakeWintun) Close() error {
	f.once.Do(func() { close(f.closed) })
	return nil
}

func TestTheOwnerCarriesPacketsOnWindowsWintun(t *testing.T) {
	wintun := newFakeWintun()
	_, serverTun := startTestOwnerOn(t, newWinTun(wintun, "ShikooNet", 1280))
	out := tuntest.Ping(netip.MustParseAddr("10.13.13.1"), netip.MustParseAddr("10.13.13.2"))
	wintun.outbound <- out
	select {
	case got := <-serverTun.Inbound:
		if string(got) != string(out) {
			t.Fatal("the server got another packet")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no packet reached the server")
	}
	back := tuntest.Ping(netip.MustParseAddr("10.13.13.2"), netip.MustParseAddr("10.13.13.1"))
	serverTun.Outbound <- back
	select {
	case got := <-wintun.inbound:
		if string(got) != string(back) {
			t.Fatal("the system got another packet")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no packet came back")
	}
	if got := ownerServer(); got != "wg" {
		t.Errorf("the engine reports %q, want wg", got)
	}
	stopOwner()
	select {
	case <-wintun.closed:
	case <-time.After(5 * time.Second):
		t.Fatal("the stop left the adapter open")
	}
	if got := ownerServer(); got != "" {
		t.Errorf("a stopped engine reports %q", got)
	}
}

func TestTheServerInUseRunsOnTheOwnerOnlyWhenMarked(t *testing.T) {
	marked := wgMapping(t, map[string]any{"name": "wg-a", shikooOwnerKey: "wireguard"})
	raw := &config.RawConfig{
		Proxy:      []map[string]any{marked, wgMapping(t, map[string]any{"name": "wg-b"})},
		ProxyGroup: []map[string]any{{"name": "info", "hidden": true}, {"name": "main"}, {"name": "other"}},
		Rule:       []string{"DOMAIN,door.example,DIRECT", "MATCH,main"},
	}
	picks := map[string]string{"info": "wg-b", "main": "wg-a", "other": "wg-b"}
	now := func(group string) string { return picks[group] }

	if mapping, iran := ownerInUse(raw, now); mapping["name"] != "wg-a" || iran {
		t.Fatalf("got %v, Iran %v; want wg-a without Iran's ranges", mapping["name"], iran)
	}
	raw.Rule = append([]string{"RULE-SET, shikoo-ir-ip, DIRECT, no-resolve"}, raw.Rule...)
	if _, iran := ownerInUse(raw, now); !iran {
		t.Error("the Iranian switch's rule did not keep Iran's ranges out")
	}
	picks["main"], picks["other"] = "wg-b", "wg-a"
	if mapping, _ := ownerInUse(raw, now); mapping != nil {
		t.Errorf("the owner took %v, a pick outside the listed group", mapping["name"])
	}
}
