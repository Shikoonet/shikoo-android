package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"slices"
	"strings"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/structure"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/log"
	xlog "github.com/xtls/xray-core/common/log"
	xnet "github.com/xtls/xray-core/common/net"
	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf"
	_ "github.com/xtls/xray-core/main/distro/all"
	"github.com/xtls/xray-core/transport/internet"
)

// Xray behind mihomo (docs/multi-core.md, package h1): each server becomes an authenticated SOCKS on loopback.
func init() {
	internet.UseAlternativeSystemDialer(xrayDialer{})
	xlog.RegisterHandler(xrayLog{})
	registerShikooCore("xray", startXray)
}

const xrayUser = "shikoo"

var xrayDecoder = structure.NewDecoder(structure.Option{TagName: "proxy", WeaklyTypedInput: true, KeyReplacer: structure.DefaultKeyReplacer})

// A server with a key the conversion does not read stays with mihomo; core/testdata/xray_serves.json holds Dart to this.
var xrayKeys = map[any]string{
	"vless": "uuid flow tls alpn servername client-fingerprint reality-opts network ws-opts grpc-opts xhttp-opts " +
		"encryption packet-encoding xudp packet-addr skip-cert-verify smux",
	"wireguard": "ip ipv6 private-key public-key pre-shared-key reserved allowed-ips mtu persistent-keepalive dns " +
		"remote-dns-resolve",
}

// startXray leaves a server Xray cannot carry to mihomo by handing its own mapping back.
func startXray(proxies []map[string]any) ([]map[string]any, func(), error) {
	replacements := make([]map[string]any, len(proxies))
	var inbounds, outbounds, rules []any
	for i, proxy := range proxies {
		replacements[i] = proxy
		out, err := xrayOutbound(proxy)
		if err != nil {
			log.Warnln("[SHIKOO] xray cannot carry %v, mihomo does: %v", proxy["name"], err)
			continue
		}
		port, err := freeLoopbackPort()
		if err != nil {
			return nil, nil, err
		}
		password := rand.Text()
		in, to := fmt.Sprint("in", i), fmt.Sprint("out", i)
		out["tag"] = to
		outbounds = append(outbounds, out)
		inbounds = append(inbounds, map[string]any{
			"tag": in, "listen": "127.0.0.1", "port": port, "protocol": "socks",
			"settings": map[string]any{
				"auth": "password", "accounts": []any{map[string]any{"user": xrayUser, "pass": password}},
				"udp": true, "ip": "127.0.0.1",
			},
		})
		rules = append(rules, map[string]any{"inboundTag": []string{in}, "outboundTag": to})
		replacements[i] = map[string]any{
			"name": proxy["name"], "type": "socks5", "server": "127.0.0.1", "port": port,
			"username": xrayUser, "password": password, "udp": proxy["udp"] == true,
		}
	}
	if len(outbounds) == 0 {
		return replacements, func() {}, nil
	}
	stop, err := runXray(map[string]any{
		"log":      map[string]any{"loglevel": "warning"},
		"inbounds": inbounds, "outbounds": outbounds,
		"routing": map[string]any{"rules": rules},
	})
	if err != nil {
		return nil, nil, err
	}
	return replacements, stop, nil
}

// runXray turns a panic inside Xray into an error: the apply stands, and mihomo carries these servers.
func runXray(config map[string]any) (stop func(), err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("xray panicked: %v", r)
		}
	}()
	raw, err := json.Marshal(config)
	if err != nil {
		return nil, err
	}
	instance, err := xcore.StartInstance("json", raw)
	if err != nil {
		return nil, err
	}
	// Xray's own log app took the handler while it started; mihomo's log is the one the app reads.
	xlog.RegisterHandler(xrayLog{})
	return func() { _ = instance.Close() }, nil
}

// xrayOutbound is checked by Xray's own config builder, so what it refuses (VLESS without TLS to a public
// address, REALITY on ws, …) stays with mihomo too.
func xrayOutbound(proxy map[string]any) (map[string]any, error) {
	keys, known := xrayKeys[proxy["type"]]
	if !known {
		return nil, fmt.Errorf("type %v", proxy["type"])
	}
	allowed := strings.Fields("name type server port udp " + keys)
	for key := range proxy {
		if !slices.Contains(allowed, key) {
			return nil, fmt.Errorf("key %s", key)
		}
	}
	if mux, _ := proxy["smux"].(map[string]any); mux["enabled"] == true {
		return nil, errors.New("sing-mux")
	}
	var out map[string]any
	var err error
	if proxy["type"] == "vless" {
		out, err = xrayVless(proxy)
	} else {
		out, err = xrayWireGuard(proxy)
	}
	if err != nil {
		return nil, err
	}
	raw, err := json.Marshal(out)
	if err != nil {
		return nil, err
	}
	var check conf.OutboundDetourConfig
	if err := json.Unmarshal(raw, &check); err != nil {
		return nil, err
	}
	if _, err := check.Build(); err != nil {
		return nil, err
	}
	return out, nil
}

func xrayVless(proxy map[string]any) (map[string]any, error) {
	var o outbound.VlessOption
	if err := xrayDecoder.Decode(proxy, &o); err != nil {
		return nil, err
	}
	if o.SkipCertVerify {
		return nil, errors.New("skip-cert-verify")
	}

	stream := map[string]any{"network": "raw"}
	switch o.Network {
	case "", "tcp":
	case "ws":
		headers, host := withoutHost(o.WSOpts.Headers)
		settings := map[string]any{"path": o.WSOpts.Path, "host": host, "headers": headers}
		switch {
		case o.WSOpts.V2rayHttpUpgrade:
			stream["network"], stream["httpupgradeSettings"] = "httpupgrade", settings
		case o.WSOpts.MaxEarlyData > 0 && o.WSOpts.EarlyDataHeaderName != "Sec-WebSocket-Protocol":
			return nil, errors.New("ws early data outside Sec-WebSocket-Protocol")
		default:
			if o.WSOpts.MaxEarlyData > 0 {
				settings["path"] = fmt.Sprintf("%s?ed=%d", o.WSOpts.Path, o.WSOpts.MaxEarlyData)
			}
			stream["network"], stream["wsSettings"] = "ws", settings
		}
	case "grpc":
		stream["network"] = "grpc"
		stream["grpcSettings"] = map[string]any{"serviceName": o.GrpcOpts.GrpcServiceName, "user_agent": o.GrpcOpts.GrpcUserAgent}
	case "xhttp":
		x := o.XHTTPOpts
		if x.DownloadSettings != nil {
			return nil, errors.New("xhttp download-settings")
		}
		if lo, hi, err := conf.ParseRangeString(x.ScMaxEachPostBytes); err == nil && min(lo, hi) <= 0 && max(lo, hi) > 0 {
			return nil, errors.New("sc-max-each-post-bytes from 0, on which Xray's first dial panics")
		}
		settings := map[string]any{
			"path": x.Path, "host": x.Host, "mode": x.Mode, "headers": x.Headers, "noGRPCHeader": x.NoGRPCHeader,
			"xPaddingObfsMode": x.XPaddingObfsMode,
		}
		for key, value := range map[string]string{
			"xPaddingBytes": x.XPaddingBytes, "xPaddingKey": x.XPaddingKey, "xPaddingHeader": x.XPaddingHeader,
			"xPaddingPlacement": x.XPaddingPlacement, "xPaddingMethod": x.XPaddingMethod,
			"uplinkHTTPMethod": x.UplinkHTTPMethod, "sessionIDPlacement": x.SessionPlacement,
			"sessionIDKey": x.SessionKey, "sessionIDTable": x.SessionTable, "sessionIDLength": x.SessionLength,
			"seqPlacement": x.SeqPlacement, "seqKey": x.SeqKey, "uplinkDataPlacement": x.UplinkDataPlacement,
			"uplinkDataKey": x.UplinkDataKey, "uplinkChunkSize": x.UplinkChunkSize,
			"scMaxEachPostBytes": x.ScMaxEachPostBytes, "scMinPostsIntervalMs": x.ScMinPostsIntervalMs,
		} {
			if value != "" {
				settings[key] = value
			}
		}
		if r := x.ReuseSettings; r != nil {
			xmux := map[string]any{"hKeepAlivePeriod": r.HKeepAlivePeriod}
			for key, value := range map[string]string{
				"maxConcurrency": r.MaxConcurrency, "maxConnections": r.MaxConnections,
				"cMaxReuseTimes": r.CMaxReuseTimes, "hMaxRequestTimes": r.HMaxRequestTimes,
				"hMaxReusableSecs": r.HMaxReusableSecs,
			} {
				if value != "" {
					xmux[key] = value
				}
			}
			settings["xmux"] = xmux
		}
		stream["network"], stream["xhttpSettings"] = "xhttp", settings
	default:
		return nil, fmt.Errorf("network %s", o.Network)
	}

	fingerprint := o.ClientFingerprint
	if fingerprint == "none" {
		fingerprint = ""
	}
	switch {
	case o.TLS && o.RealityOpts.PublicKey != "":
		stream["security"] = "reality"
		stream["realitySettings"] = map[string]any{
			"serverName": o.ServerName, "fingerprint": fingerprint,
			"publicKey": o.RealityOpts.PublicKey, "shortId": o.RealityOpts.ShortID,
		}
	case o.TLS:
		stream["security"] = "tls"
		stream["tlsSettings"] = map[string]any{"serverName": o.ServerName, "fingerprint": fingerprint, "alpn": o.ALPN}
	}

	encryption := o.Encryption
	if encryption == "" {
		encryption = "none"
	}
	return map[string]any{
		"protocol": "vless",
		"settings": map[string]any{
			"address": o.Server, "port": o.Port, "id": o.UUID, "flow": o.Flow, "encryption": encryption,
		},
		"streamSettings": stream,
	}, nil
}

func xrayWireGuard(proxy map[string]any) (map[string]any, error) {
	var o outbound.WireGuardOption
	if err := xrayDecoder.Decode(proxy, &o); err != nil {
		return nil, err
	}
	if len(o.Reserved) != 0 && len(o.Reserved) != 3 {
		return nil, errors.New("reserved is not three bytes")
	}
	// Xray parses these only as the whole core starts, the DNS by panicking: one bad server would stop them all.
	var addresses []string
	for _, address := range []string{o.Ip, o.Ipv6} {
		if address == "" {
			continue
		}
		if _, err := netip.ParsePrefix(address); err != nil && !isIP(address) {
			return nil, fmt.Errorf("address %s", address)
		}
		addresses = append(addresses, address)
	}
	for _, dns := range o.Dns {
		if !isIP(dns) {
			return nil, fmt.Errorf("dns %s", dns)
		}
	}
	// Xray would ask the system resolver, which answers fake-ip inside the tunnel.
	// shortcut: a server named by a domain is resolved once per config; upgrade if a panel's WireGuard host moves.
	ctx, cancel := context.WithTimeout(context.Background(), resolver.DefaultDNSTimeout)
	defer cancel()
	ip, err := resolver.ResolveIPWithResolver(resolver.WithInitiator(ctx, resolver.InitiatorProxy), o.Server, resolver.ProxyServerHostResolver)
	if err != nil {
		return nil, err
	}
	allowed := o.AllowedIPs
	if len(allowed) == 0 {
		allowed = []string{"0.0.0.0/0", "::/0"}
	}
	settings := map[string]any{
		"secretKey": o.PrivateKey, "address": addresses, "mtu": o.MTU, "noKernelTun": true,
		"peers": []any{map[string]any{
			"publicKey": o.PublicKey, "preSharedKey": o.PreSharedKey, "keepAlive": o.PersistentKeepalive,
			"endpoint": netip.AddrPortFrom(ip, uint16(o.Port)).String(), "allowedIPs": allowed,
		}},
	}
	if len(o.Reserved) == 3 {
		settings["reserved"] = []int{int(o.Reserved[0]), int(o.Reserved[1]), int(o.Reserved[2])}
	}
	if len(o.Dns) > 0 {
		settings["remoteDNS"] = o.Dns
	}
	return map[string]any{"protocol": "wireguard", "settings": settings}, nil
}

func withoutHost(headers map[string]string) (map[string]string, string) {
	rest := map[string]string{}
	host := ""
	for key, value := range headers {
		if strings.EqualFold(key, "Host") {
			host = value
			continue
		}
		rest[key] = value
	}
	return rest, host
}

func isIP(s string) bool {
	_, err := netip.ParseAddr(s)
	return err == nil
}

// shortcut: another process can take the port before Xray binds it, and then mihomo carries every server of this
// apply; upgrade to reading Xray's own listener if that is ever seen.
func freeLoopbackPort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer func() { _ = listener.Close() }()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

// xrayDialer sends Xray's sockets through mihomo's dialer: Android's protect, Windows' interface binding and
// mihomo's real DNS, never the tunnel's fake-ip.
type xrayDialer struct{}

func (xrayDialer) Dial(ctx context.Context, _ xnet.Address, dest xnet.Destination, _ *internet.SocketConfig) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, dialer.DefaultTCPTimeout)
	defer cancel()
	if dest.Network != xnet.Network_UDP {
		return dialer.DialContext(ctx, "tcp", dest.NetAddr())
	}
	host := dest.Address.String()
	if dest.Address.Family().IsIP() {
		host = dest.Address.IP().String()
	}
	ip, err := resolver.ResolveIPWithResolver(resolver.WithInitiator(ctx, resolver.InitiatorProxy), host, resolver.ProxyServerHostResolver)
	if err != nil {
		return nil, err
	}
	to := netip.AddrPortFrom(ip.Unmap(), uint16(dest.Port))
	conn, err := dialer.ListenPacket(ctx, dialer.ParseNetwork("udp", to.Addr()), "", to)
	if err != nil {
		return nil, err
	}
	// Xray's WireGuard and QUIC take the packet conn back out of this wrapper.
	return &xnet.PacketConnWrapper{PacketConn: conn, Dest: net.UDPAddrFromAddrPort(to)}, nil
}

func (xrayDialer) DestIpAddress() net.IP { return nil }

type xrayLog struct{}

func (xrayLog) Handle(msg xlog.Message) {
	if general, ok := msg.(*xlog.GeneralMessage); ok && general.Severity <= xlog.Severity_Warning {
		log.Warnln("[Xray] %s", msg)
		return
	}
	log.Debugln("[Xray] %s", msg)
}

func (xrayLog) Severity() xlog.Severity { return xlog.Severity_Info }
