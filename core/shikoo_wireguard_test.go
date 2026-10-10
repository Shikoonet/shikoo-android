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

func TestCloseWireGuardClosesOnlyWireGuardOfTheReplacedConfig(t *testing.T) {
	wg := &closeCounter{tp: C.WireGuard}
	fromProvider := &closeCounter{tp: C.WireGuard}
	vless := &closeCounter{tp: C.Vless}
	closeWireGuard(&config.Config{
		Proxies:   map[string]C.Proxy{"wg": wg, "vless": vless},
		Providers: map[string]P.ProxyProvider{"sub": &fakeProvider{proxies: []C.Proxy{fromProvider}}},
	})
	closeWireGuard(nil)

	if wg.closed != 1 || fromProvider.closed != 1 {
		t.Fatalf("WireGuard closed %d and %d times, want once each", wg.closed, fromProvider.closed)
	}
	if vless.closed != 0 {
		t.Fatalf("a VLESS outbound was closed %d times; only WireGuard shares a key with its replacement", vless.closed)
	}
}
