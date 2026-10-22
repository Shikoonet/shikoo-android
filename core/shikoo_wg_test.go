package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/netip"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
	"go4.org/netipx"
	wgconn "golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
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
	from13, _, _ := wgPlan(wgMapping(t, nil), iran, excludeRouteSdk, noResolve)
	below13, _, _ := wgPlan(wgMapping(t, nil), iran, excludeRouteSdk-1, noResolve)
	t.Logf("Android 13+: %d routes, %d excluded; below 13: %d routes", len(from13.Routes), len(from13.Excluded), len(below13.Routes))
	if len(from13.Excluded) == 0 || len(below13.Routes) <= len(from13.Excluded) {
		t.Errorf("from13 %d excluded, below13 %d routes", len(from13.Excluded), len(below13.Routes))
	}
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

func startTestOwner(t *testing.T) (*device.Device, *tuntest.ChannelTUN, *tuntest.ChannelTUN) {
	t.Helper()
	private, public := wgKeyPair(t)
	server, serverTun, serverPublic, port := wgServer(t, public)
	t.Cleanup(server.Close)
	_, prepared, err := wgPlan(map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": port, "ip": "10.13.13.2",
		"private-key": b64(private), "public-key": b64(serverPublic),
	}, nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	ownerMu.Lock()
	ownerPrepared = prepared
	ownerMu.Unlock()
	clientTun := tuntest.NewChannelTUN()
	if err := startOwner(clientTun.TUN()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(stopOwner)
	return server, serverTun, clientTun
}

func TestTheOwnerAnswersItsServersPingWithAHandshake(t *testing.T) {
	server, _, _ := startTestOwner(t)
	params, _ := json.Marshal(TestDelayParams{ProxyName: "wg", Timeout: 3000})
	fake := &fakeConn{}
	previous := swapConn(fake)
	defer swapConn(previous)
	methodHandlers[asyncTestDelayMethod](&MethodCall{ID: "1", Method: asyncTestDelayMethod, Arguments: params}, MethodResponse{ID: "1"})
	var frames [][]byte
	for deadline := time.Now().Add(5 * time.Second); len(frames) == 0 && time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		frames = fake.frames(t)
	}
	if len(frames) != 1 {
		t.Fatalf("%d answers", len(frames))
	}
	var answer struct{ Result Delay }
	if err := json.Unmarshal(frames[0], &answer); err != nil || answer.Result.Value <= 0 || answer.Result.Name != "wg" {
		t.Fatalf("answer %s (%v), want a delay for wg", frames[0], err)
	}

	server.Close()
	if delay := ownerFor("wg").testDelay(&TestDelayParams{ProxyName: "wg", Timeout: 300}); delay.Value != -1 {
		t.Errorf("a server that is gone answered %d", delay.Value)
	}
	if ownerFor("other") != nil {
		t.Error("the owner claims a server it does not hold")
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

func TestStopTunStopsTheOwnerAndForgetsAPreparedServer(t *testing.T) {
	startTestOwner(t)
	ownerMu.Lock()
	ownerPrepared = &wgPrepared{server: "next"}
	ownerMu.Unlock()
	stopOwner()
	if ownerFor("wg") != nil || ownerPrepared != nil {
		t.Error("the owner outlived its stop")
	}
	if err := startOwner(tuntest.NewChannelTUN().TUN()); err == nil {
		t.Error("started with nothing prepared")
	}
}
