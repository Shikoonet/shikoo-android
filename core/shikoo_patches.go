package main

import "github.com/metacubex/mihomo/adapter/outbound"

// Undefined here means the core was built unpatched: run bash tools/core-patches/apply.sh.
var _ = outbound.ShikooUnconnectedBind
