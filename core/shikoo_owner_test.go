package main

import (
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestShikooOwnerReportsTheServerAnOwnerEngineCarries(t *testing.T) {
	if _, ok := methodHandlers[shikooOwnerMethod]; !ok {
		t.Fatal("shikooOwner has no handler")
	}
	carrying := ""
	registerShikooOwner("fake-owner", func() string { return carrying })
	t.Cleanup(func() { delete(shikooOwners, "fake-owner") })

	if got := shikooOwnerNow(); got != (ShikooOwner{}) {
		t.Errorf("with nothing carried the core reported %+v, want none", got)
	}
	carrying = "W"
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "fake-owner", Server: "W"}) {
		t.Errorf("the core reported %+v, want fake-owner carrying W", got)
	}
}

func TestMihomosParserIgnoresTheOwnerMark(t *testing.T) {
	cfg := parseShikooCores(t, "proxies:\n  - {name: W, type: http, server: 1.1.1.1, port: 1, shikoo-owner: wireguard}\n")

	if got := proxyTypes(cfg, "W"); got[0] != constant.Http {
		t.Errorf("type %v: the marked server must stay mihomo's own until the owner core takes the tunnel", got)
	}
}
