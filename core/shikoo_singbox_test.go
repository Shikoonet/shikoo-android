package main

import (
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"maps"
	"math/big"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	madapter "github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/trie"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	mDNS "github.com/miekg/dns"
	xcore "github.com/xtls/xray-core/core"
	"golang.org/x/crypto/ssh"
)

func TestSingBoxServesWhatDartSays(t *testing.T) {
	content, err := os.ReadFile("testdata/sing_box_serves.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []struct {
		Serves bool           `json:"serves"`
		Proxy  map[string]any `json:"proxy"`
	}
	if err := json.Unmarshal(content, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		if got := singBoxServes(c.Proxy); got != c.Serves {
			t.Errorf("%v: serves %v, want %v", c.Proxy["name"], got, c.Serves)
		}
	}
}

// x25519 gives a key pair the way WireGuard (std) or REALITY (raw URL) writes it.
func x25519(t *testing.T, encoding *base64.Encoding) (private, public string) {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return encoding.EncodeToString(key.Bytes()), encoding.EncodeToString(key.PublicKey().Bytes())
}

func TestSingBoxCarriesEveryTypeItServesAndStopsWithItsGeneration(t *testing.T) {
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	wgPrivate, wgPublic := x25519(t, base64.StdEncoding)
	ca := e2ePKI(t, t.TempDir())
	_, clientKey := e2eSSHKey(t)
	proxies := fmt.Sprintf(`
proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, flow: xtls-rprx-vision, servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd}, shikoo-core: singBox}
  - {name: ws, type: vless, server: a.test, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: ws, ws-opts: {path: /p, headers: {Host: a.test}}, shikoo-core: singBox}
  - {name: grpc, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: grpc, grpc-opts: {grpc-service-name: g}, client-fingerprint: firefox, shikoo-core: singBox}
  - {name: xhttp, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: xhttp, shikoo-core: singBox}
  - {name: wg, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %q, public-key: %q, udp: true, shikoo-core: singBox}
  - {name: wg dns, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %[2]q, public-key: %[3]q, udp: true, remote-dns-resolve: true, dns: [1.1.1.1, 8.8.8.8], shikoo-core: singBox}
  - {name: ovpn, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p, shikoo-core: singBox}
  - {name: ssh, type: ssh, server: 127.0.0.1, port: 1, username: u, private-key: %q, shikoo-core: singBox}
`, realityPublic, wgPrivate, wgPublic, ca, clientKey)
	t.Cleanup(func() { shikooCoresRunning, shikooCoresStarting = nil, nil })

	cfg := parseShikooCores(t, proxies)
	shikooCoresCommit()

	got := proxyTypes(cfg, "reality", "ws", "grpc", "xhttp", "wg", "wg dns", "ovpn", "ssh")
	want := []C.AdapterType{C.Socks5, C.Socks5, C.Socks5, C.Vless, C.Socks5, C.Socks5, C.Socks5, C.Socks5}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("types %v, want %v: XHTTP stays on mihomo, every other server goes to sing-box", got, want)
		}
	}
	if !cfg.Proxies["wg"].SupportUDP() || !cfg.Proxies["ovpn"].SupportUDP() || cfg.Proxies["ssh"].SupportUDP() {
		t.Error("UDP must follow what mihomo's own adapter carries")
	}
	first := cfg.Proxies["reality"].Addr()
	if conn, err := net.Dial("tcp", first); err != nil {
		t.Fatalf("sing-box is not listening at %s: %v", first, err)
	} else {
		conn.Close()
	}

	if again := parseShikooCores(t, proxies); again.Proxies["reality"].Type() != C.Socks5 {
		t.Fatal("the next generation did not start while the previous one still runs")
	}
	shikooCoresCommit()
	if conn, err := net.DialTimeout("tcp", first, time.Second); err == nil {
		conn.Close()
		t.Fatal("the previous sing-box still listens after the next generation was committed")
	}
	for _, stop := range shikooCoresRunning {
		stop()
	}
}

// Xray-core v26.9.8 and later refuse a REALITY ClientHello without X25519MLKEM768 ahead of X25519 (XTLS/REALITY
// 8cdf7bf9); unpatched sing-box 1.14.3 strips it (row ۵۷ in SHIKOO_PATCHES.md).
func TestSingBoxRealityOffersMLKEMBeforeX25519(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	hellos := make(chan []byte, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		header := make([]byte, 5)
		if _, err := io.ReadFull(conn, header); err != nil {
			return
		}
		body := make([]byte, int(header[3])<<8|int(header[4]))
		if _, err := io.ReadFull(conn, body); err == nil {
			hellos <- body
		}
	}()
	_, public := x25519(t, base64.RawURLEncoding)
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: r, type: vless, server: 127.0.0.1, port: %d, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: reality.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd},
     shikoo-core: singBox}
`, listener.Addr().(*net.TCPAddr).Port, public))
	t.Cleanup(e2eStop)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if conn, err := cfg.Proxies["r"].DialContext(ctx, e2eTarget("127.0.0.1", 1)); err == nil {
		defer conn.Close()
	}

	var hello []byte
	select {
	case hello = <-hellos:
	case <-time.After(5 * time.Second):
		t.Fatal("sing-box sent no ClientHello")
	}
	groups, shares := helloGroups(t, hello)
	const mlkem, classic = 0x11ec, 0x001d
	if len(shares) < 2 || shares[0] != mlkem || shares[1] != classic {
		t.Errorf("key shares %#x, want X25519MLKEM768 then X25519", shares)
	}
	mlkemAt, classicAt := slices.Index(groups, mlkem), slices.Index(groups, classic)
	if mlkemAt < 0 || mlkemAt > classicAt {
		t.Errorf("supported groups %#x, want X25519MLKEM768 ahead of X25519", groups)
	}
}

// ovpnStaticKey is a random OpenVPN static key in the file format, comment lines included.
func ovpnStaticKey(t *testing.T) string {
	t.Helper()
	key := make([]byte, 256)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	text := "#\n# 2048 bit OpenVPN static key\n#\n-----BEGIN OpenVPN Static key V1-----\n"
	for i := 0; i < len(key); i += 16 {
		text += hex.EncodeToString(key[i:i+16]) + "\n"
	}
	return text + "-----END OpenVPN Static key V1-----\n"
}

// sing-openvpn reads control-channel keys in its own goroutine, where a bad one panics and ends the app.
func TestSingBoxNeverGetsAKeyThatWouldPanic(t *testing.T) {
	ca := e2ePKI(t, t.TempDir())
	key := ovpnStaticKey(t)
	lines := strings.Split(key, "\n")
	short := strings.Join(append(lines[3:12], lines[19:]...), "\n")
	v2 := "-----BEGIN OpenVPN tls-crypt-v2 client key-----\nAAAA\n-----END OpenVPN tls-crypt-v2 client key-----\n"
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	proxy := func(name string, extra string) string {
		return fmt.Sprintf("  - {name: %q, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p, %s, "+
			"shikoo-core: singBox}\n", name, ca, extra)
	}
	yaml := "proxies:\n" + proxy("good", fmt.Sprintf("tls-auth: %q, key-direction: \"1\"", key)) +
		proxy("garbage", `tls-auth: garbage, key-direction: "1"`) +
		proxy("short", fmt.Sprintf("tls-auth: %q, key-direction: \"1\"", short)) +
		proxy("crypt garbage", "tls-crypt: garbage") +
		proxy("crypt v2 garbage", "tls-crypt-v2: garbage") +
		proxy("crypt v2 empty", fmt.Sprintf("tls-crypt-v2: %q", v2)) +
		fmt.Sprintf("  - {name: long short-id, type: vless, server: 127.0.0.1, port: 1, "+
			"uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, servername: a.test, client-fingerprint: chrome, "+
			"reality-opts: {public-key: %s, short-id: 0123456789abcdef01}, shikoo-core: singBox}\n", realityPublic)
	raw, err := config.UnmarshalRawConfig([]byte(yaml))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(e2eStop)

	shikooCoresRewrite(raw)

	types := map[string]any{}
	for _, mapping := range raw.Proxy {
		types[mapping["name"].(string)] = mapping["type"]
	}
	want := map[string]any{"good": "socks5", "garbage": "openvpn", "short": "openvpn", "crypt garbage": "openvpn",
		"crypt v2 garbage": "openvpn", "crypt v2 empty": "openvpn", "long short-id": "vless"}
	if !maps.Equal(types, want) {
		t.Fatalf("types %v, want %v: what mihomo's parser refuses stays on mihomo", types, want)
	}
	time.Sleep(2 * time.Second) // the supervisor tries a session at once, and a panic there ends this test binary
}

func TestSingBoxLeavesAKeyOnlyMihomoReadsToMihomo(t *testing.T) {
	ca := e2ePKI(t, t.TempDir())
	key := strings.Replace(ovpnStaticKey(t), "-----BEGIN OpenVPN Static key V1-----\n",
		"-----BEGIN OpenVPN Static key V1-----\n# a comment\n", 1)
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd},
     shikoo-core: singBox}
  - {name: auth, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p, tls-auth: %q,
     key-direction: "1", shikoo-core: singBox}
  - {name: crypt, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p, tls-crypt: %q,
     shikoo-core: singBox}
`, realityPublic, ca, key, ca, key))
	t.Cleanup(e2eStop)

	got := proxyTypes(cfg, "reality", "auth", "crypt")
	want := []C.AdapterType{C.Socks5, C.OpenVPN, C.OpenVPN}
	if !slices.Equal(got, want) {
		t.Fatalf("types %v, want %v: sing-openvpn refuses the key up front, so only those servers stay on mihomo", got, want)
	}
	time.Sleep(2 * time.Second) // a panic in sing-openvpn's goroutine would end this test binary
}

func TestSingBoxNewTurnsAPanicIntoAnError(t *testing.T) {
	_, public := x25519(t, base64.RawURLEncoding)
	out := map[string]any{"type": "vless", "tag": "s0", "detour": "mihomo", "server": "127.0.0.1", "server_port": 1,
		"uuid": "4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11", "tls": map[string]any{"enabled": true, "server_name": "a.test",
			"utls":    map[string]any{"enabled": true, "fingerprint": "chrome"},
			"reality": map[string]any{"enabled": true, "public_key": public, "short_id": "0123456789abcdef01"}}}

	instance, err := singBoxNew(singBoxConfig(1, "x", []singBoxServer{{0, out, false, false, ""}}), false)

	if err == nil || instance != nil {
		t.Fatalf("a short_id over 8 bytes gave %v, %v; want sing-box's panic as an error", instance, err)
	}
}

func TestSingBoxLeavesOnlyTheServerItRefusesToMihomo(t *testing.T) {
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	wgPrivate, wgPublic := x25519(t, base64.StdEncoding)
	ca := e2ePKI(t, t.TempDir())
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd},
     shikoo-core: singBox}
  - {name: bare allowed-ips, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %q,
     public-key: %q, allowed-ips: ["0.0.0.0", "::"], udp: true, shikoo-core: singBox}
  - {name: unknown cipher, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p,
     data-ciphers: [NOPE], shikoo-core: singBox}
  - {name: no fingerprint, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, reality-opts: {public-key: %[1]s, short-id: 0123abcd}, shikoo-core: singBox}
`, realityPublic, wgPrivate, wgPublic, ca))
	t.Cleanup(e2eStop)

	got := proxyTypes(cfg, "reality", "bare allowed-ips", "unknown cipher", "no fingerprint")
	want := []C.AdapterType{C.Socks5, C.Socks5, C.OpenVPN, C.Vless}
	if !slices.Equal(got, want) {
		t.Fatalf("types %v, want %v: mihomo takes the servers sing-box refuses, and only those", got, want)
	}
}

// sing-box takes a WireGuard key of 31 or 33 bytes and fails only when it starts; the key check keeps such a server on
// mihomo, and with the check opened up, so does the one-by-one start that follows a failed one.
func TestSingBoxLeavesAWireGuardKeyOfTheWrongLengthOnMihomo(t *testing.T) {
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	wgPrivate, wgPublic := x25519(t, base64.StdEncoding)
	short := base64.StdEncoding.EncodeToString(make([]byte, 31))
	long := base64.StdEncoding.EncodeToString(make([]byte, 33))
	proxies := fmt.Sprintf(`proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd},
     shikoo-core: singBox}
  - {name: private 31, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %q, public-key: %q,
     udp: true, shikoo-core: singBox}
  - {name: public 33, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %q, public-key: %q,
     udp: true, shikoo-core: singBox}
`, realityPublic, short, wgPublic, wgPrivate, long)
	check := singBoxWireGuardKey
	t.Cleanup(func() { singBoxWireGuardKey = check })
	for _, keys := range []*regexp.Regexp{check, regexp.MustCompile("")} {
		singBoxWireGuardKey = keys
		cfg := parseShikooCores(t, proxies)
		e2eStop()

		got := proxyTypes(cfg, "reality", "private 31", "public 33")
		want := []C.AdapterType{C.Socks5, C.WireGuard, C.WireGuard}
		if !slices.Equal(got, want) {
			t.Fatalf("key check %q: types %v, want %v", keys, got, want)
		}
	}
}

// mihomo refuses a config with a server its parser refuses; with sing-box in that server's place it would not.
func TestSingBoxLeavesWhatMihomoRefusesOnMihomo(t *testing.T) {
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	wgPrivate, wgPublic := x25519(t, base64.StdEncoding)
	raw, err := config.UnmarshalRawConfig([]byte(fmt.Sprintf(`proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %[1]s, short-id: 0123abcd},
     shikoo-core: singBox}
  - {name: reality without tls, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %[1]s, short-id: 0123abcd},
     shikoo-core: singBox}
  - {name: mtu 70000, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %[2]q, public-key: %[3]q,
     mtu: 70000, shikoo-core: singBox}
`, realityPublic, wgPrivate, wgPublic)))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(e2eStop)

	shikooCoresRewrite(raw)

	types := map[string]any{}
	for _, mapping := range raw.Proxy {
		types[mapping["name"].(string)] = mapping["type"]
	}
	want := map[string]any{"reality": "socks5", "reality without tls": "vless", "mtu 70000": "wireguard"}
	if !maps.Equal(types, want) {
		t.Fatalf("types %v, want %v", types, want)
	}
}

func TestSingBoxConvertsToWhatMihomoWouldUse(t *testing.T) {
	vless := map[string]any{"name": "n", "type": "vless", "server": "a.test", "port": 443, "uuid": "u", "network": "ws"}
	wg := map[string]any{"name": "n", "type": "wireguard", "server": "127.0.0.1", "port": 1, "private-key": "k",
		"public-key": "p", "ip": "10.0.0.2", "allowed-ips": []any{"10.0.0.0/8"}}
	ovpn := map[string]any{"name": "n", "type": "openvpn", "server": "127.0.0.1", "port": 1, "ca": "c"}
	with := func(base map[string]any, changes map[string]any) map[string]any {
		mapping := maps.Clone(base)
		maps.Copy(mapping, changes)
		return mapping
	}
	peer := `{"address":"127.0.0.1","allowed_ips":%s,"persistent_keepalive_interval":0,"port":1,"pre_shared_key":"",` +
		`"public_key":"p","reserved":%s}`
	for _, c := range []struct {
		name    string
		mapping map[string]any
		fields  string
		want    string
	}{
		{"ws ?ed", with(vless, map[string]any{"ws-opts": map[string]any{"path": "/p?ed=2048&x=1"}}), "transport",
			`{"early_data_header_name":"Sec-WebSocket-Protocol","headers":null,"max_early_data":2048,"path":"/p?x=1","type":"ws"}`},
		{"ws other query", with(vless, map[string]any{"ws-opts": map[string]any{"path": "/p?x=1"}}), "transport",
			`{"early_data_header_name":"","headers":null,"max_early_data":0,"path":"/p?x=1","type":"ws"}`},
		{"wg single, both families", with(wg, map[string]any{"ipv6": "fd00::2"}), "address peers detour",
			`["10.0.0.2/32","fd00::2/128"] [` + fmt.Sprintf(peer, `["0.0.0.0/0","::/0"]`, "null") + `] "mihomo-unconnected"`},
		{"wg single, IPv4", wg, "peers", `[` + fmt.Sprintf(peer, `["0.0.0.0/0"]`, "null") + `]`},
		{"wg peers", with(wg, map[string]any{"reserved": []any{1, 2, 3}, "peers": []any{map[string]any{"server": "127.0.0.1",
			"port": 1, "public-key": "p", "allowed-ips": []any{"10.0.0.0/8"}}}}), "peers",
			`[` + fmt.Sprintf(peer, `["10.0.0.0/8"]`, `"AQID"`) + `]`},
		{"ovpn plain", ovpn, "data_ciphers data_ciphers_fallback auth compression_lzo",
			`["AES-128-GCM"] "AES-128-GCM" "SHA256" null`},
		{"ovpn comp-lzo no", with(ovpn, map[string]any{"comp-lzo": "no"}), "compression_lzo", `null`},
		{"ovpn cbc", with(ovpn, map[string]any{"cipher": "aes-256-cbc", "auth": "sha-1", "comp-lzo": "adaptive"}),
			"data_ciphers data_ciphers_fallback auth compression_lzo", `["AES-256-CBC"] "AES-256-CBC" "SHA1" "yes"`},
		{"ovpn data-ciphers", with(ovpn, map[string]any{"data-ciphers": []any{"aes-256-gcm", "chacha20-poly1305"},
			"data-ciphers-fallback": "AES-CBC"}), "data_ciphers data_ciphers_fallback",
			`["AES-256-GCM","CHACHA20-POLY1305"] "AES-128-CBC"`},
	} {
		out, _, _, err := singBoxConvert(context.Background(), c.mapping)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		var tree map[string]any
		content, _ := json.Marshal(out)
		json.Unmarshal(content, &tree)
		var got []string
		for _, field := range strings.Fields(c.fields) {
			value, _ := json.Marshal(tree[field])
			got = append(got, string(value))
		}
		if strings.Join(got, " ") != c.want {
			t.Errorf("%s: %s is\n%s, want\n%s", c.name, c.fields, strings.Join(got, " "), c.want)
		}
	}
}

func TestSingBoxSocksIsLocalWithAFreshSecret(t *testing.T) {
	_, public := x25519(t, base64.RawURLEncoding)
	mapping := map[string]any{"name": "r", "type": "vless", "server": "127.0.0.1", "port": 1,
		"uuid": "4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11", "tls": true, "servername": "a.test", "client-fingerprint": "chrome",
		"reality-opts": map[string]any{"public-key": public, "short-id": "0123abcd"}}
	var passwords []string
	for range 2 {
		replacements, stop, err := startSingBox([]map[string]any{maps.Clone(mapping)})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(stop)
		socks := replacements[0]
		password := socks["password"].(string)
		if socks["server"] != "127.0.0.1" || len(password) < 20 {
			t.Fatalf("replacement %v: want 127.0.0.1 and a password of 20 characters or more", socks)
		}
		passwords = append(passwords, password)
		outside := net.JoinHostPort(e2eHostIP(t), strconv.Itoa(socks["port"].(int)))
		if conn, err := net.DialTimeout("tcp", outside, time.Second); err == nil {
			conn.Close()
			t.Fatalf("sing-box's SOCKS answers on %s, not only on loopback", outside)
		}
		wrong := maps.Clone(socks)
		wrong["password"] = password + "x"
		proxy, err := madapter.ParseProxy(wrong)
		if err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		conn, err := proxy.DialContext(ctx, e2eTarget("127.0.0.1", 1))
		cancel()
		if err == nil {
			conn.Close()
			t.Fatal("sing-box's SOCKS took a wrong password")
		}
	}
	if passwords[0] == passwords[1] {
		t.Fatal("two generations share a password")
	}
}

// mihomo resolves a VLESS or SSH server's name with its proxy-server resolver, never the tunnel's.
func TestSingBoxServerNameGoesToMihomosProxyServerResolver(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	reached := make(chan struct{}, 1)
	go func() {
		if conn, err := listener.Accept(); err == nil {
			conn.Close()
			reached <- struct{}{}
		}
	}()
	asked := e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"vless.shikoo.test.": "127.0.0.1"})
	tunnel := e2eNames(t, &resolver.DefaultResolver, nil)
	_, public := x25519(t, base64.RawURLEncoding)
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: r, type: vless, server: vless.shikoo.test, port: %d, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true,
     servername: a.test, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd},
     shikoo-core: singBox}
`, listener.Addr().(*net.TCPAddr).Port, public))
	t.Cleanup(e2eStop)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if conn, err := cfg.Proxies["r"].DialContext(ctx, e2eTarget("127.0.0.1", 1)); err == nil {
		defer conn.Close()
	}

	select {
	case <-reached:
	case <-time.After(5 * time.Second):
		t.Fatal("sing-box never reached the server by its name")
	}
	if !slices.Contains(*asked, "vless.shikoo.test.") || slices.Contains(*tunnel, "vless.shikoo.test.") {
		t.Fatalf("proxy-server resolver asked %v, tunnel resolver asked %v", *asked, *tunnel)
	}
}

// helloGroups reads a ClientHello handshake message: its supported groups and its key shares' groups, GREASE left out.
func helloGroups(t *testing.T, hello []byte) (groups, shares []uint16) {
	t.Helper()
	u16 := func(b []byte) int { return int(b[0])<<8 | int(b[1]) }
	grease := func(v int) bool { return v&0x0f0f == 0x0a0a }
	at := 4 + 2 + 32
	at += 1 + int(hello[at])
	at += 2 + u16(hello[at:])
	at += 1 + int(hello[at])
	end := at + 2 + u16(hello[at:])
	for at += 2; at < end; {
		kind, size := u16(hello[at:]), u16(hello[at+2:])
		data := hello[at+4 : at+4+size]
		switch kind {
		case 10:
			for i := 2; i < len(data); i += 2 {
				if g := u16(data[i:]); !grease(g) {
					groups = append(groups, uint16(g))
				}
			}
		case 51:
			for i := 2; i < len(data); i += 4 + u16(data[i+2:]) {
				if g := u16(data[i:]); !grease(g) {
					shares = append(shares, uint16(g))
				}
			}
		}
		at += 4 + size
	}
	return groups, shares
}

// The end-to-end test runs official servers from SHIKOO_E2E_BIN, unpacked, never installed:
// mihomo (v1.19.32 release), sing-box (1.14.3 release), and usr/sbin/openvpn and usr/sbin/sshd from Ubuntu's
// openvpn and openssh-server packages (apt-get download, dpkg -x) with their libraries under usr/lib.
// OpenVPN needs root for its tun; sshd runs as nobody, so it takes keys only.
func TestSingBoxEndToEnd(t *testing.T) {
	bin := os.Getenv("SHIKOO_E2E_BIN")
	if bin == "" {
		t.Skip("SHIKOO_E2E_BIN names the folder of the official servers")
	}
	var hookMu sync.Mutex
	var hooked []string
	previous := dialer.DefaultSocketHook
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		hookMu.Lock()
		defer hookMu.Unlock()
		hooked = append(hooked, network+" "+address)
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = previous })
	freshHook := func() {
		hookMu.Lock()
		defer hookMu.Unlock()
		hooked = nil
	}
	sawHook := func(t *testing.T, want string) {
		t.Helper()
		hookMu.Lock()
		defer hookMu.Unlock()
		for _, h := range hooked {
			if strings.Contains(h, want) {
				return
			}
		}
		t.Errorf("no socket to %q went through mihomo's socket hook: %v", want, hooked)
	}
	host := e2eHostIP(t)
	echo := e2eEcho(t)
	uuid := "4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11"

	t.Run("VLESS REALITY against mihomo v1.19.32", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		dest := e2eTLS(t)
		private, public := x25519(t, base64.RawURLEncoding)
		port := e2ePort(t)
		e2eFile(t, dir, "config.yaml", fmt.Sprintf(`mode: direct
log-level: debug
listeners:
  - {name: reality-in, type: vless, listen: 127.0.0.1, port: %d, users: [{username: u, uuid: %s, flow: xtls-rprx-vision}],
     reality-config: {dest: %q, private-key: %s, short-id: ["0123abcd"], server-names: [reality.test]}}
`, port, uuid, dest, private))
		e2eRun(t, dir, filepath.Join(bin, "mihomo"), "-d", dir)
		e2eWait(t, port)
		proxy := e2eThrough(t, fmt.Sprintf(`{name: r, type: vless, server: 127.0.0.1, port: %d, uuid: %s, tls: true, udp: true,
  flow: xtls-rprx-vision, servername: reality.test, client-fingerprint: chrome,
  reality-opts: {public-key: %s, short-id: 0123abcd}}`, port, uuid, public), "127.0.0.1", echo)
		sawHook(t, fmt.Sprintf("127.0.0.1:%d", port))

		page := e2eHTTP(t)
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if delay, err := proxy.URLTest(ctx, page, nil); err != nil || delay == 0 {
			t.Errorf("ping through sing-box: %d ms, %v", delay, err)
		}
		e2eLog(t, dir, "REALITY")
	})

	t.Run("a dead server fails its ping, so the app sees failed", func(t *testing.T) {
		_, public := x25519(t, base64.RawURLEncoding)
		cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: dead, type: vless, server: 127.0.0.1, port: %d, uuid: %s, tls: true, servername: reality.test,
     client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 0123abcd}, shikoo-core: singBox}
`, e2ePort(t), uuid, public))
		t.Cleanup(e2eStop)
		if cfg.Proxies["dead"].Type() != C.Socks5 {
			t.Fatal("sing-box did not take the server")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if delay, err := cfg.Proxies["dead"].URLTest(ctx, e2eHTTP(t), nil); err == nil {
			t.Fatalf("a ping through sing-box to a closed port answered in %d ms", delay)
		} else {
			t.Logf("ping error: %v", err)
		}
	})

	t.Run("WireGuard against sing-box 1.14.3, server by name, TCP and UDP", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		serverPrivate, serverPublic := x25519(t, base64.StdEncoding)
		clientPrivate, clientPublic := x25519(t, base64.StdEncoding)
		port := e2ePort(t)
		e2eFile(t, dir, "config.json", fmt.Sprintf(`{"log": {"level": "warn"},
  "endpoints": [{"type": "wireguard", "tag": "wg", "listen_port": %d, "address": ["10.66.0.1/24"], "private_key": %q,
    "peers": [{"public_key": %q, "allowed_ips": ["10.66.0.2/32"]}]}],
  "outbounds": [{"type": "direct", "tag": "direct"}], "route": {"final": "direct"}}`, port, serverPrivate, clientPublic))
		e2eRun(t, dir, filepath.Join(bin, "sing-box"), "run", "-c", filepath.Join(dir, "config.json"))
		time.Sleep(time.Second)
		names := e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"wg.shikoo.test.": "127.0.0.1"})
		e2eNames(t, &resolver.DefaultResolver, nil)

		proxy := e2eThrough(t, fmt.Sprintf(`{name: w, type: wireguard, server: wg.shikoo.test, port: %d, ip: 10.66.0.2,
  private-key: %q, public-key: %q, udp: true, mtu: 1280}`, port, clientPrivate, serverPublic), host, echo)
		if len(*names) == 0 {
			t.Error("sing-box resolved the server's name without mihomo's proxy-server resolver")
		}
		sawHook(t, "udp")

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		target := e2eTarget(host, echo)
		target.NetWork = C.UDP
		packets, err := proxy.ListenPacketContext(ctx, target)
		if err != nil {
			t.Fatalf("UDP through sing-box: %v", err)
		}
		defer packets.Close()
		to := net.UDPAddrFromAddrPort(netip.AddrPortFrom(netip.MustParseAddr(host), echo))
		if _, err := packets.WriteTo([]byte("shikoo"), to); err != nil {
			t.Fatal(err)
		}
		packets.SetReadDeadline(time.Now().Add(5 * time.Second))
		buf := make([]byte, 64)
		if n, _, err := packets.ReadFrom(buf); err != nil || string(buf[:n]) != "shikoo" {
			t.Fatalf("UDP echo %q, %v", buf[:n], err)
		}

		// mihomo's single peer ignores allowed-ips, and sends to an IPv6 address while ipv6 is off, the app's default.
		e2eThrough(t, fmt.Sprintf(`{name: w, type: wireguard, server: wg.shikoo.test, port: %d, ip: 10.66.0.2,
  private-key: %q, public-key: %q, udp: true, allowed-ips: ["10.0.0.0/8"]}`, port, clientPrivate, serverPublic), host, echo)
		disabled := resolver.DisableIPv6
		resolver.DisableIPv6 = true
		t.Cleanup(func() { resolver.DisableIPv6 = disabled })
		e2eThrough(t, fmt.Sprintf(`{name: w, type: wireguard, server: "::1", port: %d, ip: 10.66.0.2,
  private-key: %q, public-key: %q, udp: true}`, port, clientPrivate, serverPublic), host, echo)
	})

	t.Run("OpenVPN against OpenVPN 2.6, tls-auth and a password", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		ca := e2ePKI(t, dir)
		e2eFile(t, dir, "check.sh", "#!/bin/sh\n[ \"$(sed -n 1p \"$1\")\" = shikoo ] && [ \"$(sed -n 2p \"$1\")\" = test-pass ]\n")
		os.Chmod(filepath.Join(dir, "check.sh"), 0o755)
		openvpn := filepath.Join(bin, "usr/sbin/openvpn")
		if out, err := e2eCommand(bin, openvpn, "--genkey", "secret", filepath.Join(dir, "ta.key")).CombinedOutput(); err != nil {
			t.Fatalf("genkey: %v %s", err, out)
		}
		port := e2ePort(t)
		e2eFile(t, dir, "server.conf", fmt.Sprintf(`dev sbxtun
dev-type tun
proto udp4
local 127.0.0.1
port %d
server 10.89.0.0 255.255.255.0
topology subnet
ca %[2]s/ca.crt
cert %[2]s/server.crt
key %[2]s/server.key
dh none
tls-auth %[2]s/ta.key 0
auth SHA256
verify-client-cert none
username-as-common-name
script-security 2
auth-user-pass-verify %[2]s/check.sh via-file
tmp-dir %[2]s
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
verb 3
`, port, dir))
		e2eRun(t, dir, openvpn, "--config", filepath.Join(dir, "server.conf"))
		time.Sleep(2 * time.Second)
		taKey, _ := os.ReadFile(filepath.Join(dir, "ta.key"))
		e2eThrough(t, fmt.Sprintf(`{name: o, type: openvpn, server: 127.0.0.1, port: %d, proto: udp, ca: %q, username: shikoo,
  password: test-pass, tls-auth: %q, key-direction: "1", auth: SHA256}`, port, ca, taKey), host, echo)
		sawHook(t, "udp")
		e2eThrough(t, fmt.Sprintf(`{name: o, type: openvpn, server: 127.0.0.1, port: %d, proto: udp, ca: %q, username: shikoo,
  password: test-pass, tls-auth: %q, key-direction: "1", comp-lzo: "no"}`, port, ca, taKey), host, echo)
		e2eLog(t, dir, "Peer Connection Initiated")
	})

	t.Run("SSH against OpenSSH sshd, a password and a key", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		hostPublic, hostKey := e2eSSHKey(t)
		clientPublic, clientKey := e2eSSHKey(t)
		hash, err := exec.Command("openssl", "passwd", "-6", "test-pass").Output()
		if err != nil {
			t.Fatal(err)
		}
		port := e2ePort(t)
		e2eFile(t, dir, "host_key", hostKey)
		e2eFile(t, dir, "authorized_keys", clientPublic)
		for _, path := range []string{filepath.Dir(dir), dir, filepath.Join(dir, "authorized_keys")} {
			os.Chmod(path, 0o755) // sshd reads the keys as the user
		}
		// sshd wants its privsep user "sshd" and an unlocked account; both exist only in its own mount namespace.
		e2eFile(t, dir, "passwd", "root:x:0:0::/root:/bin/sh\nsshd:x:65534:65534::/run/sshd:/usr/sbin/nologin\n"+
			"shikoo:x:65534:65534::/tmp:/bin/sh\n")
		e2eFile(t, dir, "shadow", "shikoo:"+strings.TrimSpace(string(hash))+":20000:0:99999:7:::\n")
		e2eFile(t, dir, "sshd_config", fmt.Sprintf(`Port %d
ListenAddress 127.0.0.1
HostKey %[2]s/host_key
PidFile %[2]s/sshd.pid
AuthorizedKeysFile %[2]s/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication yes
AllowTcpForwarding yes
`, port, dir))
		e2eRun(t, dir, "unshare", "--mount", "--propagation", "private", "sh", "-c", fmt.Sprintf(
			"mount --bind %[1]s/passwd /etc/passwd && mount --bind %[1]s/shadow /etc/shadow && "+
				"mount -t tmpfs tmpfs /run && mkdir /run/sshd && exec %[2]s -D -e -f %[1]s/sshd_config",
			dir, filepath.Join(bin, "usr/sbin/sshd")))
		e2eWait(t, port)
		e2eThrough(t, fmt.Sprintf(`{name: s, type: ssh, server: 127.0.0.1, port: %d, username: shikoo, password: test-pass,
  host-key: [%q]}`, port, strings.TrimSpace(hostPublic)), "127.0.0.1", echo)
		sawHook(t, fmt.Sprintf("127.0.0.1:%d", port))
		e2eThrough(t, fmt.Sprintf(`{name: s, type: ssh, server: 127.0.0.1, port: %d, username: shikoo, private-key: %q}`,
			port, clientKey), "127.0.0.1", echo)
		e2eLog(t, dir, "Accepted")
	})
}

func e2eStop() {
	for _, stop := range shikooCoresStarting {
		stop()
	}
	shikooCoresStarting = nil
}

// e2eThrough marks the mapping for sing-box, checks mihomo now holds a SOCKS5 in its place, and echoes once through it.
func e2eThrough(t *testing.T, mapping, ip string, port uint16) C.Proxy {
	t.Helper()
	cfg := parseShikooCores(t, "proxies:\n  - "+strings.ReplaceAll(strings.TrimSuffix(mapping, "}"), "\n", " ")+
		", shikoo-core: singBox}\n")
	t.Cleanup(e2eStop)
	var proxy C.Proxy
	for _, p := range cfg.Proxies {
		if p.Type() == C.Socks5 {
			proxy = p
		}
	}
	if proxy == nil {
		t.Fatal("sing-box did not take the server")
	}
	// OpenVPN refuses connections until its handshake is done, and WireGuard's first packet starts one.
	var err error
	for deadline := time.Now().Add(15 * time.Second); time.Now().Before(deadline); time.Sleep(300 * time.Millisecond) {
		if err = e2eEchoOnce(proxy, ip, port); err == nil {
			return proxy
		}
	}
	t.Fatalf("echo through sing-box: %v", err)
	return proxy
}

func e2eEchoOnce(proxy C.Proxy, ip string, port uint16) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := proxy.DialContext(ctx, e2eTarget(ip, port))
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("shikoo")); err != nil {
		return err
	}
	buf := make([]byte, 6)
	if _, err := conn.Read(buf); err != nil || string(buf) != "shikoo" {
		return fmt.Errorf("echo %q, %v", buf, err)
	}
	return nil
}

func e2eTarget(ip string, port uint16) *C.Metadata {
	return &C.Metadata{NetWork: C.TCP, DstIP: netip.MustParseAddr(ip), DstPort: port}
}

func e2eEcho(t *testing.T) uint16 {
	t.Helper()
	tcp, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		t.Fatal(err)
	}
	port := uint16(tcp.Addr().(*net.TCPAddr).Port)
	udp, err := net.ListenPacket("udp", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { tcp.Close(); udp.Close() })
	go func() {
		for {
			conn, err := tcp.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				buf := make([]byte, 64)
				n, _ := conn.Read(buf)
				conn.Write(buf[:n])
			}()
		}
	}()
	go func() {
		buf := make([]byte, 64)
		for {
			n, from, err := udp.ReadFrom(buf)
			if err != nil {
				return
			}
			udp.WriteTo(buf[:n], from)
		}
	}()
	return port
}

func e2eHTTP(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})}
	go server.Serve(listener)
	t.Cleanup(func() { server.Close() })
	return "http://" + listener.Addr().String() + "/"
}

// e2eTLS is REALITY's dest: a TLS 1.3 server the REALITY server borrows its handshake from.
func e2eTLS(t *testing.T) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), DNSNames: []string{"reality.test"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{MinVersion: tls.VersionTLS13,
		Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go http.Serve(listener, http.NotFoundHandler())
	return listener.Addr().String()
}

// e2ePKI writes a CA and a server certificate for OpenVPN into dir, and returns the CA in PEM.
func e2ePKI(t *testing.T, dir string) string {
	t.Helper()
	write := func(name string, block *pem.Block) string {
		data := pem.EncodeToMemory(block)
		e2eFile(t, dir, name, string(data))
		return string(data)
	}
	issue := func(template, parent *x509.Certificate, signer *ecdsa.PrivateKey) (*x509.Certificate, *ecdsa.PrivateKey, []byte) {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		if signer == nil {
			signer = key
		}
		der, err := x509.CreateCertificate(rand.Reader, template, parent, &key.PublicKey, signer)
		if err != nil {
			t.Fatal(err)
		}
		cert, _ := x509.ParseCertificate(der)
		return cert, key, der
	}
	caTemplate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "shikoo-test-ca"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour), IsCA: true,
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	caCert, caKey, caDER := issue(caTemplate, caTemplate, nil)
	ca := write("ca.crt", &pem.Block{Type: "CERTIFICATE", Bytes: caDER})
	_, serverKey, serverDER := issue(&x509.Certificate{SerialNumber: big.NewInt(2),
		Subject: pkix.Name{CommonName: "shikoo-test-server"}, NotBefore: time.Now().Add(-time.Hour),
		NotAfter: time.Now().Add(24 * time.Hour), KeyUsage: x509.KeyUsageDigitalSignature,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}, caCert, caKey)
	write("server.crt", &pem.Block{Type: "CERTIFICATE", Bytes: serverDER})
	der, _ := x509.MarshalECPrivateKey(serverKey)
	write("server.key", &pem.Block{Type: "EC PRIVATE KEY", Bytes: der})
	return ca
}

func e2eSSHKey(t *testing.T) (authorized, private string) {
	t.Helper()
	public, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(key, "")
	if err != nil {
		t.Fatal(err)
	}
	sshPublic, _ := ssh.NewPublicKey(public)
	return string(ssh.MarshalAuthorizedKey(sshPublic)), string(pem.EncodeToMemory(block))
}

// e2eNames points one of mihomo's resolvers at fixed answers and records each name asked.
func e2eNames(t *testing.T, at *resolver.Resolver, answers map[string]string) *[]string {
	t.Helper()
	previous := *at
	fake := &fakeResolver{answers: answers}
	*at = fake
	t.Cleanup(func() { *at = previous })
	return &fake.asked
}

type fakeResolver struct {
	answers map[string]string
	mu      sync.Mutex
	asked   []string
}

func (f *fakeResolver) ask(name string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.asked = append(f.asked, name)
}

func (f *fakeResolver) ExchangeContext(_ context.Context, m *mDNS.Msg) (*mDNS.Msg, error) {
	f.ask(m.Question[0].Name)
	reply := new(mDNS.Msg)
	reply.SetReply(m)
	q := m.Question[0]
	for _, ip := range strings.Fields(f.answers[q.Name]) {
		if kind := map[bool]uint16{true: mDNS.TypeA, false: mDNS.TypeAAAA}[strings.Contains(ip, ".")]; kind == q.Qtype {
			rr, _ := mDNS.NewRR(q.Name + " 60 IN " + mDNS.TypeToString[kind] + " " + ip)
			reply.Answer = append(reply.Answer, rr)
		}
	}
	return reply, nil
}

// LookupIP answers a literal as itself and a name from answers (space-separated), as mihomo's dialer asks it.
func (f *fakeResolver) LookupIP(_ context.Context, host string) ([]netip.Addr, error) {
	if ip, err := netip.ParseAddr(host); err == nil {
		return []netip.Addr{ip}, nil
	}
	f.ask(host + ".")
	var ips []netip.Addr
	for _, ip := range strings.Fields(f.answers[host+"."]) {
		ips = append(ips, netip.MustParseAddr(ip))
	}
	if len(ips) == 0 {
		return nil, errors.New("fake: no answer")
	}
	return ips, nil
}
func (f *fakeResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	ips, err := f.LookupIP(ctx, host)
	if ips = slices.DeleteFunc(ips, func(ip netip.Addr) bool { return !ip.Is4() }); err == nil && len(ips) == 0 {
		return nil, resolver.ErrIPVersion // as mihomo's own resolver answers an IPv6 address
	}
	return ips, err
}
func (f *fakeResolver) LookupIPv6(context.Context, string) ([]netip.Addr, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) ResolveECH(context.Context, string) ([]byte, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) Invalid() bool    { return true }
func (f *fakeResolver) ClearCache()      {}
func (f *fakeResolver) ResetConnection() {}

func e2eHostIP(t *testing.T) string {
	t.Helper()
	addresses, _ := net.InterfaceAddrs()
	for _, address := range addresses {
		if prefix, err := netip.ParsePrefix(address.String()); err == nil && prefix.Addr().Is4() &&
			!prefix.Addr().IsLoopback() && !strings.HasPrefix(prefix.Addr().String(), "10.") {
			return prefix.Addr().String()
		}
	}
	t.Skip("no outside address to reach through a tunnel")
	return ""
}

func e2ePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func e2eWait(t *testing.T, port int) {
	t.Helper()
	for i := 0; i < 50; i++ {
		if conn, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port)); err == nil {
			conn.Close()
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("nothing listens on %d", port)
}

func e2eFile(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func e2eCommand(bin, name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.Env = append(os.Environ(), "LD_LIBRARY_PATH="+filepath.Join(bin, "usr/lib/x86_64-linux-gnu")+":"+
		filepath.Join(bin, "lib/x86_64-linux-gnu"))
	return cmd
}

// e2eRun starts a server whose output goes to dir/server.log, which e2eLog prints.
func e2eRun(t *testing.T, dir, name string, args ...string) {
	t.Helper()
	logFile, err := os.Create(filepath.Join(dir, "server.log"))
	if err != nil {
		t.Fatal(err)
	}
	cmd := e2eCommand(os.Getenv("SHIKOO_E2E_BIN"), name, args...)
	cmd.Stdout, cmd.Stderr = logFile, logFile
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill()
		cmd.Wait()
		logFile.Close()
	})
}

// e2eLog prints the server's lines that hold want, as evidence that it saw the client.
func e2eLog(t *testing.T, dir, want string) {
	t.Helper()
	content, _ := os.ReadFile(filepath.Join(dir, "server.log"))
	for _, line := range strings.Split(string(content), "\n") {
		if strings.Contains(line, want) {
			t.Log(line)
		}
	}
}

// The lookup reaches the only server that knows probe.test through the tunnel: Xray's WireGuard server redirects UDP 53
// to it, and mihomo, whose resolver sing-box would otherwise ask, has none in this test.
func TestSingBoxResolvesAWireGuardServersNamesThroughIt(t *testing.T) {
	ip := outsideIP(t)
	var queries, hits atomic.Int32
	dnsConn, err := net.ListenPacket("udp", net.JoinHostPort(ip, "0"))
	if err != nil {
		t.Fatal(err)
	}
	dnsServer := &mDNS.Server{PacketConn: dnsConn, Handler: mDNS.HandlerFunc(func(w mDNS.ResponseWriter, r *mDNS.Msg) {
		queries.Add(1)
		answer := new(mDNS.Msg)
		answer.SetReply(r)
		if q := r.Question[0]; q.Name == "probe.test." && q.Qtype == mDNS.TypeA {
			answer.Answer = []mDNS.RR{&mDNS.A{Hdr: mDNS.RR_Header{Name: q.Name, Rrtype: mDNS.TypeA, Class: mDNS.ClassINET,
				Ttl: 60}, A: net.ParseIP(ip)}}
		}
		_ = w.WriteMsg(answer)
	})}
	go func() { _ = dnsServer.ActivateAndServe() }()
	t.Cleanup(func() { _ = dnsServer.Shutdown() })
	target := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNoContent)
	})}
	listener, err := net.Listen("tcp", net.JoinHostPort(ip, "0"))
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = target.Serve(listener) }()
	t.Cleanup(func() { _ = target.Close() })

	serverWG, clientWG := wgPair(t), wgPair(t)
	port, err := freeLoopbackPort()
	if err != nil {
		t.Fatal(err)
	}
	allow := map[string]any{"finalRules": []any{map[string]any{"action": "allow"}}}
	server, err := json.Marshal(map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{"listen": "127.0.0.1", "port": port, "protocol": "wireguard", "settings": map[string]any{
			"secretKey": serverWG.private, "mtu": 1420,
			"peers": []any{map[string]any{"publicKey": clientWG.public, "allowedIPs": []string{"10.9.0.2/32"}}},
		}}},
		"outbounds": []any{
			map[string]any{"tag": "direct", "protocol": "freedom", "settings": allow},
			map[string]any{"tag": "dns", "protocol": "freedom", "settings": map[string]any{
				"redirect": dnsConn.LocalAddr().String(), "finalRules": allow["finalRules"]}},
		},
		"routing": map[string]any{"rules": []any{map[string]any{"network": "udp", "port": "53", "outboundTag": "dns"}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	instance, err := xcore.StartInstance("json", server)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = instance.Close() })

	previous := resolver.DefaultResolver
	resolver.DefaultResolver = nil
	t.Cleanup(func() { resolver.DefaultResolver = previous })
	cfg := parseShikooCores(t, fmt.Sprintf(`
proxies:
  - {name: wg dns, type: wireguard, server: 127.0.0.1, port: %d, ip: 10.9.0.2, private-key: %q, public-key: %q, udp: true, remote-dns-resolve: true, dns: [1.1.1.1, 8.8.8.8], shikoo-core: singBox}
`, port, clientWG.private, serverWG.public))
	shikooCoresCommit()
	t.Cleanup(func() {
		for _, stop := range shikooCoresRunning {
			stop()
		}
		shikooCoresRunning = nil
	})

	proxy := cfg.Proxies["wg dns"]
	if proxy.Type() != C.Socks5 {
		t.Fatalf("wg dns is %v, want the SOCKS in front of sing-box", proxy.Type())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, targetPort, _ := net.SplitHostPort(listener.Addr().String())
	delay, err := proxy.URLTest(ctx, "http://probe.test:"+targetPort+"/generate_204", anyDelayTestStatus)
	if err != nil || delay == 0 || hits.Load() == 0 {
		t.Fatalf("probe.test through sing-box: delay %d, err %v, target hits %d", delay, err, hits.Load())
	}
	if queries.Load() == 0 {
		t.Fatal("the name was resolved without the DNS server behind the WireGuard server")
	}
}

// A relay's name with an IPv4 address forwarding to the server and an IPv6 one on the relay, whose own server takes the
// same keys: mihomo dials the IPv4 one, and sing-box handshook both and kept the nearer's answer, leaving from the relay.
func TestSingBoxDialsTheAddressMihomoWouldForAWireGuardServersName(t *testing.T) {
	relay, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	if probe, err := net.ListenPacket("udp", "[::1]:0"); err != nil {
		t.Skip("no IPv6 loopback")
	} else {
		_ = probe.Close()
	}
	port, far := relay.LocalAddr().(*net.UDPAddr).Port, freeUDPPort(t)
	serverWG, clientWG := wgPair(t), wgPair(t)
	wgServers(t, serverWG, clientWG, map[string]string{"relay": fmt.Sprintf("[::1]:%d", port),
		"server": fmt.Sprintf("127.0.0.1:%d", far)})
	go udpRelay(relay, fmt.Sprintf("127.0.0.1:%d", far), 100*time.Millisecond)
	e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"wg.shikoo.test.": "127.0.0.1 ::1"})
	if exit := wgExit(singBoxWG(t, port, clientWG, serverWG)); exit != "server" {
		t.Fatalf("the tunnel left from %q, want the server mihomo dials", exit)
	}
}

// The profile's hosts pin the name to one server and DNS answers another with the same keys: sing-box asked DNS.
func TestSingBoxWireGuardServersNameFollowsMihomosHosts(t *testing.T) {
	port := freeUDPPort(t)
	serverWG, clientWG := wgPair(t), wgPair(t)
	wgServers(t, serverWG, clientWG, map[string]string{"pinned": fmt.Sprintf("127.0.0.1:%d", port),
		"dns": fmt.Sprintf("127.0.0.2:%d", port)})
	e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"wg.shikoo.test.": "127.0.0.2"})
	pinned := trie.New[resolver.HostValue]()
	value, _ := resolver.NewHostValueByIPs([]netip.Addr{netip.MustParseAddr("127.0.0.1")})
	_ = pinned.Insert("wg.shikoo.test", value)
	previous := resolver.DefaultHosts
	resolver.DefaultHosts = resolver.NewHosts(pinned)
	t.Cleanup(func() { resolver.DefaultHosts = previous })
	if exit := wgExit(singBoxWG(t, port, clientWG, serverWG)); exit != "pinned" {
		t.Fatalf("the tunnel left from %q, want the server mihomo's hosts name", exit)
	}
}

// Two IPv4 addresses for a name: sing-box handshook both at each attempt and rekey, so the exit could move mid-session.
func TestSingBoxWireGuardKeepsOneAddressOfAName(t *testing.T) {
	var hits [2]atomic.Int32
	port := 0
	for i, ip := range []string{"127.0.0.1", "127.0.0.2"} {
		conn, err := net.ListenPacket("udp", net.JoinHostPort(ip, strconv.Itoa(port)))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close() })
		port = conn.LocalAddr().(*net.UDPAddr).Port
		go func() {
			for buf := make([]byte, 2048); ; hits[i].Add(1) {
				if _, _, err := conn.ReadFrom(buf); err != nil {
					return
				}
			}
		}()
	}
	e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"wg.shikoo.test.": "127.0.0.1 127.0.0.2"})
	client, server := wgPair(t), wgPair(t)
	out, _, _, err := singBoxConvert(context.Background(), map[string]any{"name": "wg", "type": "wireguard",
		"server": "wg.shikoo.test", "port": port, "ip": "10.9.0.2", "private-key": client.private,
		"public-key": server.public})
	if err != nil {
		t.Fatal(err)
	}
	if address := out["peers"].([]any)[0].(map[string]any)["address"]; !isIP(fmt.Sprint(address)) {
		t.Fatalf("sing-box gets %v, a name it resolves again at each rekey", address)
	}
	proxy := singBoxWG(t, port, client, server)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	go func() {
		if conn, err := proxy.DialContext(ctx, e2eTarget("203.0.113.7", 80)); err == nil {
			_ = conn.Close()
		}
	}()
	for ctx.Err() == nil && max(hits[0].Load(), hits[1].Load()) < 2 {
		time.Sleep(100 * time.Millisecond)
	}
	if a, b := hits[0].Load(), hits[1].Load(); min(a, b) != 0 || max(a, b) < 2 {
		t.Fatalf("handshakes to 127.0.0.1: %d, to 127.0.0.2: %d; want one address, again at the retry", a, b)
	}
}

// A dead DNS: the apply, which holds configMu, waited a whole DNS timeout per name. An unresolved name stays on mihomo.
func TestSingBoxResolvesWireGuardNamesAtOnceAndLeavesTheUnresolvedToMihomo(t *testing.T) {
	timeout, previous := resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver
	resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver = 300*time.Millisecond, deadResolver{&fakeResolver{}}
	t.Cleanup(func() { resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver = timeout, previous })
	client, server := wgPair(t), wgPair(t)
	yaml := "proxies:\n"
	for i := range 4 {
		yaml += fmt.Sprintf("  - {name: wg%d, type: wireguard, server: wg%[1]d.shikoo.test, port: 51820, ip: 10.9.0.2, "+
			"private-key: %q, public-key: %q, udp: true, shikoo-core: singBox}\n", i, client.private, server.public)
	}
	start := time.Now()
	cfg := parseShikooCores(t, yaml)
	t.Cleanup(e2eStop)
	if took := time.Since(start); took > 2*resolver.DefaultDNSTimeout {
		t.Errorf("the apply took %v, one DNS timeout is %v", took, resolver.DefaultDNSTimeout)
	}
	for i := range 4 {
		if kind := cfg.Proxies[fmt.Sprintf("wg%d", i)].Type(); kind != C.WireGuard {
			t.Errorf("wg%d is %v, want mihomo's own WireGuard", i, kind)
		}
	}
}

func TestSingBoxWireGuardNamesAfterUnresolvedOnesStillGoToSingBox(t *testing.T) {
	timeout, previous := resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver
	resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver = 300*time.Millisecond, deadResolver{&fakeResolver{
		answers: map[string]string{"ok1.shikoo.test.": "127.0.0.1", "ok2.shikoo.test.": "127.0.0.1"}}}
	t.Cleanup(func() { resolver.DefaultDNSTimeout, resolver.ProxyServerHostResolver = timeout, previous })
	client, server := wgPair(t), wgPair(t)
	yaml := "proxies:\n"
	for _, name := range []string{"hang1", "hang2", "ok1", "ok2"} {
		yaml += fmt.Sprintf("  - {name: %s, type: wireguard, server: %[1]s.shikoo.test, port: 51820, ip: 10.9.0.2, "+
			"private-key: %q, public-key: %q, udp: true, shikoo-core: singBox}\n", name, client.private, server.public)
	}
	cfg := parseShikooCores(t, yaml)
	t.Cleanup(e2eStop)
	for name, want := range map[string]C.AdapterType{"hang1": C.WireGuard, "hang2": C.WireGuard, "ok1": C.Socks5,
		"ok2": C.Socks5} {
		if kind := cfg.Proxies[name].Type(); kind != want {
			t.Errorf("%s is %v, want %v", name, kind, want)
		}
	}
}

// deadResolver never answers a name its fakeResolver has none for, and as a real resolver none past the caller's deadline.
type deadResolver struct{ *fakeResolver }

func (r deadResolver) LookupIP(ctx context.Context, host string) ([]netip.Addr, error) {
	if r.answers[host+"."] == "" {
		<-ctx.Done()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return r.fakeResolver.LookupIP(ctx, host)
}
func (r deadResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	return r.LookupIP(ctx, host)
}

func TestSingBoxWireGuardNameFollowsMihomosIPv6(t *testing.T) {
	e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"both.test.": "127.0.0.1 ::1", "six.test.": "::1"})
	disabled := resolver.DisableIPv6
	t.Cleanup(func() { resolver.DisableIPv6 = disabled })
	for _, c := range []struct {
		name string
		ipv6 bool
		want string
	}{{"both.test", false, "127.0.0.1"}, {"both.test", true, "127.0.0.1"}, {"six.test", true, "::1"}, {"six.test", false, ""}} {
		resolver.DisableIPv6 = !c.ipv6
		out, _, _, err := singBoxConvert(context.Background(), map[string]any{"name": "wg", "type": "wireguard",
			"server": c.name, "port": 1, "ip": "10.9.0.2", "private-key": "k", "public-key": "p"})
		got := ""
		if err == nil {
			got = fmt.Sprint(out["peers"].([]any)[0].(map[string]any)["address"])
		}
		if got != c.want {
			t.Errorf("%s with mihomo's IPv6 on %v: %q, want %q", c.name, c.ipv6, got, c.want)
		}
	}
}

// singBoxWG hands one WireGuard server by name to sing-box; the tunnel's resolver knows no name.
func singBoxWG(t *testing.T, port int, client, server wgKeys) C.Proxy {
	t.Helper()
	e2eNames(t, &resolver.DefaultResolver, nil)
	cfg := parseShikooCores(t, fmt.Sprintf(`
proxies:
  - {name: wg, type: wireguard, server: wg.shikoo.test, port: %d, ip: 10.9.0.2, private-key: %q, public-key: %q, udp: true, shikoo-core: singBox}
`, port, client.private, server.public))
	t.Cleanup(e2eStop)
	if cfg.Proxies["wg"].Type() != C.Socks5 {
		t.Fatalf("wg is %v, want the SOCKS in front of sing-box", cfg.Proxies["wg"].Type())
	}
	return cfg.Proxies["wg"]
}

// wgServers starts a WireGuard server per address, same keys, each answering every connection with its own name.
func wgServers(t *testing.T, server, client wgKeys, at map[string]string) {
	t.Helper()
	allow := []any{map[string]any{"action": "allow"}}
	var inbounds, outbounds, rules []any
	for name, address := range at {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = listener.Close() })
		go func() {
			for conn, err := listener.Accept(); err == nil; conn, err = listener.Accept() {
				_, _ = conn.Write([]byte(name))
				_ = conn.Close()
			}
		}()
		ip, port, _ := net.SplitHostPort(address)
		number, _ := strconv.Atoi(port)
		inbounds = append(inbounds, map[string]any{"tag": name, "listen": ip, "port": number, "protocol": "wireguard",
			"settings": map[string]any{"secretKey": server.private, "mtu": 1420,
				"peers": []any{map[string]any{"publicKey": client.public, "allowedIPs": []string{"10.9.0.2/32"}}}}})
		outbounds = append(outbounds, map[string]any{"tag": name, "protocol": "freedom",
			"settings": map[string]any{"redirect": listener.Addr().String(), "finalRules": allow}})
		rules = append(rules, map[string]any{"inboundTag": []string{name}, "outboundTag": name})
	}
	config, err := json.Marshal(map[string]any{"log": map[string]any{"loglevel": "warning"}, "inbounds": inbounds,
		"outbounds": outbounds, "routing": map[string]any{"rules": rules}})
	if err != nil {
		t.Fatal(err)
	}
	instance, err := xcore.StartInstance("json", config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = instance.Close() })
}

// wgExit is the name of the server the tunnel leaves from, "" if none answers.
func wgExit(proxy C.Proxy) string {
	for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		conn, err := proxy.DialContext(ctx, e2eTarget("203.0.113.7", 80))
		cancel()
		if err == nil {
			_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
			answer, _ := io.ReadAll(conn)
			_ = conn.Close()
			if len(answer) > 0 {
				return string(answer)
			}
		}
	}
	return ""
}

// udpRelay forwards one client's datagrams to `to` and back, each after delay: a relay in front of a farther server.
func udpRelay(relay net.PacketConn, to string, delay time.Duration) {
	upstream, err := net.Dial("udp", to)
	if err != nil {
		return
	}
	defer upstream.Close()
	var client atomic.Pointer[net.Addr]
	go func() {
		for buf := make([]byte, 65535); ; {
			n, err := upstream.Read(buf)
			if err != nil {
				return
			}
			packet := slices.Clone(buf[:n])
			time.AfterFunc(delay, func() { _, _ = relay.WriteTo(packet, *client.Load()) })
		}
	}()
	for buf := make([]byte, 65535); ; {
		n, from, err := relay.ReadFrom(buf)
		if err != nil {
			return
		}
		client.Store(&from)
		packet := slices.Clone(buf[:n])
		time.AfterFunc(delay, func() { _, _ = upstream.Write(packet) })
	}
}
