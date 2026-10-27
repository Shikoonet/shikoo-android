package main

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	ovpn "github.com/metacubex/mihomo/transport/openvpn"
	"github.com/metacubex/mihomo/tunnel"
	"go4.org/netipx"
)

const testCA = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"

func staticKey(t *testing.T) (pem string, key []byte) {
	t.Helper()
	key = make([]byte, 256)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	lines := []string{"-----BEGIN OpenVPN Static key V1-----"}
	for i := 0; i < len(key); i += 16 {
		lines = append(lines, hex.EncodeToString(key[i:i+16]))
	}
	return strings.Join(append(lines, "-----END OpenVPN Static key V1-----"), "\n"), key
}

func ovpnMapping(set map[string]any) map[string]any {
	mapping := map[string]any{
		"name": "ov", "type": "openvpn", "server": "203.0.113.9", "port": 1194, "ca": testCA,
		"username": "shikoo", "password": "secret",
	}
	for key, value := range set {
		mapping[key] = value
	}
	return mapping
}

func profileLines(t *testing.T, set map[string]any) []string {
	t.Helper()
	plan, err := ovpnPrepare(ovpnMapping(set), false)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(plan.Profile, "\n")
}

func TestTheOpenvpnProfileStatesMihomosDefaults(t *testing.T) {
	lines := profileLines(t, nil)
	for _, want := range []string{"client", "dev tun", "proto udp", "remote 203.0.113.9 1194", "cipher AES-128-GCM",
		"auth SHA256", "auth-user-pass"} {
		if !slices.Contains(lines, want) {
			t.Errorf("no %q in\n%s", want, strings.Join(lines, "\n"))
		}
	}
	if plan, _ := ovpnPrepare(ovpnMapping(nil), false); plan.Username != "shikoo" || plan.Password != "secret" ||
		strings.Contains(plan.Profile, "secret") || !strings.Contains(plan.Profile, "<ca>\n"+testCA+"\n</ca>") {
		t.Errorf("credentials: %q %q, in the profile: %v", plan.Username, plan.Password, strings.Contains(plan.Profile, "secret"))
	}
}

func TestTheOpenvpnProfileKeepsWhatTheMappingSays(t *testing.T) {
	key, _ := staticKey(t)
	lines := profileLines(t, map[string]any{
		"proto": "tcp", "cipher": "AES-256-CBC", "auth": "SHA1", "tls-auth": key, "key-direction": "1",
		"comp-lzo": "no", "ping": 10, "ping-restart": 60,
	})
	for _, want := range []string{"proto tcp-client", "cipher AES-256-CBC", "auth SHA1", "key-direction 1", "comp-lzo no",
		"ping 10", "ping-restart 60", "<tls-auth>", "</tls-auth>"} {
		if !slices.Contains(lines, want) {
			t.Errorf("no %q in\n%s", want, strings.Join(lines, "\n"))
		}
	}
	crypt, _ := staticKey(t)
	if lines := profileLines(t, map[string]any{"tls-crypt": crypt}); !slices.Contains(lines, "<tls-crypt>") ||
		slices.Contains(lines, "key-direction 1") {
		t.Errorf("tls-crypt profile:\n%s", strings.Join(lines, "\n"))
	}
}

func TestTheOpenvpnEngineRefusesWhatOnlyMihomoCarries(t *testing.T) {
	for _, set := range []map[string]any{
		{"dialer-proxy": "other"},
		{"peer-info": map[string]any{"IV_X": "1"}},
		{"dev": "tap"},
		{"ca": ""},
	} {
		if _, err := ovpnPrepare(ovpnMapping(set), false); err == nil {
			t.Errorf("%v: prepared", set)
		}
	}
}

func TestPrepareOwnerGivesOpenvpnItsProfile(t *testing.T) {
	home := t.TempDir()
	was := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(was) })
	config := "proxies:\n  - {name: ov, type: openvpn, server: 203.0.113.9, port: 1194, username: u, password: p, ca: \"" +
		strings.ReplaceAll(testCA, "\n", "\\n") + "\"}\n"
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	answer, err := handlePrepareOwner(&PrepareOwnerParams{Core: "openvpn", Server: "ov", IranDirect: true})
	if err != nil {
		t.Fatal(err)
	}
	out, _ := json.Marshal(answer)
	var plan map[string]string
	if json.Unmarshal(out, &plan) != nil || !strings.Contains(plan["ovpn"], "remote 203.0.113.9 1194") || plan["username"] != "u" {
		t.Errorf("Kotlin reads %s", out)
	}
	if prepared := ovpnPrepared.Load(); prepared == nil || prepared.server != "ov" || !prepared.iranDirect {
		t.Errorf("prepared %+v", prepared)
	}
}

func prepareOpenvpn(t *testing.T, iranDirect bool) {
	t.Helper()
	if _, err := ovpnPrepare(ovpnMapping(nil), iranDirect); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ovpnPrepared.Store(nil) })
}

func withShippedIranianSet(t *testing.T) {
	t.Helper()
	set, err := os.ReadFile("../assets/data/shikoo-ir-ip.mrs")
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	if err := os.WriteFile(filepath.Join(home, "shikoo-ir-ip.mrs"), set, 0o600); err != nil {
		t.Fatal(err)
	}
	was := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(was) })
}

func pushed() *ovpnTunnelSpec {
	return &ovpnTunnelSpec{Addresses: []string{"10.8.0.2/24"}}
}

func ipSet(values []string) *netipx.IPSet {
	var b netipx.IPSetBuilder
	for _, value := range values {
		b.AddPrefix(netip.MustParsePrefix(value))
	}
	return must(b.IPSet())
}

func TestOpenvpnsTunnelKeepsIranOutAsExcludedRoutesFromAndroid13(t *testing.T) {
	withShippedIranianSet(t)
	prepareOpenvpn(t, true)
	plan := must(ovpnTunnel(pushed(), 33))
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0"}) || !slices.Contains(plan.Excluded, "2.176.0.0/12") ||
		len(plan.Excluded)+len(plan.Routes) > wgExcludedBudget {
		t.Errorf("routes %v, %d excluded", plan.Routes, len(plan.Excluded))
	}
	if !slices.Equal(plan.Addresses, []string{"10.8.0.2/24"}) || plan.MTU != 1500 || plan.DNS == nil {
		t.Errorf("addresses %v, mtu %d, dns %v", plan.Addresses, plan.MTU, plan.DNS)
	}
}

func TestOpenvpnsTunnelCutsIranOutOfTheRoutesBelowAndroid13(t *testing.T) {
	withShippedIranianSet(t)
	prepareOpenvpn(t, true)
	plan := must(ovpnTunnel(pushed(), 25))
	routes := ipSet(plan.Routes)
	if len(plan.Excluded) != 0 || len(plan.Routes) > wgRoutesBudget ||
		routes.Contains(netip.MustParseAddr("2.176.0.1")) || !routes.Contains(netip.MustParseAddr("1.1.1.1")) {
		t.Errorf("%d routes, %d excluded", len(plan.Routes), len(plan.Excluded))
	}
}

func TestOpenvpnsTunnelKeepsTheServersDNSAndMTUWhenIranGoesThroughIt(t *testing.T) {
	withShippedIranianSet(t)
	prepareOpenvpn(t, false)
	spec := pushed()
	spec.DNS, spec.MTU = []string{"10.8.0.1"}, 1400
	plan := must(ovpnTunnel(spec, 33))
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0"}) || len(plan.Excluded) != 0 ||
		!slices.Equal(plan.DNS, []string{"10.8.0.1"}) || plan.MTU != 1400 {
		t.Errorf("%+v", plan)
	}
}

// Android blocks a family the VPN has nothing of; a pushed IPv6 DNS server alone would have let IPv6 out beside it.
// A family with an address goes all through the tunnel, with or without redirect-gateway from the server.
func TestOpenvpnsTunnelTakesAllOfEachFamilyItHasAnAddressIn(t *testing.T) {
	prepareOpenvpn(t, false)
	spec := pushed()
	spec.DNS = []string{"1.1.1.1", "2606:4700:4700::1111"}
	plan := must(ovpnTunnel(spec, 33))
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0"}) || !slices.Equal(plan.DNS, []string{"1.1.1.1"}) {
		t.Errorf("an IPv4-only tunnel: routes %v, dns %v", plan.Routes, plan.DNS)
	}
	spec.Addresses = append(spec.Addresses, "fd00:8::2/64")
	plan = must(ovpnTunnel(spec, 33))
	if !slices.Equal(plan.Routes, []string{"0.0.0.0/0", "::/0"}) || len(plan.DNS) != 2 {
		t.Errorf("a dual-stack tunnel: routes %v, dns %v", plan.Routes, plan.DNS)
	}
}

// The keys Kotlin's Core.openvpnState sends, and the plan's it reads (VpnService.addOwnerTunnel).
func TestOpenvpnsKeysAreThoseKotlinUses(t *testing.T) {
	var state ovpnStateParams
	if err := json.Unmarshal([]byte(`{"session":3,"server":"ov","up":true}`), &state); err != nil ||
		state != (ovpnStateParams{Session: 3, Server: "ov", Up: true}) {
		t.Errorf("read %+v (%v)", state, err)
	}
	var spec ovpnTunnelSpec
	if err := json.Unmarshal([]byte(`{"addresses":["10.8.0.2/24"],"dns":["1.1.1.1"],"mtu":1500}`), &spec); err != nil ||
		len(spec.Addresses) != 1 || len(spec.DNS) != 1 || spec.MTU != 1500 {
		t.Errorf("read %+v (%v)", spec, err)
	}
	out, _ := json.Marshal(&ownerPlan{})
	for _, key := range []string{`"addresses"`, `"routes"`, `"excluded"`, `"dns"`, `"mtu"`} {
		if !strings.Contains(string(out), key) {
			t.Errorf("no %s in %s", key, out)
		}
	}
	kotlin := string(must(os.ReadFile("../android/core/src/main/java/com/follow/clash/core/Core.kt")))
	for _, call := range []string{`"` + string(shikooOpenvpnTunnelMethod) + `"`, `"` + string(shikooOpenvpnStateMethod) + `"`,
		`put("session", session)`, `put("server", server)`, `put("up", up)`} {
		if !strings.Contains(kotlin, call) {
			t.Errorf("Core.kt has no %s", call)
		}
	}
}

type ovpnCloseSpy struct {
	constant.Proxy
	closes *int
}

func (spy ovpnCloseSpy) Close() error {
	*spy.closes++
	return nil
}

// A session mihomo's client opened while off (a ping round) would otherwise outlive the gate and take the engine's.
func TestTheEngineTakingAServerClosesMihomosClientOfItOnce(t *testing.T) {
	registerTestOpenvpn(t)
	closes := 0
	proxies, providers := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(map[string]constant.Proxy{"ov": ovpnCloseSpy{adapter.NewProxy(outbound.NewDirect()), &closes}}, providers)
	t.Cleanup(func() { tunnel.UpdateProxies(proxies, providers) })
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov"})
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov", Up: true})
	if closes != 1 {
		t.Errorf("mihomo's client of the server was closed %d times", closes)
	}
}

func registerTestOpenvpn(t *testing.T) {
	t.Helper()
	registerShikooOwner("openvpn-test", ovpnCarrying, ovpnPing)
	t.Cleanup(func() {
		delete(shikooOwners, "openvpn-test")
		ovpnNow.Store(nil)
	})
}

func TestTheServiceTellsTheRegistryWhatOpenvpnCarries(t *testing.T) {
	registerTestOpenvpn(t)
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov"})
	if now := shikooOwnerNow(); now != (ShikooOwner{Core: "openvpn-test", Server: "ov"}) {
		t.Errorf("carrying %+v while connecting", now)
	}
	ovpnState(&ovpnStateParams{Session: 2, Server: "ov2"})
	ovpnState(&ovpnStateParams{Session: 1})
	if now := shikooOwnerNow(); now.Server != "ov2" {
		t.Errorf("an older session's end cleared the newer one: %+v", now)
	}
	ovpnState(&ovpnStateParams{Session: 2})
	if now := shikooOwnerNow(); now != (ShikooOwner{}) {
		t.Errorf("carrying %+v after the end", now)
	}
}

// resetServer answers a client's hard reset as an OpenVPN server does, over UDP or TCP.
func resetServer(t *testing.T, network string, crypt ovpn.ControlCryptor, opcode ovpn.Opcode) string {
	t.Helper()
	answer := func(packet []byte) []byte {
		reset, _, _, err := ovpn.DecodeControlPacket(crypt, packet)
		if err != nil || reset.Opcode != ovpn.PControlHardResetClientV2 {
			return nil
		}
		reply := ovpn.ControlPacket{Opcode: opcode, LocalSession: must(ovpn.NewSessionID()),
			AckIDs: []uint32{reset.MessageID}, AckRemoteSession: reset.LocalSession}
		return must(reply.Encode(crypt, 1, uint32(time.Now().Unix())))
	}
	if network == "udp" {
		conn := must(net.ListenPacket("udp", "127.0.0.1:0"))
		t.Cleanup(func() { conn.Close() })
		go func() {
			buf := make([]byte, 2048)
			for {
				n, from, err := conn.ReadFrom(buf)
				if err != nil {
					return
				}
				if reply := answer(buf[:n]); reply != nil {
					_, _ = conn.WriteTo(reply, from)
				}
			}
		}()
		return conn.LocalAddr().String()
	}
	listener := must(net.Listen("tcp", "127.0.0.1:0"))
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				var size uint16
				if binary.Read(conn, binary.BigEndian, &size) != nil {
					return
				}
				packet := make([]byte, size)
				if _, err := io.ReadFull(conn, packet); err != nil {
					return
				}
				if reply := answer(packet); reply != nil {
					_ = binary.Write(conn, binary.BigEndian, uint16(len(reply)))
					_, _ = conn.Write(reply)
				}
			}()
		}
	}()
	return listener.Addr().String()
}

func pingOpenvpn(t *testing.T, address string, set map[string]any, up bool) int32 {
	t.Helper()
	host, port, _ := net.SplitHostPort(address)
	set["server"], set["port"] = host, port
	if _, err := ovpnPrepare(ovpnMapping(set), false); err != nil {
		t.Fatal(err)
	}
	ovpnState(&ovpnStateParams{Session: 1, Server: "ov", Up: up})
	return ovpnPing(&TestDelayParams{ProxyName: "ov", Timeout: 1500}).Value
}

func TestOpenvpnsPingIsTheServersAnswerToAReset(t *testing.T) {
	registerTestOpenvpn(t)
	authPEM, authKey := staticKey(t)
	cryptPEM, cryptKey := staticKey(t)
	serverAuth := must(ovpn.NewTLSAuth(authKey, "0", "SHA256"))
	serverCrypt := must(ovpn.NewTLSCrypt(cryptKey, false))
	for _, c := range []struct {
		name    string
		network string
		server  ovpn.ControlCryptor
		set     map[string]any
	}{
		{"udp", "udp", nil, map[string]any{}},
		{"udp tls-auth", "udp", serverAuth, map[string]any{"tls-auth": authPEM, "key-direction": "1"}},
		{"udp tls-crypt", "udp", serverCrypt, map[string]any{"tls-crypt": cryptPEM}},
		{"tcp tls-crypt", "tcp", serverCrypt, map[string]any{"tls-crypt": cryptPEM, "proto": "tcp"}},
	} {
		address := resetServer(t, c.network, c.server, ovpn.PControlHardResetServerV2)
		if value := pingOpenvpn(t, address, c.set, true); value <= 0 {
			t.Errorf("%s: ping %d", c.name, value)
		}
		if value := pingOpenvpn(t, address, c.set, false); value != -1 {
			t.Errorf("%s: ping %d while the engine's session is down", c.name, value)
		}
	}
	wrongPEM, _ := staticKey(t)
	address := resetServer(t, "udp", serverCrypt, ovpn.PControlHardResetServerV2)
	if value := pingOpenvpn(t, address, map[string]any{"tls-crypt": wrongPEM}, true); value != -1 {
		t.Errorf("a server that cannot read the reset answered in %d ms", value)
	}
	address = resetServer(t, "udp", serverCrypt, ovpn.PControlHardResetServerV1)
	if value := pingOpenvpn(t, address, map[string]any{"tls-crypt": cryptPEM}, true); value != -1 {
		t.Errorf("a key-method 1 answer, which the engine cannot use, counted as a ping of %d ms", value)
	}
}
