package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
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
	config, err := json.Marshal(map[string]any{
		"log":      map[string]any{"loglevel": "warning"},
		"inbounds": inbounds, "outbounds": outbounds,
		"routing": map[string]any{"rules": rules},
	})
	if err != nil {
		return nil, nil, err
	}
	instance, err := xcore.StartInstance("json", config)
	if err != nil {
		return nil, nil, err
	}
	// Xray's own log app took the handler while it started; mihomo's log is the one the app reads.
	xlog.RegisterHandler(xrayLog{})
	return replacements, func() { _ = instance.Close() }, nil
}

// xrayOutbound is checked by Xray's own config builder, so what it refuses (VLESS without TLS to a public
// address, REALITY on ws, …) stays with mihomo too.
func xrayOutbound(proxy map[string]any) (map[string]any, error) {
	var basic outbound.BasicOption
	if err := xrayDecoder.Decode(proxy, &basic); err != nil {
		return nil, err
	}
	if basic.DialerProxy != "" || basic.Interface != "" || basic.RoutingMark != 0 || basic.IPVersion != 0 {
		return nil, errors.New("a dialer option only mihomo honours")
	}
	if mux, _ := proxy["smux"].(map[string]any); mux["enabled"] == true {
		return nil, errors.New("sing-mux")
	}
	var out map[string]any
	var err error
	switch proxy["type"] {
	case "vless":
		out, err = xrayVless(proxy)
	case "wireguard":
		out, err = xrayWireGuard(proxy)
	default:
		err = fmt.Errorf("type %v", proxy["type"])
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
	switch {
	// allowInsecure is gone from Xray; pinning and client certificates have no mapping written here.
	case o.SkipCertVerify || o.Fingerprint != "" || o.Certificate != "" || o.NameCertVerify != "":
		return nil, errors.New("certificate options")
	case o.ECHOpts.Enable || o.ShadowTLSOpts != (outbound.ShadowTLSOptions{}) ||
		o.RestlsOpts != (outbound.RestlsOptions{}) || o.JLSOpts != (outbound.JLSOptions{}):
		return nil, errors.New("a TLS wrapper Xray lacks")
	case len(o.WSHeaders) > 0:
		return nil, errors.New("ws-headers")
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
	switch {
	case len(o.Peers) > 0:
		return nil, errors.New("several peers")
	case o.AmneziaWGOption != nil:
		return nil, errors.New("AmneziaWG")
	case len(o.Reserved) != 0 && len(o.Reserved) != 3:
		return nil, errors.New("reserved is not three bytes")
	}
	// Xray would ask the system resolver, which answers fake-ip inside the tunnel.
	// shortcut: a server named by a domain is resolved once per config; upgrade if a panel's WireGuard host moves.
	ctx, cancel := context.WithTimeout(context.Background(), resolver.DefaultDNSTimeout)
	defer cancel()
	ip, err := resolver.ResolveIPWithResolver(resolver.WithInitiator(ctx, resolver.InitiatorProxy), o.Server, resolver.ProxyServerHostResolver)
	if err != nil {
		return nil, err
	}
	var addresses []string
	for _, address := range []string{o.Ip, o.Ipv6} {
		if address != "" {
			addresses = append(addresses, address)
		}
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

func freeLoopbackPort() (int, error) {
	for range 8 {
		tcp, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return 0, err
		}
		port := tcp.Addr().(*net.TCPAddr).Port
		udp, err := net.ListenPacket("udp", fmt.Sprintf("127.0.0.1:%d", port))
		_ = tcp.Close()
		if err == nil {
			_ = udp.Close()
			return port, nil
		}
	}
	return 0, errors.New("no free loopback port for both TCP and UDP")
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
