package main

import (
	"github.com/metacubex/mihomo/adapter/outbound"
	tun "github.com/metacubex/sing-tun"
)

// Undefined here means the core was built unpatched: run bash tools/core-patches/apply.sh.
var _ = outbound.ShikooUnconnectedBind
var _ = tun.ShikooListenAgain
