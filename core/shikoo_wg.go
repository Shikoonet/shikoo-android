package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
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
	"github.com/metacubex/mihomo/tunnel"
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

var wgDNS = []string{"1.1.1.1", "8.8.8.8"}

// excludeRoute is Android 13's; below it the Iranian ranges are cut out of the routes instead.
const excludeRouteSdk = 33

type PrepareOwnerParams struct {
	Core       string `json:"core"`
	Server     string `json:"server"`
	IranDirect bool   `json:"iran-direct"`
}

type ownerPlan struct {
	Addresses []string `json:"addresses"`
	DNS       []string `json:"dns"`
	MTU       int      `json:"mtu"`
	Routes    []string `json:"routes"`
	Excluded  []string `json:"excluded"`
}

type wgPrepared struct {
	server string
	uapi   string
	peer   device.NoisePublicKey
}

type wgOwner struct {
	server string
	dev    *device.Device
	peer   *device.Peer
}

var (
	ownerMu       sync.Mutex
	ownerPrepared *wgPrepared
	ownerRunning  *wgOwner
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
	// The owner's server shares its key with mihomo's client for it: a handshake from that client would take the
	// server's session for a while, so the owner answers pings of its server itself (handleTestDelay's twin).
	mihomoDelay := methodHandlers[asyncTestDelayMethod]
	methodHandlers[asyncTestDelayMethod] = func(call *MethodCall, response MethodResponse) {
		var params TestDelayParams
		if call.decodeArguments(&params) == nil {
			if owner := ownerFor(params.ProxyName); owner != nil {
				safeGo(response, func() { response.success(owner.testDelay(&params)) })
				return
			}
		}
		mihomoDelay(call, response)
	}
}

func handlePrepareOwner(params *PrepareOwnerParams) (*ownerPlan, error) {
	if params.Core != "wireguard" {
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
	plan, prepared, err := wgPlan(mapping, iranRanges(params.IranDirect), int(sdkVersion.Load()), lookupEndpoint)
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
			allowed.AddPrefix(prefix.Masked())
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
	for _, server := range option.Dns {
		if ip, err := netip.ParseAddr(server); err == nil {
			plan.DNS = append(plan.DNS, ip.String())
		}
	}
	if len(plan.DNS) == 0 {
		plan.DNS = wgDNS
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
	return plan, &wgPrepared{server: fmt.Sprint(mapping["name"]), uapi: uapi.String(), peer: first}, nil
}

// One binder parcel takes a VPN's routes to every app watching the network: 2067 Iranian ranges overflowed it (Android
// 15), 8747 routes around them crashed YouTube (7.1). So the widest blocks within wgRouteBudget go; the rest ride the server.
const wgRouteBudget = 500

func cutIran(routes, iran *netipx.IPSet, excludeRoute bool) (routesLeft *netipx.IPSet, excluded []string, err error) {
	var inside netipx.IPSetBuilder
	inside.AddSet(routes)
	inside.Intersect(iran)
	all, err := inside.IPSet()
	if err != nil {
		return nil, nil, err
	}
	blocks := all.Prefixes()
	size := func(p netip.Prefix) int { return p.Addr().BitLen() - p.Bits() }
	slices.SortStableFunc(blocks, func(a, b netip.Prefix) int { return size(b) - size(a) })
	routesLeft, excluded = routes, []string{}
	var cut netipx.IPSetBuilder
	for i, j := 0, 0; i < len(blocks); i = j {
		for j = i; j < len(blocks) && size(blocks[j]) == size(blocks[i]); j++ {
			cut.AddPrefix(blocks[j])
		}
		out, err := cut.IPSet()
		if err != nil {
			return nil, nil, err
		}
		if excludeRoute {
			if len(routes.Prefixes())+len(out.Prefixes()) > wgRouteBudget {
				break
			}
			excluded = prefixStrings(out)
			continue
		}
		var left netipx.IPSetBuilder
		left.AddSet(routes)
		left.RemoveSet(out)
		around, err := left.IPSet()
		if err != nil {
			return nil, nil, err
		}
		if len(around.Prefixes()) > wgRouteBudget {
			break
		}
		routesLeft = around
	}
	return routesLeft, excluded, nil
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

// Before the VPN is up, and the app stays out of it: the device's own DNS, as the official app resolves it.
func lookupEndpoint(host string) (netip.Addr, error) {
	if ip, err := netip.ParseAddr(host); err == nil {
		return ip.Unmap(), nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	if err != nil {
		return netip.Addr{}, err
	}
	for _, ip := range ips {
		if ip.Unmap().Is4() {
			return ip.Unmap(), nil
		}
	}
	if len(ips) == 0 {
		return netip.Addr{}, errors.New("no address")
	}
	return ips[0], nil
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
	// A device a ping left in mihomo's client of this server would answer with the same key. The apply that
	// follows every start builds that client again, idle.
	if proxy := tunnel.AllProxies()[prepared.server]; proxy != nil && proxy.Type() == constant.WireGuard {
		_ = proxy.Close()
	}
	ownerMu.Lock()
	ownerRunning = owner
	ownerMu.Unlock()
	return nil
}

func startWireGuard(t tun.Device, bind wgconn.Bind, prepared *wgPrepared) (*wgOwner, error) {
	logger := &device.Logger{
		Verbosef: device.DiscardLogf,
		Errorf:   func(format string, args ...any) { log.Warnln("[WG] "+format, args...) },
	}
	dev := device.NewDevice(countingTun{t}, bind, logger)
	if err := dev.IpcSet(prepared.uapi); err != nil {
		dev.Close()
		return nil, err
	}
	dev.DisableSomeRoamingForBrokenMobileSemantics()
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, err
	}
	return &wgOwner{server: prepared.server, dev: dev, peer: dev.LookupPeer(prepared.peer)}, nil
}

func stopOwner() {
	ownerMu.Lock()
	owner := ownerRunning
	ownerRunning = nil
	ownerMu.Unlock()
	if owner != nil {
		owner.dev.Close()
	}
}

func ownerFor(server string) *wgOwner {
	ownerMu.Lock()
	defer ownerMu.Unlock()
	if ownerRunning != nil && ownerRunning.server == server {
		return ownerRunning
	}
	return nil
}

// testDelay is the time a fresh handshake takes: the server's own answer, through the socket that carries the
// tunnel. wireguard-go sends at most one initiation per 5 s, so a ping right after another waits on that one.
func (o *wgOwner) testDelay(params *TestDelayParams) *Delay {
	delay := &Delay{Name: params.ProxyName, Url: params.TestUrl, Value: -1}
	start := time.Now()
	if o.peer == nil || o.peer.SendHandshakeInitiation(false) != nil {
		return delay
	}
	for deadline := start.Add(delayTestTimeout(params.Timeout)); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		if at := o.lastHandshake(); !at.Before(start) {
			delay.Value = int32(max(at.Sub(start).Milliseconds(), 1))
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

// shikooOwnerKey is markCores' mark for the official engine; mihomo's parser drops it, and still carries the server.
const shikooOwnerKey = "shikoo-owner"

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
