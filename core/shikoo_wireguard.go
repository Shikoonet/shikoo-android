package main

import (
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// ponytail: WireGuard only (SHIKOO_PATCHES.md row 24); a QUIC outbound keeps a pre-VPN socket too, add it if one ships.
func rebindWireGuard() {
	for _, proxy := range tunnel.AllProxies() {
		outbound.ShikooRebind(shikooUngated(proxy.Adapter()))
	}
}

func closeWireGuard(cfg *config.Config) {
	if cfg == nil {
		return
	}
	proxies := make([]C.Proxy, 0, len(cfg.Proxies))
	for _, proxy := range cfg.Proxies {
		proxies = append(proxies, proxy)
	}
	for _, provider := range cfg.Providers {
		proxies = append(proxies, provider.Proxies()...)
	}
	for _, proxy := range proxies {
		if proxy.Type() == C.WireGuard {
			_ = proxy.Close()
		}
	}
}
