package main

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/constant"
	xcore "github.com/xtls/xray-core/core"
)

const xrayTestUUID = "b831381d-6324-4d53-ad4f-8cda48b30811"

func TestXrayOutboundConvertsWhatThePanelSends(t *testing.T) {
	reality := map[string]any{
		"name": "r", "type": "vless", "server": "1.2.3.4", "port": 443, "uuid": xrayTestUUID,
		"flow": "xtls-rprx-vision", "tls": true, "servername": "www.example.com", "client-fingerprint": "chrome",
		"reality-opts": map[string]any{"public-key": base64.RawURLEncoding.EncodeToString(make([]byte, 32)), "short-id": "6ba85179e30d4fc2"},
	}
	cases := []struct {
		name  string
		proxy map[string]any
		want  map[string]string
	}{
		{"reality on raw", reality, map[string]string{
			"network": "raw", "security": "reality", "reality.serverName": "www.example.com", "reality.shortId": "6ba85179e30d4fc2",
		}},
		{"xhttp over reality", with(reality, map[string]any{
			"flow": "", "network": "xhttp",
			"xhttp-opts": map[string]any{
				"path": "/x", "host": "cdn.example.com", "mode": "packet-up", "x-padding-bytes": "100-200",
				"reuse-settings": map[string]any{"max-concurrency": "16-32", "h-keep-alive-period": 30},
			},
		}), map[string]string{
			"network": "xhttp", "security": "reality", "xhttp.path": "/x", "xhttp.host": "cdn.example.com",
			"xhttp.mode": "packet-up", "xhttp.xPaddingBytes": "100-200", "xhttp.xmux": `{"hKeepAlivePeriod":30,"maxConcurrency":"16-32"}`,
		}},
		{"tls on ws with early data", map[string]any{
			"name": "w", "type": "vless", "server": "cdn.example.com", "port": 443, "uuid": xrayTestUUID,
			"tls": true, "servername": "cdn.example.com", "alpn": []any{"http/1.1"}, "network": "ws",
			"ws-opts": map[string]any{
				"path": "/ws", "headers": map[string]any{"Host": "cdn.example.com", "X-A": "b"},
				"max-early-data": 2048, "early-data-header-name": "Sec-WebSocket-Protocol",
			},
		}, map[string]string{
			"network": "ws", "security": "tls", "ws.path": "/ws?ed=2048", "ws.host": "cdn.example.com",
			"ws.headers": `{"X-A":"b"}`, "tls.alpn": `["http/1.1"]`,
		}},
		{"httpupgrade", map[string]any{
			"name": "u", "type": "vless", "server": "cdn.example.com", "port": 443, "uuid": xrayTestUUID, "tls": true,
			"network": "ws", "ws-opts": map[string]any{"path": "/up", "v2ray-http-upgrade": true},
		}, map[string]string{"network": "httpupgrade", "httpupgrade.path": "/up"}},
		{"grpc", map[string]any{
			"name": "g", "type": "vless", "server": "cdn.example.com", "port": 443, "uuid": xrayTestUUID, "tls": true,
			"network": "grpc", "grpc-opts": map[string]any{"grpc-service-name": "svc"},
		}, map[string]string{"network": "grpc", "grpc.serviceName": "svc"}},
		{"wireguard", map[string]any{
			"name": "wg", "type": "wireguard", "server": "1.2.3.4", "port": 51820, "ip": "10.0.0.2", "ipv6": "fd00::2",
			"private-key": wgKey(t), "public-key": wgKey(t), "pre-shared-key": wgKey(t),
			"reserved": []any{1, 2, 3}, "mtu": 1380, "udp": true,
		}, map[string]string{
			"wireguard.address": `["10.0.0.2","fd00::2"]`, "wireguard.mtu": "1380", "wireguard.reserved": "[1,2,3]",
			"wireguard.endpoint": "1.2.3.4:51820", "wireguard.allowedIPs": `["0.0.0.0/0","::/0"]`, "wireguard.noKernelTun": "true",
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, err := xrayOutbound(c.proxy)
			if err != nil {
				t.Fatal(err)
			}
			got := flatXray(t, out)
			for key, want := range c.want {
				if got[key] != want {
					t.Errorf("%s = %s, want %s", key, got[key], want)
				}
			}
		})
	}
}

// The same file is test/shikoo/xray_test.dart's: Dart marks for Xray exactly what Go then hands to it.
func TestXrayServesWhatDartSays(t *testing.T) {
	content, err := os.ReadFile("testdata/xray_serves.json")
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
		if _, err := xrayOutbound(c.Proxy); (err == nil) != c.Serves {
			t.Errorf("%v: Xray takes it %v (%v), want %v", c.Proxy["name"], err == nil, err, c.Serves)
		}
	}
}

// A refusal Xray only meets while the whole core starts takes every server off Xray, never the whole apply.
func TestXrayFailureLeavesTheApplyStanding(t *testing.T) {
	wg := map[string]any{
		"name": "wg", "type": "wireguard", "server": "1.2.3.4", "port": 51820, "ip": "10.0.0.2",
		"private-key": wgKey(t), "public-key": wgKey(t), "udp": true,
	}
	cfg := parseShikooCores(t, fmt.Sprintf(`
proxies:
  - {name: wg, type: wireguard, server: 1.2.3.4, port: 51820, ip: 10.0.0.2, private-key: %q, public-key: %q, dns: ["1.1.1.1:53"], shikoo-core: xray}
`, wg["private-key"], wg["public-key"]))
	if got := cfg.Proxies["wg"].Type(); got != constant.WireGuard {
		t.Errorf("wg is %v, want mihomo's own WireGuard", got)
	}
	// Past the conversion's checks: Xray's WireGuard itself panics on this DNS while the core starts.
	_, err := runXray(map[string]any{"outbounds": []any{map[string]any{
		"protocol": "wireguard",
		"settings": map[string]any{
			"secretKey": wg["private-key"], "address": []string{"10.0.0.2"}, "noKernelTun": true, "remoteDNS": []string{"dns.google"},
			"peers": []any{map[string]any{"publicKey": wg["public-key"], "endpoint": "1.2.3.4:51820"}},
		},
	}}})
	if err == nil || !strings.Contains(err.Error(), "panicked") {
		t.Errorf("err %v, want Xray's panic as an error", err)
	}
	// Past the conversion's checks again: Xray's config builder itself panics on this encryption.
	err = xrayBuild(map[string]any{"protocol": "vless", "settings": map[string]any{
		"address": "1.1.1.1", "port": 443, "id": xrayTestUUID, "encryption": "mlkem768x25519plus.native.0rtt.",
	}})
	if err == nil || !strings.Contains(err.Error(), "panicked") {
		t.Errorf("err %v, want the builder's panic as this server's error", err)
	}
}

func TestXrayStartsAServerAloneWhenTogetherTheyFail(t *testing.T) {
	var started [][]string
	previous := xrayRun
	xrayRun = func(config map[string]any) (func(), error) {
		var tags []string
		for _, out := range config["outbounds"].([]any) {
			tags = append(tags, out.(map[string]any)["tag"].(string))
		}
		started = append(started, tags)
		if slices.Contains(tags, "out1") {
			return nil, errors.New("refused while starting")
		}
		return func() {}, nil
	}
	t.Cleanup(func() { xrayRun = previous })
	plain := func(name string) map[string]any {
		return map[string]any{"name": name, "type": "vless", "server": "10.0.0.1", "port": 80, "uuid": xrayTestUUID}
	}
	replacements, stop, err := startXray([]map[string]any{plain("a"), plain("b"), plain("c")})
	if err != nil {
		t.Fatal(err)
	}
	stop()
	var types []any
	for _, replacement := range replacements {
		types = append(types, replacement["type"])
	}
	if fmt.Sprint(types) != "[socks5 vless socks5]" || fmt.Sprint(started[len(started)-1]) != "[out0 out2]" {
		t.Errorf("types %v after starts %v: want only b on mihomo and the others started together", types, started)
	}
}

// Values Xray meets only at run time, where its panic would end the whole app: each runs in a process of its own.
var xrayRunTimeCases = map[string]map[string]any{
	"xhttp posts of -5": {"type": "vless", "uuid": xrayTestUUID, "network": "xhttp",
		"xhttp-opts": map[string]any{"path": "/p", "mode": "packet-up", "sc-max-each-post-bytes": "-5"}},
	"xhttp posts from 0": {"type": "vless", "uuid": xrayTestUUID, "network": "xhttp",
		"xhttp-opts": map[string]any{"path": "/p", "mode": "packet-up", "sc-max-each-post-bytes": "0-1000"}},
	"xhttp posts past int32": {"type": "vless", "uuid": xrayTestUUID, "network": "xhttp",
		"xhttp-opts": map[string]any{"path": "/p", "mode": "packet-up", "sc-max-each-post-bytes": "1-2147483648"}},
	"wireguard mtu -1": {"type": "wireguard", "ip": "10.9.0.2", "mtu": -1},
}

func TestXrayBadValuesKeepTheProcess(t *testing.T) {
	if os.Getenv("XRAY_RUN_TIME_CASE") != "" {
		t.Skip("child")
	}
	began := time.Now()
	for name := range xrayRunTimeCases {
		child := exec.Command(os.Args[0], "-test.run", "^TestXrayRunTimeCase$", "-test.count=1")
		child.Env = append(os.Environ(), "XRAY_RUN_TIME_CASE="+name)
		out, err := child.CombinedOutput()
		if err != nil || !strings.Contains(string(out), "kept the process") {
			t.Errorf("%s: the process ended (%v): %s", name, err, out[:min(len(out), 400)])
		}
	}
	t.Logf("%d cases in %v", len(xrayRunTimeCases), time.Since(began).Round(time.Millisecond))
}

func TestXrayRunTimeCase(t *testing.T) {
	name := os.Getenv("XRAY_RUN_TIME_CASE")
	if name == "" {
		t.Skip("parent")
	}
	server, client := wgPair(t), wgPair(t)
	ports := [2]int{}
	for i := range ports {
		ports[i], _ = freeLoopbackPort()
	}
	_, err := runXray(map[string]any{
		"inbounds": []any{
			map[string]any{"listen": "127.0.0.1", "port": ports[0], "protocol": "vless", "settings": map[string]any{
				"clients": []any{map[string]any{"id": xrayTestUUID}}, "decryption": "none"},
				"streamSettings": map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/p"}}},
			map[string]any{"listen": "127.0.0.1", "port": ports[1], "protocol": "wireguard", "settings": map[string]any{
				"secretKey": server.private, "peers": []any{map[string]any{"publicKey": client.public, "allowedIPs": []string{"10.9.0.2/32"}}}}},
		},
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow"}}}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	proxy := with(xrayRunTimeCases[name], map[string]any{"name": "bad", "server": "127.0.0.1", "port": ports[0], "udp": true})
	if proxy["type"] == "wireguard" {
		proxy = with(proxy, map[string]any{"port": ports[1], "private-key": client.private, "public-key": server.public})
	}
	replacements, stop, err := startXray([]map[string]any{proxy})
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	if replacements[0]["type"] == "socks5" {
		parsed, err := adapter.ParseProxy(replacements[0])
		if err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_, _ = parsed.URLTest(ctx, "http://"+net.JoinHostPort(outsideIP(t), "9")+"/", anyDelayTestStatus)
		cancel()
		time.Sleep(time.Second)
	}
	fmt.Println("kept the process")
}

func TestXraySocksIsLoopbackAndNeedsItsPassword(t *testing.T) {
	plain := map[string]any{"name": "a", "type": "vless", "server": "10.0.0.1", "port": 443, "uuid": xrayTestUUID}
	first, stop, err := startXray([]map[string]any{plain})
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	second, stopSecond, err := startXray([]map[string]any{plain})
	if err != nil {
		t.Fatal(err)
	}
	stopSecond()
	socks := first[0]
	if socks["server"] != "127.0.0.1" || socks["password"] == second[0]["password"] || len(socks["password"].(string)) < 26 {
		t.Fatalf("%v and %v: want 127.0.0.1 and a fresh long password each start", socks, second[0])
	}
	port := fmt.Sprint(socks["port"])
	if conn, err := net.DialTimeout("tcp", net.JoinHostPort(outsideIP(t), port), time.Second); err == nil {
		_ = conn.Close()
		t.Error("the SOCKS answers outside loopback")
	}
	answer := func(greeting []byte, user, password string) []byte {
		conn, err := net.Dial("tcp", "127.0.0.1:"+port)
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = conn.Close() }()
		_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
		reply := make([]byte, 2)
		if _, err := conn.Write(greeting); err != nil || readFull(conn, reply) != nil || user == "" {
			return reply
		}
		auth := append([]byte{1, byte(len(user))}, user...)
		auth = append(append(auth, byte(len(password))), password...)
		if _, err := conn.Write(auth); err != nil || readFull(conn, reply) != nil {
			return []byte{0xff, 0xff}
		}
		return reply
	}
	if reply := answer([]byte{5, 1, 0}, "", ""); reply[1] == 0 {
		t.Error("the SOCKS took a client without a password")
	}
	password := socks["password"].(string)
	if reply := answer([]byte{5, 1, 2}, xrayUser, "x"+password[1:]); reply[1] == 0 {
		t.Error("the SOCKS took a wrong password")
	}
	if reply := answer([]byte{5, 1, 2}, xrayUser, password); reply[1] != 0 {
		t.Errorf("the SOCKS refused its own password: % x", reply)
	}
}

func readFull(conn net.Conn, buf []byte) error {
	_, err := io.ReadFull(conn, buf)
	return err
}

// An Xray server in this process, the panel's mappings marked as Dart marks them, and mihomo's own
// URL test through what Go put in their place: the ping and the traffic of the app.
func TestXrayCarriesRealityXHTTPAndWireGuardEndToEnd(t *testing.T) {
	var mu sync.Mutex
	var dialed []string
	var udpSockets atomic.Int32
	previous := dialer.DefaultSocketHook
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		mu.Lock()
		dialed = append(dialed, address)
		mu.Unlock()
		if strings.HasPrefix(network, "udp") {
			udpSockets.Add(1)
		}
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = previous })

	var hits atomic.Int32
	target := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNoContent)
	})}
	listener, err := net.Listen("tcp", net.JoinHostPort(outsideIP(t), "0"))
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = target.Serve(listener) }()
	t.Cleanup(func() { _ = target.Close() })
	targetURL := "http://" + listener.Addr().String() + "/generate_204"

	camouflage := httptest.NewTLSServer(http.NotFoundHandler())
	t.Cleanup(camouflage.Close)
	realityKey, _ := ecdh.X25519().GenerateKey(rand.Reader)
	serverWG, clientWG := wgPair(t), wgPair(t)
	ports := [4]int{}
	for i := range ports {
		if ports[i], err = freeLoopbackPort(); err != nil {
			t.Fatal(err)
		}
	}
	realityServer := map[string]any{
		"target": camouflage.Listener.Addr().String(), "serverNames": []string{"example.com"},
		"privateKey": base64.RawURLEncoding.EncodeToString(realityKey.Bytes()), "shortIds": []string{"6ba85179e30d4fc2"},
	}
	vlessIn := func(port int, flow string, stream map[string]any) map[string]any {
		return map[string]any{
			"listen": "127.0.0.1", "port": port, "protocol": "vless", "streamSettings": stream,
			"settings": map[string]any{"clients": []any{map[string]any{"id": xrayTestUUID, "flow": flow}}, "decryption": "none"},
		}
	}
	server, err := json.Marshal(map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{
			vlessIn(ports[0], "xtls-rprx-vision", map[string]any{"network": "raw", "security": "reality", "realitySettings": realityServer}),
			vlessIn(ports[1], "", map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/x"}, "security": "reality", "realitySettings": realityServer}),
			vlessIn(ports[2], "", map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/p"}}),
			map[string]any{"listen": "127.0.0.1", "port": ports[3], "protocol": "wireguard", "settings": map[string]any{
				"secretKey": serverWG.private, "mtu": 1420,
				"peers": []any{map[string]any{"publicKey": clientWG.public, "allowedIPs": []string{"10.9.0.2/32"}}},
			}},
		},
		// Xray's freedom blackholes private addresses unless a final rule allows them.
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow"}}}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	instance, err := xcore.StartInstance("json", server)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = instance.Close() })

	realityPublic := base64.RawURLEncoding.EncodeToString(realityKey.PublicKey().Bytes())
	reality := fmt.Sprintf(`tls: true, servername: example.com, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: 6ba85179e30d4fc2}`, realityPublic)
	cfg := parseShikooCores(t, fmt.Sprintf(`
proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: %d, uuid: %s, flow: xtls-rprx-vision, udp: true, %s, shikoo-core: xray}
  - {name: xhttp-reality, type: vless, server: 127.0.0.1, port: %d, uuid: %s, network: xhttp, xhttp-opts: {path: /x}, %s, shikoo-core: xray}
  - {name: xhttp, type: vless, server: 127.0.0.1, port: %d, uuid: %s, network: xhttp, xhttp-opts: {path: /p}, shikoo-core: xray}
  - {name: wireguard, type: wireguard, server: 127.0.0.1, port: %d, ip: 10.9.0.2, private-key: %q, public-key: %q, udp: true, shikoo-core: xray}
  - {name: insecure, type: vless, server: 1.2.3.4, port: 443, uuid: %s, tls: true, skip-cert-verify: true, shikoo-core: xray}
`, ports[0], xrayTestUUID, reality, ports[1], xrayTestUUID, reality, ports[2], xrayTestUUID, ports[3], clientWG.private, serverWG.public, xrayTestUUID))
	shikooCoresCommit()
	t.Cleanup(func() {
		for _, stop := range shikooCoresRunning {
			stop()
		}
		shikooCoresRunning = nil
	})

	if got := cfg.Proxies["insecure"].Type(); got != constant.Vless {
		t.Errorf("insecure is %v: a server Xray refuses stays with mihomo", got)
	}
	for i, name := range []string{"reality", "xhttp-reality", "xhttp", "wireguard"} {
		proxy := cfg.Proxies[name]
		if proxy.Type() != constant.Socks5 {
			t.Fatalf("%s is %v, want the SOCKS in front of Xray", name, proxy.Type())
		}
		before := hits.Load()
		// 10 s: a REALITY server holds its first connection 5 s while it learns its target (xtls/reality tls.go).
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		delay, err := proxy.URLTest(ctx, targetURL, anyDelayTestStatus)
		cancel()
		if err != nil || delay == 0 {
			t.Fatalf("%s: delay %d, err %v", name, delay, err)
		}
		t.Logf("%s answered in %d ms through Xray", name, delay)
		if hits.Load() == before {
			t.Fatalf("%s answered without reaching the target", name)
		}
		if i == 3 {
			continue
		}
		server := fmt.Sprintf("127.0.0.1:%d", ports[i])
		mu.Lock()
		found := strings.Contains(strings.Join(dialed, " "), server)
		mu.Unlock()
		if !found {
			t.Errorf("%s: Xray reached %s without mihomo's dialer, so Android would not protect it", name, server)
		}
	}
	if udpSockets.Load() == 0 {
		t.Error("WireGuard's socket skipped mihomo's dialer")
	}

	echo, err := net.ListenPacket("udp", net.JoinHostPort(outsideIP(t), "0"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = echo.Close() })
	go func() {
		buf := make([]byte, 1500)
		for {
			n, from, err := echo.ReadFrom(buf)
			if err != nil {
				return
			}
			_, _ = echo.WriteTo(buf[:n], from)
		}
	}()
	to := echo.LocalAddr().(*net.UDPAddr)
	for _, name := range []string{"reality", "wireguard"} {
		if got := udpRoundTrip(t, cfg.Proxies[name], to); got != "ping "+name {
			t.Errorf("%s: UDP came back as %q", name, got)
		}
	}
}

func udpRoundTrip(t *testing.T, proxy constant.Proxy, to *net.UDPAddr) string {
	t.Helper()
	if !proxy.SupportUDP() {
		t.Errorf("%s: mihomo's tunnel would send it no UDP", proxy.Name())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ip, _ := netip.AddrFromSlice(to.IP.To4())
	conn, err := proxy.ListenPacketContext(ctx, &constant.Metadata{NetWork: constant.UDP, DstIP: ip, DstPort: uint16(to.Port)})
	if err != nil {
		t.Fatalf("%s: %v", proxy.Name(), err)
	}
	defer func() { _ = conn.Close() }()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.WriteTo([]byte("ping "+proxy.Name()), to); err != nil {
		t.Fatalf("%s: %v", proxy.Name(), err)
	}
	buf := make([]byte, 64)
	n, _, err := conn.ReadFrom(buf)
	if err != nil {
		t.Fatalf("%s: no UDP answer: %v", proxy.Name(), err)
	}
	return string(buf[:n])
}

func with(base map[string]any, changes map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range base {
		out[key] = value
	}
	for key, value := range changes {
		out[key] = value
	}
	return out
}

// flatXray names the fields a test reads: network, security, <transport>.<key>, reality.<key>, tls.<key>, wireguard.<key>.
func flatXray(t *testing.T, out map[string]any) map[string]string {
	t.Helper()
	got := map[string]string{}
	put := func(prefix string, fields any) {
		m, _ := fields.(map[string]any)
		for key, value := range m {
			if s, ok := value.(string); ok {
				got[prefix+key] = s
				continue
			}
			raw, err := json.Marshal(value)
			if err != nil {
				t.Fatal(err)
			}
			got[prefix+key] = string(raw)
		}
	}
	if stream, ok := out["streamSettings"].(map[string]any); ok {
		got["network"], _ = stream["network"].(string)
		got["security"], _ = stream["security"].(string)
		put("reality.", stream["realitySettings"])
		put("tls.", stream["tlsSettings"])
		put(got["network"]+".", stream[got["network"]+"Settings"])
	}
	if out["protocol"] == "wireguard" {
		settings := out["settings"].(map[string]any)
		put("wireguard.", settings)
		put("wireguard.", settings["peers"].([]any)[0])
	}
	return got
}

type wgKeys struct{ private, public string }

func wgPair(t *testing.T) wgKeys {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return wgKeys{base64.StdEncoding.EncodeToString(key.Bytes()), base64.StdEncoding.EncodeToString(key.PublicKey().Bytes())}
}

func wgKey(t *testing.T) string { return wgPair(t).public }

// WireGuard's own stack routes no loopback address through the tunnel.
func outsideIP(t *testing.T) string {
	t.Helper()
	addresses, _ := net.InterfaceAddrs()
	for _, address := range addresses {
		if ip, ok := address.(*net.IPNet); ok && ip.IP.To4() != nil && !ip.IP.IsLoopback() {
			return ip.IP.String()
		}
	}
	t.Skip("no address outside loopback")
	return ""
}
