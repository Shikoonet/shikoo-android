package main

import (
	"testing"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
)

type closeCounter struct {
	C.Proxy
	tp     C.AdapterType
	closed int
}

func (c *closeCounter) Type() C.AdapterType { return c.tp }

func (c *closeCounter) Close() error {
	c.closed++
	return nil
}

type fakeProvider struct {
	P.ProxyProvider
	proxies []C.Proxy
}

func (f *fakeProvider) Proxies() []C.Proxy { return f.proxies }

func TestCloseWireGuardAlsoClosesTheOpenVPNAndSSHOfTheReplacedConfig(t *testing.T) {
	wg := &closeCounter{tp: C.WireGuard}
	fromProvider := &closeCounter{tp: C.WireGuard}
	openvpn := &closeCounter{tp: C.OpenVPN}
	ssh := &closeCounter{tp: C.Ssh}
	vless := &closeCounter{tp: C.Vless}
	closeWireGuard(&config.Config{
		Proxies:   map[string]C.Proxy{"wg": wg, "openvpn": openvpn, "ssh": ssh, "vless": vless},
		Providers: map[string]P.ProxyProvider{"sub": &fakeProvider{proxies: []C.Proxy{fromProvider}}},
	})
	closeWireGuard(nil)

	if wg.closed != 1 || fromProvider.closed != 1 {
		t.Fatalf("WireGuard closed %d and %d times, want once each", wg.closed, fromProvider.closed)
	}
	if openvpn.closed != 1 || ssh.closed != 1 {
		t.Fatalf("OpenVPN closed %d and SSH %d times, want once each: each would keep its login", openvpn.closed, ssh.closed)
	}
	if vless.closed != 0 {
		t.Fatalf("a VLESS outbound was closed %d times; it holds no session with its server", vless.closed)
	}
}
