package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

const shikooOwnerMethod CoreMethod = "shikooOwner"

const shikooOwnerKey = "shikoo-owner"

type ShikooOwner struct {
	Core   string `json:"core"`
	Server string `json:"server"`
}

type shikooOwnerEngine struct {
	carrying func() string
	ping     func(params *TestDelayParams) *Delay
}

var shikooOwners = map[string]shikooOwnerEngine{}

// registerShikooOwner, from an owner engine's init(): carrying names the server it carries now ("" none); ping answers
// that server's delay test from the engine's own session (nil: none). Contract: docs/multi-core.md §4.
func registerShikooOwner(core string, carrying func() string, ping func(params *TestDelayParams) *Delay) {
	if _, exists := shikooOwners[core]; exists {
		panic("shikoo owner registered twice: " + core)
	}
	shikooOwners[core] = shikooOwnerEngine{carrying: carrying, ping: ping}
}

func shikooOwnerNow() ShikooOwner {
	for core, owner := range shikooOwners {
		if server := owner.carrying(); server != "" {
			return ShikooOwner{Core: core, Server: server}
		}
	}
	return ShikooOwner{}
}

func shikooOwnerOf(server string) (shikooOwnerEngine, bool) {
	if server != "" {
		for _, owner := range shikooOwners {
			if owner.carrying() == server {
				return owner, true
			}
		}
	}
	return shikooOwnerEngine{}, false
}

var errShikooOwnerCarries = errors.New("an owner core carries this server")

// shikooOwnerGate: one session per key or username on the server, so mihomo's client waits while an owner carries it.
type shikooOwnerGate struct{ C.ProxyAdapter }

func (gate shikooOwnerGate) DialContext(ctx context.Context, metadata *C.Metadata) (C.Conn, error) {
	if _, carried := shikooOwnerOf(gate.Name()); carried {
		return nil, errShikooOwnerCarries
	}
	return gate.ProxyAdapter.DialContext(ctx, metadata)
}

func (gate shikooOwnerGate) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	if _, carried := shikooOwnerOf(gate.Name()); carried {
		return nil, errShikooOwnerCarries
	}
	return gate.ProxyAdapter.ListenPacketContext(ctx, metadata)
}

// Before mihomo holds cfg, so groups and the tunnel see only the gated proxy.
func shikooOwnerGates(raw *config.RawConfig, cfg *config.Config) {
	for _, mapping := range raw.Proxy {
		if _, marked := mapping[shikooOwnerKey]; !marked {
			continue
		}
		if proxy, ok := cfg.Proxies[fmt.Sprint(mapping["name"])].(*adapter.Proxy); ok {
			proxy.ProxyAdapter = shikooOwnerGate{proxy.ProxyAdapter}
		}
	}
}

// shikooOwnerTakes, from an owner engine once it carries server: a client of mihomo's that dialed it before, a ping
// round while off, would keep its session alive past the gate until the next apply.
func shikooOwnerTakes(server string) {
	if proxy := tunnel.AllProxies()[server]; proxy != nil {
		_ = proxy.Close()
	}
}

func shikooUngated(proxy C.ProxyAdapter) C.ProxyAdapter {
	if gate, ok := proxy.(shikooOwnerGate); ok {
		return gate.ProxyAdapter
	}
	return proxy
}

func init() {
	registerMethod(shikooOwnerMethod, withoutArguments(func(response MethodResponse) {
		response.success(shikooOwnerNow())
	}))
	mihomoDelay := methodHandlers[asyncTestDelayMethod]
	methodHandlers[asyncTestDelayMethod] = func(call *MethodCall, response MethodResponse) {
		var params TestDelayParams
		if call.decodeArguments(&params) == nil {
			if owner, carried := shikooOwnerOf(params.ProxyName); carried && owner.ping != nil {
				safeGo(response, func() { response.success(owner.ping(&params)) })
				return
			}
		}
		mihomoDelay(call, response)
	}
}
