package main

import (
	"fmt"
	"sync/atomic"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

type ownerBuild struct{ core, server string }

var (
	// Sam (2026-10-23): a WireGuard engine that would not start leaves its server on mihomo's tun until the next run.
	ownerFailed string
	// Go's own rebuild for a new key is no death to the app's watch: the server, until the new engine runs or fails.
	ownerBuilding atomic.Pointer[ownerBuild]

	startOwnerTunnel func(device, key, core string, mapping map[string]any, iranDirect bool) error
	ownerTunnelKey   func() string
	closeOwnerTunnel func()
	mihomoTun        = func(conf LC.Tun) { listener.ReCreateTun(conf, tunnel.Tunnel) }
	pickOf           = groupPick
)

func buildingFor(core string) string {
	if building := ownerBuilding.Load(); building != nil && building.core == core {
		return building.server
	}
	return ""
}

func recreateOwnerTun(conf LC.Tun) {
	var core string
	var mapping map[string]any
	var iranDirect bool
	if conf.Enable {
		raw, err := appliedRawConfig()
		if err != nil {
			log.Warnln("[Owner] config not read: %v", err)
		} else {
			core, mapping, iranDirect = ownerInUse(raw, pickOf)
		}
	}
	key := fmt.Sprint(conf.Device, mapping, iranDirect)
	// OpenVPN has no mihomo to fall back to (Sam, 2026-10-30): one that cannot run leaves no tunnel.
	if mapping == nil || key == ownerFailed {
		closeOwnerTunnel()
		if core != "openvpn" {
			mihomoTun(conf)
		}
		return
	}
	if ownerTunnelKey() == key {
		return
	}
	if shikooOwnerNow().Server != "" {
		ownerBuilding.Store(&ownerBuild{core, fmt.Sprint(mapping["name"])})
		defer ownerBuilding.Store(nil)
	}
	// mihomo's tun leaves first: its DNS would answer the endpoint's name with a fake address.
	mihomoTun(LC.Tun{})
	closeOwnerTunnel()
	if err := startOwnerTunnel(conf.Device, key, core, mapping, iranDirect); err != nil {
		log.Errorln("[Owner] %s did not start: %v", core, err)
		ownerFailed = key
		if core != "openvpn" {
			mihomoTun(conf)
		}
	}
}

func groupPick(name string) string {
	if proxy, ok := tunnel.AllProxies()[name].(*adapter.Proxy); ok {
		if group, ok := proxy.ProxyAdapter.(interface{ Now() string }); ok {
			return group.Now()
		}
	}
	return ""
}
