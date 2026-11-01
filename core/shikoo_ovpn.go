package main

import (
	"context"
	"errors"
	"fmt"
	"net/netip"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/structure"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	ovpn "github.com/metacubex/mihomo/transport/openvpn"
	"go4.org/netipx"
)

// The official OpenVPN engine (docs/multi-core.md, h3) is OpenVPN 3 under the VPN service (OpenVpn.kt): Go gives it the
// profile and the routes, and keeps the registry's view of it, which the service reports.

const (
	shikooOpenvpnTunnelMethod CoreMethod = "shikooOpenvpnTunnel"
	shikooOpenvpnStateMethod  CoreMethod = "shikooOpenvpnState"
)

// Keys the official engine cannot honour: such a server's start fails, as OpenVPN has no mihomo to fall back to.
var ovpnRefusedKeys = []string{"dialer-proxy", "peer-info"}

type ovpnPlan struct {
	Profile  string `json:"ovpn"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type ovpnSession struct {
	server     string
	config     *ovpn.ClientConfig
	iranDirect bool
	id         int
	up         bool
}

type ovpnTunnelSpec struct {
	Addresses []string `json:"addresses"`
	DNS       []string `json:"dns"`
	MTU       int      `json:"mtu"`
}

type ovpnStateParams struct {
	Session int    `json:"session"`
	Server  string `json:"server"`
	Up      bool   `json:"up"`
}

var (
	ovpnPrepared atomic.Pointer[ovpnSession]
	// Atomic, as the registry's carrying must answer at once and take no lock.
	ovpnNow atomic.Pointer[ovpnSession]
)

func init() {
	registerMethod(shikooOpenvpnTunnelMethod, withArguments(func(spec *ovpnTunnelSpec, response MethodResponse) {
		safeGo(response, func() {
			plan, err := ovpnTunnel(spec, int(sdkVersion.Load()))
			if err != nil {
				response.failure("openvpn_tunnel", err.Error(), nil)
				return
			}
			response.success(plan)
		})
	}))
	registerMethod(shikooOpenvpnStateMethod, withArguments(func(params *ovpnStateParams, response MethodResponse) {
		ovpnState(params)
		response.success(true)
	}))
}

// ovpnPrepare reads a mapping the way mihomo's OpenVPN outbound does (adapter/outbound/openvpn.go), so a key both
// read means the same in both cores, and writes it as the profile OpenVPN 3 reads.
func ovpnPrepare(mapping map[string]any, iranDirect, held bool) (*ovpnPlan, error) {
	config, err := ovpnSessionOf(mapping, iranDirect)
	if err != nil {
		return nil, err
	}
	// OpenVPN 3 dials a remote name through the VPN a switch holds, where no DNS answers; the pings keep the name.
	dialed := *config
	dialed.RemoteHost = pinnedHost(config.RemoteHost, held)
	return &ovpnPlan{Profile: ovpnProfile(&dialed), Username: config.Username, Password: config.Password}, nil
}

func ovpnConfig(mapping map[string]any) (string, *ovpn.ClientConfig, error) {
	var option outbound.OpenVPNOption
	decoder := structure.NewDecoder(structure.Option{TagName: "proxy", WeaklyTypedInput: true, KeyReplacer: structure.DefaultKeyReplacer})
	if err := decoder.Decode(mapping, &option); err != nil {
		return "", nil, err
	}
	config := &ovpn.ClientConfig{
		RemoteHost:   option.Server,
		RemotePort:   uint16(option.Port),
		Proto:        option.Proto,
		Dev:          option.Dev,
		Cipher:       option.Cipher,
		Auth:         option.Auth,
		CompLZO:      option.CompLZO,
		CA:           []byte(option.CA),
		Cert:         []byte(option.Cert),
		Key:          []byte(option.Key),
		TLSAuth:      []byte(option.TLSAuth),
		KeyDirection: option.KeyDirection,
		TLSCrypt:     []byte(option.TLSCrypt),
		TLSCryptV2:   []byte(option.TLSCryptV2),
		Username:     option.Username,
		Password:     option.Password,
		PingInterval: time.Duration(option.Ping) * time.Second,
		PingRestart:  time.Duration(option.PingRestart) * time.Second,
	}
	if err := config.Prepare(); err != nil {
		return "", nil, err
	}
	return option.Name, config, nil
}

// ovpnProfile states mihomo's defaults (Prepare's cipher and auth) instead of leaving OpenVPN 3 its own.
func ovpnProfile(c *ovpn.ClientConfig) string {
	proto := "udp"
	if c.Proto == ovpn.ProtoTCP {
		proto = "tcp-client"
	}
	lines := []string{
		"client", "dev tun", "nobind", "proto " + proto,
		"remote " + c.RemoteHost + " " + strconv.Itoa(int(c.RemotePort)),
		"cipher " + c.Cipher, "auth " + c.Auth,
	}
	if c.Username != "" {
		lines = append(lines, "auth-user-pass")
	}
	if c.KeyDirection != "" {
		lines = append(lines, "key-direction "+c.KeyDirection)
	}
	if c.CompLZO != "" {
		lines = append(lines, "comp-lzo "+c.CompLZO)
	}
	if c.PingInterval > 0 {
		lines = append(lines, "ping "+strconv.Itoa(int(c.PingInterval.Seconds())))
	}
	if c.PingRestart > 0 {
		lines = append(lines, "ping-restart "+strconv.Itoa(int(c.PingRestart.Seconds())))
	}
	for _, block := range []struct {
		tag  string
		body []byte
	}{{"ca", c.CA}, {"cert", c.Cert}, {"key", c.Key}, {"tls-auth", c.TLSAuth}, {"tls-crypt", c.TLSCrypt}, {"tls-crypt-v2", c.TLSCryptV2}} {
		if body := strings.TrimSpace(string(block.body)); body != "" {
			lines = append(lines, "<"+block.tag+">", body, "</"+block.tag+">")
		}
	}
	return strings.Join(lines, "\n") + "\n"
}

func ovpnTunnel(spec *ovpnTunnelSpec, sdk int) (*ownerPlan, error) {
	session := ovpnPrepared.Load()
	if session == nil {
		return nil, errors.New("no server prepared")
	}
	// All of a family the tunnel has an address in goes through it, whatever routes the server pushed (the lead,
	// 2026-10-28); Android blocks a family it has nothing of, which a DNS server alone would open outside it.
	carried := map[bool]bool{}
	var b netipx.IPSetBuilder
	for _, value := range spec.Addresses {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return nil, err
		}
		carried[prefix.Addr().Is4()] = true
		every := netip.IPv6Unspecified()
		if prefix.Addr().Is4() {
			every = netip.IPv4Unspecified()
		}
		b.AddPrefix(netip.PrefixFrom(every, 0))
	}
	routes, err := b.IPSet()
	if err != nil {
		return nil, err
	}
	plan := &ownerPlan{Addresses: spec.Addresses, DNS: []string{}, MTU: spec.MTU, Excluded: []string{}}
	for _, value := range spec.DNS {
		if ip, err := netip.ParseAddr(value); err == nil && carried[ip.Unmap().Is4()] {
			plan.DNS = append(plan.DNS, value)
		}
	}
	if plan.MTU <= 0 {
		plan.MTU = 1500
	}
	if session.iranDirect {
		// A missing set only sends Iranian sites through the server, as it does for mihomo's rule.
		if iran, err := readIPSet(filepath.Join(constant.Path.HomeDir(), "shikoo-ir-ip.mrs")); err != nil {
			log.Warnln("[OpenVPN] Iranian ranges not read: %v", err)
		} else if routes, plan.Excluded, err = cutIran(routes, iran, sdk >= excludeRouteSdk); err != nil {
			return nil, err
		}
	}
	plan.Routes = prefixStrings(routes)
	return plan, nil
}

// ovpnState: the service's word on its engine. "" for a session that is no longer the latest leaves the new one.
func ovpnState(params *ovpnStateParams) {
	if params.Server == "" {
		if now := ovpnNow.Load(); now != nil && now.id == params.Session {
			ovpnNow.CompareAndSwap(now, nil)
		}
		return
	}
	next := &ovpnSession{server: params.Server, id: params.Session, up: params.Up}
	if prepared := ovpnPrepared.Load(); prepared != nil && prepared.server == params.Server {
		next.config = prepared.config
	}
	if was := ovpnNow.Swap(next); was == nil || was.server != params.Server {
		shikooOwnerTakes(params.Server)
	}
	if params.Up {
		ovpnUp()
	}
}

var ovpnUp = func() {}

func ovpnCarrying() string {
	if now := ovpnNow.Load(); now != nil {
		return now.server
	}
	return buildingFor("openvpn")
}

var ovpnEnded atomic.Pointer[ovpnOutcome]

type ovpnOutcome struct {
	state  string
	reason string
}

func ovpnOwnerState() string {
	if ended := ovpnEnded.Load(); ended != nil {
		return ended.state
	}
	if now := ovpnNow.Load(); now != nil {
		if now.up {
			return stateUp
		}
		return stateConnecting
	}
	return ""
}

// ovpnSessionOf stores what the next session runs; Windows looks the name up on the session's own goroutine, off configMu.
func ovpnSessionOf(mapping map[string]any, iranDirect bool) (*ovpn.ClientConfig, error) {
	for _, key := range ovpnRefusedKeys {
		if _, set := mapping[key]; set {
			return nil, fmt.Errorf("the official engine cannot honour %s", key)
		}
	}
	name, config, err := ovpnConfig(mapping)
	if err != nil {
		return nil, err
	}
	ovpnPrepared.Store(&ovpnSession{server: name, config: config, iranDirect: iranDirect})
	return config, nil
}

// ovpnPinned puts the server's address for its name in the profile: a reconnect would look it up through the tunnel's down DNS.
func ovpnPinned(c *ovpn.ClientConfig, ip netip.Addr) string {
	pinned := *c
	pinned.RemoteHost = ip.String()
	return ovpnProfile(&pinned)
}

// ovpnPing: the server's answer to a session reset while the engine's own session is up, from which it takes nothing.
func ovpnPing(params *TestDelayParams) *Delay {
	if now := ovpnNow.Load(); now != nil && now.up && now.server == params.ProxyName {
		return ovpnDelay(params, now.config)
	}
	return ovpnDelay(params, nil)
}

func ovpnIdlePing(mapping map[string]any, params *TestDelayParams) *Delay {
	_, config, _ := ovpnConfig(mapping)
	return ovpnDelay(params, config)
}

func ovpnDelay(params *TestDelayParams, c *ovpn.ClientConfig) *Delay {
	delay := &Delay{Name: params.ProxyName, Url: params.TestUrl, Value: -1}
	if c == nil {
		return delay
	}
	if rtt, err := ovpnProbe(c, delayTestTimeout(params.Timeout)); err == nil {
		delay.Value = int32(max(rtt.Milliseconds(), 1))
	}
	return delay
}

const ovpnResendAfter = 500 * time.Millisecond

// ovpnProbe dials as mihomo's client does (its resolver, Android's protect), and times a UDP resend from the first reset.
func ovpnProbe(c *ovpn.ClientConfig, timeout time.Duration) (time.Duration, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	conn, err := dialer.DialContext(ctx, c.Proto, c.RemoteAddress())
	if err != nil {
		return 0, err
	}
	io := ovpn.NewDatagramPacketIO(conn)
	if c.Proto == ovpn.ProtoTCP {
		io = ovpn.NewTCPPacketIO(conn)
	}
	mux := ovpn.NewPacketMux(io)
	go mux.Run()
	defer mux.Close()
	var crypt ovpn.ControlCryptor
	switch {
	case len(c.TLSCryptV2Key) > 0:
		crypt, err = ovpn.NewTLSCryptV2(c.TLSCryptV2Key, c.TLSCryptV2WrappedKey)
	case len(c.TLSCryptKey) > 0:
		crypt, err = ovpn.NewTLSCrypt(c.TLSCryptKey, true)
	case len(c.TLSAuthKey) > 0:
		crypt, err = ovpn.NewTLSAuth(c.TLSAuthKey, c.KeyDirection, c.Auth)
	}
	if err != nil {
		return 0, err
	}
	id, err := ovpn.NewSessionID()
	if err != nil {
		return 0, err
	}
	control := ovpn.NewControlChannel(mux, crypt, id)
	start := time.Now()
	if err := control.SendReset(ctx); err != nil {
		return 0, err
	}
	if c.Proto != ovpn.ProtoTCP {
		resend := time.AfterFunc(ovpnResendAfter, func() { _ = control.RetransmitPending(ctx) })
		defer resend.Stop()
	}
	reply, err := control.Read(ctx)
	if err != nil {
		return 0, err
	}
	if reply.Opcode != ovpn.PControlHardResetServerV2 {
		return 0, fmt.Errorf("the server answered %v", reply.Opcode)
	}
	return time.Since(start), nil
}
