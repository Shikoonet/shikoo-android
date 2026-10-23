package main

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func fakeOwner(t *testing.T, ping func(*TestDelayParams) *Delay) *string {
	t.Helper()
	carrying := new(string)
	registerShikooOwner("fake-owner", func() string { return *carrying }, ping)
	t.Cleanup(func() { delete(shikooOwners, "fake-owner") })
	return carrying
}

func TestShikooOwnerReportsTheServerAnOwnerEngineCarries(t *testing.T) {
	if _, ok := methodHandlers[shikooOwnerMethod]; !ok {
		t.Fatal("shikooOwner has no handler")
	}
	carrying := fakeOwner(t, nil)

	if got := shikooOwnerNow(); got != (ShikooOwner{}) {
		t.Errorf("with nothing carried the core reported %+v, want none", got)
	}
	*carrying = "W"
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "fake-owner", Server: "W"}) {
		t.Errorf("the core reported %+v, want fake-owner carrying W", got)
	}
}

func TestMihomosParserIgnoresTheOwnerMark(t *testing.T) {
	key := base64.StdEncoding.EncodeToString(wireGuardKey(t).Bytes())
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: H, type: http, server: 1.1.1.1, port: 1, shikoo-owner: wireguard}
  - {name: W, type: wireguard, server: 1.1.1.1, port: 1, private-key: %s, public-key: %s, ip: 10.0.0.2, shikoo-owner: wireguard}
  - {name: O, type: openvpn, server: 1.1.1.1, port: 1194, ca: %q, username: u, password: p, shikoo-owner: openvpn}
`, key, key,
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: []byte("ca")})))

	want := []constant.AdapterType{constant.Http, constant.WireGuard, constant.OpenVPN}
	if got := proxyTypes(cfg, "H", "W", "O"); !slices.Equal(got, want) {
		t.Errorf("types %v, want %v: a marked server stays mihomo's own until the owner core takes the tunnel", got, want)
	}
}

func TestAnOwnerRegisteredTwicePanics(t *testing.T) {
	fakeOwner(t, nil)
	defer func() {
		if recover() == nil {
			t.Error("a second fake-owner was taken")
		}
	}()
	registerShikooOwner("fake-owner", func() string { return "" }, nil)
}

// silentPeer is a WireGuard server that never answers: it records the source port of every packet it hears.
type silentPeer struct {
	conn  *net.UDPConn
	mu    sync.Mutex
	ports []int
}

func listenSilentPeer(t *testing.T) *silentPeer {
	t.Helper()
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	peer := &silentPeer{conn: conn}
	go func() {
		buffer := make([]byte, 2048)
		for {
			_, from, err := conn.ReadFromUDP(buffer)
			if err != nil {
				return
			}
			peer.mu.Lock()
			peer.ports = append(peer.ports, from.Port)
			peer.mu.Unlock()
		}
	}()
	return peer
}

func (peer *silentPeer) heard() []int {
	peer.mu.Lock()
	defer peer.mu.Unlock()
	return append([]int(nil), peer.ports...)
}

func wireGuardKey(t *testing.T) *ecdh.PrivateKey {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return key
}

// gatedWireGuard is the profile Dart writes once the user picks an owner core for W: W marked, behind a selector.
func gatedWireGuard(t *testing.T, peer *silentPeer) *config.Config {
	t.Helper()
	encode := base64.StdEncoding.EncodeToString
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: W, type: wireguard, server: 127.0.0.1, port: %d, private-key: %s, public-key: %s, ip: 10.0.0.2, udp: true, shikoo-owner: wireguard}
proxy-groups:
  - {name: G, type: select, proxies: [W]}
rules:
  - MATCH,G
`, peer.conn.LocalAddr().(*net.UDPAddr).Port, encode(wireGuardKey(t).Bytes()), encode(wireGuardKey(t).PublicKey().Bytes())))
	t.Cleanup(func() { closeWireGuard(cfg) })
	return cfg
}

var (
	toTCP = &constant.Metadata{NetWork: constant.TCP, DstIP: netip.MustParseAddr("10.0.0.1"), DstPort: 80}
	toUDP = &constant.Metadata{NetWork: constant.UDP, DstIP: netip.MustParseAddr("10.0.0.1"), DstPort: 53}
)

func TestMihomosClientOfAServerAnOwnerCarriesNeverReachesIt(t *testing.T) {
	peer := listenSilentPeer(t)
	cfg := gatedWireGuard(t, peer)
	*fakeOwner(t, nil) = "W"
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	match := cfg.Rules[len(cfg.Rules)-1]
	if match.RuleType() != constant.MATCH {
		t.Fatalf("last rule %v, want MATCH", match.RuleType())
	}
	if _, err := cfg.Proxies[match.Adapter()].DialContext(ctx, toTCP); !errors.Is(err, errShikooOwnerCarries) {
		t.Errorf("a request by MATCH (checkIp, a pasted link before its DIRECT rule) got %v, want refused", err)
	}
	if _, err := cfg.Proxies["W"].ListenPacketContext(ctx, toUDP); !errors.Is(err, errShikooOwnerCarries) {
		t.Errorf("a UDP session got %v, want refused", err)
	}
	if _, err := cfg.Proxies["W"].URLTest(ctx, "http://10.0.0.1/generate_204", nil); err == nil {
		t.Error("mihomo's own delay test of W answered")
	}
	time.Sleep(300 * time.Millisecond)
	if heard := peer.heard(); len(heard) != 0 {
		t.Fatalf("the server heard %d packets from mihomo's client: a second handshake with the owner's key", len(heard))
	}
}

func TestTakingAServerSilencesMihomosClientThatDialedItBefore(t *testing.T) {
	peer := listenSilentPeer(t)
	cfg := gatedWireGuard(t, peer)
	carrying := fakeOwner(t, nil)
	previousProxies, previousProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	t.Cleanup(func() { tunnel.UpdateProxies(previousProxies, previousProviders) })
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, _ = cfg.Proxies["G"].DialContext(ctx, toTCP)
	if len(peer.heard()) == 0 {
		t.Fatal("the ping round before connect sent no handshake")
	}

	*carrying = "W"
	shikooOwnerTakes("W")
	at := len(peer.heard())
	// A peer that never answers gets the handshake again every five seconds while the client lives.
	time.Sleep(6 * time.Second)

	if more := len(peer.heard()) - at; more > 0 {
		t.Fatalf("mihomo's client sent %d packets to W after the owner took it", more)
	}
}

func TestAServerNoOwnerCarriesStaysMihomosAndRebinds(t *testing.T) {
	peer := listenSilentPeer(t)
	cfg := gatedWireGuard(t, peer)
	*fakeOwner(t, nil) = "another server"
	within := func(wait time.Duration) context.Context {
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		t.Cleanup(cancel)
		return ctx
	}

	// Three seconds: a first SYN can beat the device coming up, and the stack resends it after one.
	if _, err := cfg.Proxies["G"].DialContext(within(3*time.Second), toTCP); errors.Is(err, errShikooOwnerCarries) {
		t.Fatal("refused, though no owner carries W")
	}
	if _, err := cfg.Proxies["W"].ListenPacketContext(within(time.Second), toUDP); errors.Is(err, errShikooOwnerCarries) {
		t.Fatal("a UDP session refused, though no owner carries W")
	}
	heard := peer.heard()
	if len(heard) == 0 {
		t.Fatal("mihomo's client sent no handshake")
	}

	previousProxies, previousProviders := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	t.Cleanup(func() { tunnel.UpdateProxies(previousProxies, previousProviders) })
	rebindWireGuard()

	// A peer that never answers gets the handshake again every five seconds, now from the new socket.
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		for _, port := range peer.heard() {
			if port != heard[0] {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("every packet still came from port %d: the rebind did not reach the client behind the gate", heard[0])
}
