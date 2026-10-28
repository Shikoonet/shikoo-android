package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/resolver"
	C "github.com/metacubex/mihomo/constant"
	mDNS "github.com/miekg/dns"
	xcore "github.com/xtls/xray-core/core"
)

func TestShikooCoresSendNamesAsUDPThroughTheServer(t *testing.T) {
	ip := outsideIP(t)
	var queries atomic.Int32
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
	echo, err := net.ListenPacket("udp", net.JoinHostPort(ip, "0"))
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

	serverWG, singBoxWG, xrayWG := wgPair(t), wgPair(t), wgPair(t)
	var ports [2]int
	for i := range ports {
		if ports[i], err = freeLoopbackPort(); err != nil {
			t.Fatal(err)
		}
	}
	allow := []any{map[string]any{"action": "allow"}}
	server, err := json.Marshal(map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{
			map[string]any{"listen": "127.0.0.1", "port": ports[0], "protocol": "wireguard", "settings": map[string]any{
				"secretKey": serverWG.private, "mtu": 1420, "peers": []any{
					map[string]any{"publicKey": singBoxWG.public, "allowedIPs": []string{"10.9.0.2/32"}},
					map[string]any{"publicKey": xrayWG.public, "allowedIPs": []string{"10.9.0.3/32"}},
				}}},
			map[string]any{"listen": "127.0.0.1", "port": ports[1], "protocol": "vless", "settings": map[string]any{
				"clients": []any{map[string]any{"id": xrayTestUUID}}, "decryption": "none"}},
		},
		"outbounds": []any{
			map[string]any{"tag": "direct", "protocol": "freedom", "settings": map[string]any{"finalRules": allow}},
			map[string]any{"tag": "dns", "protocol": "freedom", "settings": map[string]any{
				"redirect": dnsConn.LocalAddr().String(), "finalRules": allow}},
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
	wg := "type: wireguard, server: 127.0.0.1, port: %d, public-key: %q, udp: true, remote-dns-resolve: true, dns: [1.1.1.1, 8.8.8.8]"
	vless := fmt.Sprintf("type: vless, server: 127.0.0.1, port: %d, uuid: %s, udp: true", ports[1], xrayTestUUID)
	cfg := parseShikooCores(t, fmt.Sprintf(`
proxies:
  - {name: wg sing-box, ip: 10.9.0.2, private-key: %q, %s, shikoo-core: singBox}
  - {name: wg xray, ip: 10.9.0.3, private-key: %q, %s, shikoo-core: xray}
  - {name: vless sing-box, %s, shikoo-core: singBox}
  - {name: vless xray, %s, shikoo-core: xray}
  - {name: plain socks, type: socks5, server: 127.0.0.1, port: 1, udp: true}
`, singBoxWG.private, fmt.Sprintf(wg, ports[0], serverWG.public), xrayWG.private, fmt.Sprintf(wg, ports[0], serverWG.public),
		vless, vless))
	shikooCoresCommit()
	t.Cleanup(func() {
		for _, stop := range shikooCoresRunning {
			stop()
		}
		shikooCoresRunning = nil
	})

	if _, err := cfg.Proxies["plain socks"].ListenPacketContext(context.Background(),
		&C.Metadata{NetWork: C.UDP, Host: "probe.test", DstPort: 1}); err == nil {
		t.Error("a plain SOCKS server resolved a name without mihomo's resolver")
	}
	echoPort := echo.LocalAddr().(*net.UDPAddr).Port
	for _, name := range []string{"wg sing-box", "wg xray", "vless sing-box", "vless xray"} {
		proxy := cfg.Proxies[name]
		if proxy.Type() != C.Socks5 {
			t.Errorf("%s is %v, want the SOCKS in front of its core", name, proxy.Type())
			continue
		}
		before := queries.Load()
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		metadata := &C.Metadata{NetWork: C.UDP, Host: "probe.test", DstPort: uint16(echoPort)}
		pc, err := proxy.ListenPacketContext(ctx, metadata)
		cancel()
		if err != nil {
			t.Errorf("%s: %v", name, err)
			continue
		}
		_, _ = pc.WriteTo([]byte(name), metadata.UDPAddr())
		buf := make([]byte, 64)
		_ = pc.SetReadDeadline(time.Now().Add(5 * time.Second))
		n, _, err := pc.ReadFrom(buf)
		_ = pc.Close()
		if err != nil || string(buf[:n]) != name || queries.Load() == before {
			t.Errorf("%s: echo %q, err %v, lookups through the server %d", name, buf[:n], err, queries.Load()-before)
		}
	}
}
