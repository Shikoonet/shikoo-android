package main

import (
	"github.com/metacubex/mihomo/adapter/outbound"
	tun "github.com/metacubex/sing-tun"
)

// An error here means the core was built unpatched: run bash tools/core-patches/apply.sh.
var _ = outbound.ShikooUnconnectedBind
var _ = tun.ShikooListenAgain
var _ *bool = outbound.RealityOptions{}.SupportX25519MLKEM768
var _ = outbound.Socks5Option{}.RemoteDnsResolve
