package main

import (
	"bytes"
	"cmp"
	_ "embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/klauspost/compress/zstd"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/structure"
	"github.com/metacubex/mihomo/component/cidr"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel/statistic"
	singtun "github.com/metacubex/sing-tun"
	"go4.org/netipx"
	wgconn "golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// The official WireGuard engine, owning the VPN's tun (docs/multi-core.md, package h2). The VPN service asks
// for a plan before it builds the VPN, then hands the descriptor over (lib.go).

const shikooPrepareOwnerMethod CoreMethod = "shikooPrepareOwner"

// What the official Android app runs with when the server's mapping says nothing: its own MTU, and the
// keepalive and DNS of the panel's /links config, the one that app imports.
const (
	wgMTU       = 1280
	wgKeepalive = 100
)

var wgDNS = []string{"1.1.1.1", "8.8.8.8", "2606:4700:4700::1111", "2001:4860:4860::8888"}

// excludeRoute is Android 13's; below it the Iranian ranges are cut out of the routes instead, and so on Windows.
const (
	excludeRouteSdk = 33
	windowsSdk      = 0
)

type PrepareOwnerParams struct {
	Core       string `json:"core"`
	Server     string `json:"server"`
	IranDirect bool   `json:"iran-direct"`
	Held       bool   `json:"held"`
}

type ownerPlan struct {
	Addresses []string `json:"addresses"`
	DNS       []string `json:"dns"`
	MTU       int      `json:"mtu"`
	Routes    []string `json:"routes"`
	Excluded  []string `json:"excluded"`
}

type wgPrepared struct {
	server    string
	uapi      string
	peer      device.NoisePublicKey
	keepalive int
}

type wgOwner struct {
	server string
	dev    *device.Device
	peer   *device.Peer
	asked  atomic.Int64 // UnixNano of the engine's last handshake initiation: at start, then at each ping
}

var (
	ownerMu       sync.Mutex
	ownerPrepared *wgPrepared
	// Atomic, as the registry's carrying must answer at once and take no lock.
	ownerRunning atomic.Pointer[wgOwner]
)

func init() {
	registerMethod(shikooPrepareOwnerMethod, withArguments(func(params *PrepareOwnerParams, response MethodResponse) {
		safeGo(response, func() {
			plan, err := handlePrepareOwner(params)
			if err != nil {
				response.failure("owner_prepare", err.Error(), nil)
				return
			}
			response.success(plan)
		})
	}))
}

func handlePrepareOwner(params *PrepareOwnerParams) (any, error) {
	if params.Core != "wireguard" && params.Core != "openvpn" {
		return nil, fmt.Errorf("no owner core %q in this build", params.Core)
	}
	raw, err := appliedRawConfig()
	if err != nil {
		return nil, err
	}
	var mapping map[string]any
	for _, proxy := range raw.Proxy {
		if proxy["name"] == params.Server {
			mapping = proxy
			break
		}
	}
	if mapping == nil {
		return nil, fmt.Errorf("server %q is not in the config", params.Server)
	}
	if params.Core == "openvpn" {
		return ovpnPrepare(mapping, params.IranDirect, params.Held)
	}
	resolve := func(host string) (netip.Addr, error) { return resolveEndpoint(host, params.Held) }
	plan, prepared, err := wgPlan(mapping, iranRanges(params.IranDirect), int(sdkVersion.Load()), resolve)
	if err != nil {
		return nil, err
	}
	ownerMu.Lock()
	ownerPrepared = prepared
	ownerMu.Unlock()
	return plan, nil
}

func appliedRawConfig() (*config.RawConfig, error) {
	buf, err := os.ReadFile(filepath.Join(constant.Path.HomeDir(), "config.yaml"))
	if err != nil {
		return nil, err
	}
	return config.UnmarshalRawConfig(buf)
}

func iranRanges(on bool) *netipx.IPSet {
	if !on {
		return nil
	}
	iran, err := readIPSet(filepath.Join(constant.Path.HomeDir(), "shikoo-ir-ip.mrs"))
	if err != nil {
		// A missing set only sends Iranian sites through the server, as it does for mihomo's rule.
		log.Warnln("[WG] Iranian ranges not read: %v", err)
	}
	return iran
}

// wgPlan reads a mapping the way mihomo's WireGuard outbound does (adapter/outbound/wireguard.go).
func wgPlan(
	mapping map[string]any,
	iran *netipx.IPSet,
	sdk int,
	resolve func(host string) (netip.Addr, error),
) (*ownerPlan, *wgPrepared, error) {
	if mapping["type"] != "wireguard" {
		return nil, nil, fmt.Errorf("not a WireGuard server: %v", mapping["type"])
	}
	var option outbound.WireGuardOption
	decoder := structure.NewDecoder(structure.Option{TagName: "proxy", WeaklyTypedInput: true, KeyReplacer: structure.DefaultKeyReplacer})
	if err := decoder.Decode(mapping, &option); err != nil {
		return nil, nil, err
	}
	if option.AmneziaWGOption != nil {
		return nil, nil, errors.New("AmneziaWG is not WireGuard")
	}
	addresses, err := option.Prefixes()
	if err != nil {
		return nil, nil, err
	}
	peers := option.Peers
	if len(peers) == 0 {
		// One peer takes every family the tunnel has an address in, whatever allowed-ips says.
		peer := option.WireGuardPeerOption
		peer.AllowedIPs = nil
		for _, address := range addresses {
			every := netip.IPv6Unspecified()
			if address.Addr().Is4() {
				every = netip.IPv4Unspecified()
			}
			peer.AllowedIPs = append(peer.AllowedIPs, netip.PrefixFrom(every, 0).String())
		}
		peers = []outbound.WireGuardPeerOption{peer}
	}
	keepalive := wgKeepalive
	if _, set := mapping["persistent-keepalive"]; set {
		keepalive = option.PersistentKeepalive
	}

	private, err := wgKey(option.PrivateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("private key: %w", err)
	}
	var uapi strings.Builder
	uapi.WriteString("private_key=" + private + "\nreplace_peers=true\n")
	// Android blocks a family the VPN has nothing of; a route or DNS server alone would open it outside the tunnel.
	carried := map[bool]bool{}
	for _, address := range addresses {
		carried[address.Addr().Is4()] = true
	}
	var allowed netipx.IPSetBuilder
	var first device.NoisePublicKey
	for i, peer := range peers {
		if len(peer.Reserved) > 0 {
			return nil, nil, errors.New("reserved bytes are not WireGuard")
		}
		public, err := wgKey(peer.PublicKey)
		if err != nil {
			return nil, nil, fmt.Errorf("public key: %w", err)
		}
		if i == 0 {
			_ = first.FromHex(public)
		}
		ip, err := resolve(peer.Server)
		if err != nil {
			return nil, nil, fmt.Errorf("endpoint %s: %w", peer.Server, err)
		}
		uapi.WriteString("public_key=" + public + "\n")
		uapi.WriteString("endpoint=" + netip.AddrPortFrom(ip, uint16(peer.Port)).String() + "\n")
		if peer.PreSharedKey != "" {
			shared, err := wgKey(peer.PreSharedKey)
			if err != nil {
				return nil, nil, fmt.Errorf("pre-shared key: %w", err)
			}
			uapi.WriteString("preshared_key=" + shared + "\n")
		}
		uapi.WriteString("persistent_keepalive_interval=" + strconv.Itoa(keepalive) + "\nreplace_allowed_ips=true\n")
		for _, value := range peer.AllowedIPs {
			prefix, err := netip.ParsePrefix(value)
			if err != nil {
				return nil, nil, err
			}
			if carried[prefix.Addr().Is4()] {
				allowed.AddPrefix(prefix.Masked())
			}
			uapi.WriteString("allowed_ip=" + prefix.Masked().String() + "\n")
		}
	}

	plan := &ownerPlan{MTU: option.MTU, Excluded: []string{}}
	if plan.MTU <= 0 {
		plan.MTU = wgMTU
	}
	for _, address := range addresses {
		plan.Addresses = append(plan.Addresses, address.String())
	}
	for _, servers := range [][]string{option.Dns, wgDNS} {
		for _, server := range servers {
			if ip, err := netip.ParseAddr(server); err == nil && carried[ip.Unmap().Is4()] {
				plan.DNS = append(plan.DNS, ip.String())
			}
		}
		if len(plan.DNS) > 0 {
			break
		}
	}
	routes, err := allowed.IPSet()
	if err != nil {
		return nil, nil, err
	}
	if iran != nil {
		if routes, plan.Excluded, err = cutIran(routes, iran, sdk >= excludeRouteSdk); err != nil {
			return nil, nil, err
		}
	}
	plan.Routes = prefixStrings(routes)
	return plan, &wgPrepared{server: fmt.Sprint(mapping["name"]), uapi: uapi.String(), peer: first, keepalive: keepalive}, nil
}

// One binder parcel takes a VPN's routes to every app watching the network: on the emulator 1500 excluded ranges failed it
// on Android 15 and 8747 routes crashed YouTube on 7.1, while 7.1 took 946 routes in 0.4 s five times over (2026-10-23).
const (
	wgExcludedBudget = 500
	wgRoutesBudget   = 1000
)

//go:embed shikoo_iran_first.txt
var iranFirstList string

type keySite struct {
	addr  netip.Addr
	first bool
}

var iranFirst = func() (out []keySite) {
	for _, line := range strings.Split(iranFirstList, "\n") {
		if fields := strings.Fields(line); len(fields) > 1 {
			if ip, err := netip.ParseAddr(fields[0]); err == nil {
				out = append(out, keySite{ip, fields[1] == "bank" || fields[1] == "pay" || fields[1] == "key"})
			}
		}
	}
	return out
}()

// cutIran fills the route budget: Iran's /16s and wider (cheap below 13), key sites (bank, pay, key first), by size.
func cutIran(routes, iran *netipx.IPSet, excludeRoute bool) (routesLeft *netipx.IPSet, excluded []string, err error) {
	var inside netipx.IPSetBuilder
	inside.AddSet(routes)
	inside.Intersect(iran)
	all, err := inside.IPSet()
	if err != nil {
		return nil, nil, err
	}
	blocks := all.Prefixes()
	var sites []netip.Prefix
	weight := map[netip.Prefix]int{}
	for _, site := range iranFirst {
		i, found := slices.BinarySearchFunc(blocks, site.addr, func(b netip.Prefix, ip netip.Addr) int { return b.Addr().Compare(ip) })
		if !found {
			i--
		}
		if i >= 0 && blocks[i].Contains(site.addr) {
			if weight[blocks[i]] == 0 {
				sites = append(sites, blocks[i])
			}
			weight[blocks[i]]++
			if site.first {
				weight[blocks[i]] += 1 << 16
			}
		}
	}
	slices.SortStableFunc(sites, func(a, b netip.Prefix) int { return weight[b] - weight[a] })
	slices.SortStableFunc(blocks, func(a, b netip.Prefix) int {
		if a.Addr().Is4() != b.Addr().Is4() {
			return cmp.Compare(a.Addr().BitLen(), b.Addr().BitLen())
		}
		return a.Bits() - b.Bits()
	})
	wide := slices.IndexFunc(blocks, func(p netip.Prefix) bool { return !p.Addr().Is4() || p.Bits() > 16 })
	if wide < 0 {
		wide = len(blocks)
	}
	order := append(append(slices.Clone(blocks[:wide]), sites...), blocks...)
	cut := func(n int) (out, left *netipx.IPSet, fits bool, err error) {
		var b netipx.IPSetBuilder
		for _, p := range order[:n] {
			b.AddPrefix(p)
		}
		if out, err = b.IPSet(); err != nil {
			return nil, nil, false, err
		}
		if excludeRoute {
			return out, routes, len(routes.Prefixes())+len(out.Prefixes()) <= wgExcludedBudget, nil
		}
		var around netipx.IPSetBuilder
		around.AddSet(routes)
		around.RemoveSet(out)
		if left, err = around.IPSet(); err != nil {
			return nil, nil, false, err
		}
		return out, left, len(left.Prefixes()) <= wgRoutesBudget, nil
	}
	lo, hi := 0, len(order)
	for lo < hi {
		mid := (lo + hi + 1) / 2
		_, _, fits, err := cut(mid)
		if err != nil {
			return nil, nil, err
		}
		if fits {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	out, left, _, err := cut(lo)
	if err != nil {
		return nil, nil, err
	}
	if excludeRoute {
		return routes, prefixStrings(out), nil
	}
	return left, []string{}, nil
}

func prefixStrings(set *netipx.IPSet) []string {
	out := []string{}
	for _, prefix := range set.Prefixes() {
		out = append(out, prefix.String())
	}
	return out
}

func wgKey(value string) (string, error) {
	key, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return "", err
	}
	if len(key) != device.NoisePublicKeySize {
		return "", fmt.Errorf("%d bytes, not 32", len(key))
	}
	return hex.EncodeToString(key), nil
}

// readIPSet reads an ipcidr rule set in mihomo's MRS form (rules/provider/mrs_reader.go).
func readIPSet(path string) (*netipx.IPSet, error) {
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	reader, err := zstd.NewReader(bytes.NewReader(buf))
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	var head struct {
		Magic    [4]byte
		Behavior byte
		Count    int64
		Extra    int64
	}
	if err := binary.Read(reader, binary.BigEndian, &head); err != nil {
		return nil, err
	}
	if head.Magic != provider.MrsMagicBytes || head.Behavior != P.IPCIDR.Byte() || head.Extra < 0 {
		return nil, errors.New("not an ipcidr rule set")
	}
	if _, err := io.CopyN(io.Discard, reader, head.Extra); err != nil {
		return nil, err
	}
	set, err := cidr.ReadIpCidrSet(reader)
	if err != nil {
		return nil, err
	}
	return set.ToIPSet(), nil
}

// startOwner runs the prepared server, and closes [t] when it cannot; the caller has stopped the last tunnel.
func startOwner(t tun.Device, bind wgconn.Bind) error {
	ownerMu.Lock()
	prepared := ownerPrepared
	ownerPrepared = nil
	ownerMu.Unlock()
	if prepared == nil {
		_ = t.Close()
		return errors.New("no server prepared")
	}
	owner, err := startWireGuard(t, bind, prepared)
	if err != nil {
		return err
	}
	ownerRunning.Store(owner)
	shikooOwnerTakes(prepared.server)
	go forgetWhenClosed(owner)
	return nil
}

func forgetWhenClosed(owner *wgOwner) {
	<-owner.dev.Wait()
	ownerRunning.CompareAndSwap(owner, nil)
}

func startWireGuard(t tun.Device, bind wgconn.Bind, prepared *wgPrepared) (*wgOwner, error) {
	dev, err := upWithoutKeepalive(t, bind, prepared)
	if err != nil {
		return nil, err
	}
	owner := &wgOwner{server: prepared.server, dev: dev, peer: dev.LookupPeer(prepared.peer)}
	owner.asked.Store(time.Now().UnixNano())
	if owner.peer != nil {
		_ = owner.peer.SendHandshakeInitiation(false)
	}
	if prepared.keepalive > 0 {
		if err := dev.IpcSet(keepaliveOf(prepared) + strconv.Itoa(prepared.keepalive) + "\n"); err != nil {
			dev.Close()
			return nil, err
		}
	}
	return owner, nil
}

// Up would send a keepalive, and so an initiation, before the engine could time one of its own.
func upWithoutKeepalive(t tun.Device, bind wgconn.Bind, prepared *wgPrepared) (*device.Device, error) {
	logger := &device.Logger{
		Verbosef: device.DiscardLogf,
		Errorf:   func(format string, args ...any) { log.Warnln("[WG] "+format, args...) },
	}
	dev := device.NewDevice(countingTun{t}, bind, logger)
	held := "persistent_keepalive_interval=" + strconv.Itoa(prepared.keepalive) + "\n"
	if err := dev.IpcSet(strings.Replace(prepared.uapi, held, "persistent_keepalive_interval=0\n", 1)); err != nil {
		dev.Close()
		return nil, err
	}
	dev.DisableSomeRoamingForBrokenMobileSemantics()
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, err
	}
	return dev, nil
}

func keepaliveOf(prepared *wgPrepared) string {
	return "public_key=" + hex.EncodeToString(prepared.peer[:]) + "\nupdate_only=true\npersistent_keepalive_interval="
}

func stopOwner() {
	owner := ownerRunning.Swap(nil)
	if owner != nil {
		owner.dev.Close()
	}
}

// registerOwner puts the engine in the registry (core/shikoo_owner.go); Android's init calls it in shikoo_wg_android.go.
func registerOwner(core string) {
	registerShikooOwner(core, ownerServer, ownerPing)
}

func ownerServer() string {
	if owner := ownerRunning.Load(); owner != nil {
		return owner.server
	}
	return ""
}

// ownerPing: the registry asks only for the server ownerServer named, but the engine may stop in between.
func ownerPing(params *TestDelayParams) *Delay {
	if owner := ownerRunning.Load(); owner != nil && owner.server == params.ProxyName {
		return owner.testDelay(params)
	}
	return &Delay{Name: params.ProxyName, Url: params.TestUrl, Value: -1}
}

// testDelay is the time a fresh handshake takes: the server's own answer, through the socket that carries the
// tunnel. wireguard-go sends at most one initiation per 5 s, so a ping right after another times that one.
func (o *wgOwner) testDelay(params *TestDelayParams) *Delay {
	delay := &Delay{Name: params.ProxyName, Url: params.TestUrl, Value: -1}
	if o.peer == nil {
		return delay
	}
	start := time.Now()
	asked := time.Unix(0, o.asked.Load())
	if start.Sub(asked) >= device.RekeyTimeout {
		if sinceItsOwn := time.Since(o.lastHandshake()); sinceItsOwn < device.RekeyTimeout {
			time.Sleep(device.RekeyTimeout - sinceItsOwn)
		}
		asked = time.Now()
		o.asked.Store(asked.UnixNano())
		if o.peer.SendHandshakeInitiation(false) != nil {
			return delay
		}
	}
	for deadline := time.Now().Add(delayTestTimeout(params.Timeout)); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		if at := o.lastHandshake(); !at.Before(asked) {
			delay.Value = int32(max(at.Sub(asked).Milliseconds(), 1))
			return delay
		}
	}
	return delay
}

func (o *wgOwner) lastHandshake() time.Time {
	state, err := o.dev.IpcGet()
	if err != nil {
		return time.Time{}
	}
	var sec, nsec int64
	for _, line := range strings.Split(state, "\n") {
		key, value, _ := strings.Cut(line, "=")
		switch key {
		case "last_handshake_time_sec":
			sec, _ = strconv.ParseInt(value, 10, 64)
		case "last_handshake_time_nsec":
			nsec, _ = strconv.ParseInt(value, 10, 64)
		}
	}
	if sec == 0 && nsec == 0 {
		return time.Time{}
	}
	return time.Unix(sec, nsec)
}

// countingTun puts the tunnel's packets in mihomo's totals, which getTraffic reads.
type countingTun struct{ tun.Device }

func (c countingTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := c.Device.Read(bufs, sizes, offset)
	var total int64
	for _, size := range sizes[:n] {
		total += int64(size)
	}
	statistic.DefaultManager.PushUploaded(false, total)
	return n, err
}

func (c countingTun) Write(bufs [][]byte, offset int) (int, error) {
	n, err := c.Device.Write(bufs, offset)
	// n is packets for some devices and bytes for Linux's.
	var total int64
	for _, buf := range bufs {
		total += int64(len(buf) - offset)
	}
	statistic.DefaultManager.PushDownloaded(false, total)
	return n, err
}

// ownerInUse: the live pick of the listed group (mainGroupOf), if marked; Iran's ranges stay out while DIRECT by rule.
func ownerInUse(raw *config.RawConfig, now func(group string) string) (mapping map[string]any, iranDirect bool) {
	for _, group := range raw.ProxyGroup {
		if hidden, _ := group["hidden"].(bool); hidden {
			continue
		}
		server := now(fmt.Sprint(group["name"]))
		for _, proxy := range raw.Proxy {
			if proxy["name"] == server && proxy[shikooOwnerKey] == "wireguard" {
				mapping = proxy
			}
		}
		break
	}
	if mapping == nil {
		return nil, false
	}
	return mapping, slices.ContainsFunc(raw.Rule, func(rule string) bool {
		fields := strings.Split(strings.ReplaceAll(rule, " ", ""), ",")
		return len(fields) >= 3 && fields[0] == "RULE-SET" && fields[1] == "shikoo-ir-ip" && fields[2] == "DIRECT"
	})
}

type winTun struct {
	t      singtun.WinTun
	name   string
	mtu    int
	events chan tun.Event
	closed sync.Once
}

func newWinTun(t singtun.WinTun, name string, mtu int) *winTun {
	return &winTun{t: t, name: name, mtu: mtu, events: make(chan tun.Event)}
}

func (w *winTun) File() *os.File { return nil }

func (w *winTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	packet, release, err := w.t.ReadPacket()
	if err != nil {
		return 0, err
	}
	sizes[0] = copy(bufs[0][offset:], packet)
	release()
	return 1, nil
}

func (w *winTun) Write(bufs [][]byte, offset int) (int, error) {
	for i, buf := range bufs {
		if _, err := w.t.Write(buf[offset:]); err != nil {
			return i, err
		}
	}
	return len(bufs), nil
}

func (w *winTun) MTU() (int, error) { return w.mtu, nil }

func (w *winTun) Name() (string, error) { return w.name, nil }

func (w *winTun) Events() <-chan tun.Event { return w.events }

func (w *winTun) BatchSize() int { return 1 }

func (w *winTun) Close() error {
	err := w.t.Close()
	w.closed.Do(func() { close(w.events) })
	return err
}
