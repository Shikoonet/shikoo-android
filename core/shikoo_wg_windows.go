//go:build windows

package main

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	singtun "github.com/metacubex/sing-tun"
	"github.com/metacubex/sing/common/control"
	wgconn "golang.zx2c4.com/wireguard/conn"
)

// Windows' TUN mode on the official engine (docs/multi-core.md §4), under configMu. Windows cannot leave the app out of
// the tunnel, so the engine's socket and mihomo's dialer (the door, DIRECT rules, pings) bind to the physical interface.

type ownerTunnel struct {
	key     string
	network singtun.NetworkUpdateMonitor
	monitor singtun.DefaultInterfaceMonitor
	finder  *physicalFinder
}

// Android registers in shikoo_wg_android.go: a name registered twice panics.
func init() { registerShikooOwner("wireguard", windowsCarrying, ownerPing) }

var (
	ownerTun *ownerTunnel
	// Sam (2026-10-23): an engine that would not start leaves its server on mihomo's tun until the next run.
	ownerFailed string
	// Go's own rebuild for a new key is no death to the app's watch: the server, until the new engine runs or fails.
	ownerBuilding atomic.Pointer[string]

	startOwnerTunnel = startOwnerTun
	mihomoTun        = func(conf LC.Tun) { listener.ReCreateTun(conf, tunnel.Tunnel) }
	pickOf           = groupPick
)

func windowsCarrying() string {
	if server := ownerServer(); server != "" {
		return server
	}
	if building := ownerBuilding.Load(); building != nil {
		return *building
	}
	return ""
}

func reCreateTun(conf LC.Tun) {
	var mapping map[string]any
	var iranDirect bool
	if conf.Enable {
		raw, err := appliedRawConfig()
		if err != nil {
			log.Warnln("[WG] config not read: %v", err)
		} else {
			mapping, iranDirect = ownerInUse(raw, pickOf)
		}
	}
	key := fmt.Sprint(conf.Device, mapping, iranDirect)
	if mapping == nil || key == ownerFailed {
		closeOwnerTun()
		mihomoTun(conf)
		return
	}
	if ownerTun != nil && ownerTun.key == key {
		return
	}
	if ownerServer() != "" {
		server := fmt.Sprint(mapping["name"])
		ownerBuilding.Store(&server)
		defer ownerBuilding.Store(nil)
	}
	// mihomo's tun leaves first: its DNS would answer the endpoint's name with a fake address.
	mihomoTun(LC.Tun{})
	closeOwnerTun()
	if err := startOwnerTunnel(conf.Device, key, mapping, iranDirect); err != nil {
		log.Errorln("[WG] owner core did not start, mihomo carries the server: %v", err)
		ownerFailed = key
		mihomoTun(conf)
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

func startOwnerTun(device, key string, mapping map[string]any, iranDirect bool) (err error) {
	plan, prepared, err := wgPlan(mapping, iranRanges(iranDirect), windowsSdk, lookupEndpoint)
	if err != nil {
		return err
	}
	owner := &ownerTunnel{key: key}
	defer func() {
		if err != nil {
			owner.close()
		}
	}()
	if owner.network, err = singtun.NewNetworkUpdateMonitor(log.SingLogger); err != nil {
		return err
	}
	if err = owner.network.Start(); err != nil {
		return err
	}
	owner.monitor, err = singtun.NewDefaultInterfaceMonitor(owner.network, log.SingLogger,
		singtun.DefaultInterfaceMonitorOptions{InterfaceFinder: sing_tun.DefaultInterfaceFinder})
	if err != nil {
		return err
	}
	if err = owner.monitor.Start(); err != nil {
		return err
	}
	bind := &physicalBind{Bind: wgconn.NewDefaultBind(), monitor: owner.monitor}
	owner.monitor.RegisterCallback(func(*control.Interface, int) {
		bind.follow()
		iface.FlushCache()
		resolver.ResetConnection()
	})

	options := wintunOptions(device, plan)
	wintun, err := newWintun(options)
	if err != nil {
		return err
	}
	ownerMu.Lock()
	ownerPrepared = prepared
	ownerMu.Unlock()
	if err = startOwner(newWinTun(wintun, device, plan.MTU), bind); err != nil {
		return err
	}
	owner.finder = &physicalFinder{owner.monitor}
	if !dialer.DefaultInterfaceFinder.CompareAndSwap(nil, owner.finder) {
		log.Warnln("[WG] another interface finder holds mihomo's dialer")
	}
	ownerTun = owner
	return nil
}

// On-link routes as wireguard-windows adds them; a missing family comes in to be dropped, as Windows lets it out.
func wintunOptions(device string, plan *ownerPlan) singtun.Options {
	options := singtun.Options{
		Name:         device,
		MTU:          uint32(plan.MTU),
		AutoRoute:    true,
		Inet4Gateway: netip.IPv4Unspecified(),
		Inet6Gateway: netip.IPv6Unspecified(),
	}
	for _, value := range plan.Addresses {
		if prefix := netip.MustParsePrefix(value); prefix.Addr().Is4() {
			options.Inet4Address = append(options.Inet4Address, prefix)
		} else {
			options.Inet6Address = append(options.Inet6Address, prefix)
		}
	}
	for _, value := range plan.Routes {
		if prefix := netip.MustParsePrefix(value); prefix.Addr().Is4() {
			options.Inet4RouteAddress = append(options.Inet4RouteAddress, prefix)
		} else {
			options.Inet6RouteAddress = append(options.Inet6RouteAddress, prefix)
		}
	}
	if len(options.Inet4Address) == 0 {
		options.Inet4Address = []netip.Prefix{netip.MustParsePrefix("172.19.0.1/32")}
		options.Inet4RouteAddress = []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0")}
	}
	if len(options.Inet6Address) == 0 {
		options.Inet6Address = []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/128")}
		options.Inet6RouteAddress = []netip.Prefix{netip.MustParsePrefix("::/0")}
	}
	for _, value := range plan.DNS {
		options.DNSServers = append(options.DNSServers, netip.MustParseAddr(value))
	}
	return options
}

// mihomo's tunNew: an adapter of the same name still going away answers slowly that it already exists.
func newWintun(options singtun.Options) (wintun singtun.WinTun, err error) {
	for range 3 {
		begin := time.Now()
		if wintun, err = singtun.New(options); err == nil || time.Since(begin) < time.Second {
			return wintun, err
		}
		log.Warnln("[WG] wintun not ready, again: %v", err)
	}
	return wintun, err
}

func stopOwnerTun() {
	closeOwnerTun()
	ownerFailed = ""
}

func closeOwnerTun() {
	if ownerTun != nil {
		ownerTun.close()
		ownerTun = nil
	}
}

func (o *ownerTunnel) close() {
	if o.finder != nil {
		dialer.DefaultInterfaceFinder.CompareAndSwap(o.finder, nil)
	}
	stopOwner()
	if o.monitor != nil {
		_ = o.monitor.Close()
	}
	if o.network != nil {
		_ = o.network.Close()
	}
}

// physicalBind binds on open, before the first handshake meets sing-tun's routes; with no interface it drops, as
// wireguard-windows does, what would loop through the tunnel.
type physicalBind struct {
	wgconn.Bind
	monitor singtun.DefaultInterfaceMonitor
}

func (b *physicalBind) Open(port uint16) ([]wgconn.ReceiveFunc, uint16, error) {
	fns, actual, err := b.Bind.Open(port)
	if err == nil {
		b.follow()
	}
	return fns, actual, err
}

func (b *physicalBind) follow() {
	var index uint32
	if physical := b.monitor.DefaultInterface(); physical != nil {
		index = uint32(physical.Index)
	}
	bind := b.Bind.(wgconn.BindSocketToInterface)
	for _, err := range []error{bind.BindSocketToInterface4(index, index == 0), bind.BindSocketToInterface6(index, index == 0)} {
		if err != nil && !errors.Is(err, net.ErrClosed) {
			log.Warnln("[WG] socket not bound to interface %d: %v", index, err)
		}
	}
}

// physicalFinder is what mihomo's own tun gives its dialer for auto-detect-interface.
type physicalFinder struct {
	monitor singtun.DefaultInterfaceMonitor
}

func (f *physicalFinder) FindInterfaceName(destination netip.Addr) string {
	if local, _ := sing_tun.DefaultInterfaceFinder.ByAddr(destination); local != nil {
		return local.Name
	}
	if physical := f.monitor.DefaultInterface(); physical != nil {
		return physical.Name
	}
	return ""
}
