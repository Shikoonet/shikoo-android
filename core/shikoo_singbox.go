package main

import (
	"cmp"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"net"
	"net/netip"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"

	madapter "github.com/metacubex/mihomo/adapter"
	mihomo "github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/common/structure"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	mDNS "github.com/miekg/dns"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/certificate"
	"github.com/sagernet/sing-box/adapter/endpoint"
	"github.com/sagernet/sing-box/adapter/inbound"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/adapter/service"
	sbdns "github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/dns/transport"
	sblog "github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/block"
	"github.com/sagernet/sing-box/protocol/openvpn"
	"github.com/sagernet/sing-box/protocol/socks"
	"github.com/sagernet/sing-box/protocol/ssh"
	"github.com/sagernet/sing-box/protocol/vless"
	"github.com/sagernet/sing-box/protocol/wireguard"
	"github.com/sagernet/sing/common/bufio"
	sjson "github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
)

func init() {
	registerShikooCore("singBox", startSingBox)
}

// singBoxKeys is every key the conversion reads, per type: a server with any other key stays on mihomo.
// lib/shikoo/engine/core_sing_box.dart keeps the same rules; core/testdata/sing_box_serves.json holds both to them.
var singBoxKeys = map[string]string{
	"vless": "uuid flow tls alpn packet-addr xudp packet-encoding encryption network " +
		"reality-opts ws-opts grpc-opts skip-cert-verify servername client-fingerprint",
	"wireguard": "ip ipv6 private-key public-key pre-shared-key reserved allowed-ips mtu " +
		"persistent-keepalive peers remote-dns-resolve dns",
	"openvpn": "proto dev cipher data-ciphers data-ciphers-fallback auth comp-lzo ca cert key tls-auth " +
		"key-direction tls-crypt tls-crypt-v2 username password ping ping-restart mtu remote-dns-resolve dns",
	"ssh": "username password private-key private-key-passphrase host-key host-key-algorithms",
}

var singBoxOptKeys = map[string]string{
	"reality-opts": "public-key short-id",
	"ws-opts":      "path headers max-early-data early-data-header-name v2ray-http-upgrade",
	"grpc-opts":    "grpc-service-name",
}

const singBoxFingerprints = "none chrome firefox safari ios android edge 360 qq"

var singBoxWireGuardKey = regexp.MustCompile(`^[A-Za-z0-9+/]{43}=$`)

func singBoxServes(proxy map[string]any) bool {
	kind := strings.ToLower(fmt.Sprint(proxy["type"]))
	keys, ok := singBoxKeys[kind]
	if !ok {
		return false
	}
	for key, value := range proxy {
		if !slices.Contains(strings.Fields(keys+" name type server port udp"), key) {
			return false
		}
		opts, _ := value.(map[string]any)
		for inner := range opts {
			if !slices.Contains(strings.Fields(singBoxOptKeys[key]), inner) {
				return false
			}
		}
	}
	if proxy["remote-dns-resolve"] == true && (kind != "wireguard" || singBoxTunnelDNS(proxy) == "") {
		return false
	}
	switch kind {
	case "vless":
		ws, _ := proxy["ws-opts"].(map[string]any)
		earlyUpgrade := ws["v2ray-http-upgrade"] == true &&
			(strings.Contains(fmt.Sprint(ws["path"]), "?") || !singBoxOneOf(ws["max-early-data"], "0"))
		return singBoxOneOf(proxy["encryption"], "none") && singBoxOneOf(proxy["network"], "tcp ws grpc") &&
			singBoxOneOf(proxy["flow"], "xtls-rprx-vision") &&
			singBoxOneOf(proxy["client-fingerprint"], singBoxFingerprints) && !earlyUpgrade
	case "wireguard":
		peers, _ := proxy["peers"].([]any)
		if len(peers) == 0 {
			peers = []any{proxy}
		}
		key := func(value any) bool { return value == nil || singBoxWireGuardKey.MatchString(fmt.Sprint(value)) }
		keys := key(proxy["private-key"])
		for _, peer := range peers {
			peer, ok := peer.(map[string]any)
			keys = keys && ok && key(peer["public-key"]) &&
				(singBoxOneOf(peer["pre-shared-key"], "") || key(peer["pre-shared-key"]))
		}
		mtu, _ := strconv.Atoi(fmt.Sprint(proxy["mtu"]))
		return keys && singBoxMTU(proxy["mtu"]) && (singBoxOneOf(proxy["ipv6"], "") || mtu == 0 || mtu >= 1280)
	case "openvpn":
		return singBoxOneOf(proxy["dev"], "tun") && singBoxMTU(proxy["mtu"])
	}
	return true
}

// shortcut: a server resolving inside its tunnel asks only its first dns, on port 53, through itself; a list if a panel needs one.
func singBoxTunnelDNS(proxy map[string]any) string {
	dns, _ := proxy["dns"].([]any)
	if proxy["remote-dns-resolve"] != true || len(dns) == 0 {
		return ""
	}
	if address, err := netip.ParseAddr(fmt.Sprint(dns[0])); err == nil {
		return address.String()
	}
	return ""
}

// mihomo v1.19.33 checks a WireGuard MTU only when it first dials, after its parser has passed the server.
func singBoxMTU(value any) bool {
	mtu, err := strconv.Atoi(fmt.Sprint(value))
	return value == nil || err == nil && (mtu == 0 || mtu >= 68 && mtu <= 65535)
}

// singBoxOneOf: absent, empty, or one of values.
func singBoxOneOf(value any, values string) bool {
	if value == nil {
		value = ""
	}
	return slices.Contains(strings.Split(" "+values, " "), fmt.Sprint(value))
}

var singBoxDecoder = structure.NewDecoder(structure.Option{TagName: "proxy", WeaklyTypedInput: true,
	KeyReplacer: structure.DefaultKeyReplacer})

// singBoxConvert reads a mapping singBoxServes accepted with mihomo's own decoder, so values mean what they mean to
// mihomo, and says whether mihomo's adapter for it would carry UDP.
func singBoxConvert(ctx context.Context, proxy map[string]any) (out map[string]any, isEndpoint, udp bool, err error) {
	switch strings.ToLower(fmt.Sprint(proxy["type"])) {
	case "vless":
		var o mihomo.VlessOption
		if err = singBoxDecoder.Decode(proxy, &o); err != nil {
			return
		}
		out = map[string]any{"type": "vless", "server": o.Server, "server_port": o.Port, "uuid": o.UUID, "flow": o.Flow}
		if o.PacketEncoding == "packetaddr" || o.PacketEncoding == "packet" || o.PacketAddr && !o.XUDP {
			out["packet_encoding"] = "packetaddr"
		}
		if o.TLS {
			tls := map[string]any{"enabled": true, "server_name": o.ServerName, "insecure": o.SkipCertVerify, "alpn": o.ALPN}
			if o.RealityOpts.PublicKey != "" {
				tls["reality"] = map[string]any{"enabled": true, "public_key": o.RealityOpts.PublicKey,
					"short_id": o.RealityOpts.ShortID}
			}
			if o.ClientFingerprint != "" && o.ClientFingerprint != "none" {
				tls["utls"] = map[string]any{"enabled": true, "fingerprint": o.ClientFingerprint}
			}
			out["tls"] = tls
		}
		switch ws := o.WSOpts; o.Network {
		case "ws":
			// mihomo reads the early-data size from the path's ?ed= (transport/vmess/websocket.go).
			path, early, header := ws.Path, ws.MaxEarlyData, ws.EarlyDataHeaderName
			if u, err := url.Parse(path); err == nil && u.Query().Get("ed") != "" {
				if ed, err := strconv.Atoi(u.Query().Get("ed")); err == nil {
					query := u.Query()
					query.Del("ed")
					u.RawQuery = query.Encode()
					path, early, header = u.String(), ed, "Sec-WebSocket-Protocol"
				}
			}
			out["transport"] = map[string]any{"type": "ws", "path": path, "headers": ws.Headers,
				"max_early_data": max(early, 0), "early_data_header_name": header}
			if ws.V2rayHttpUpgrade {
				out["transport"] = map[string]any{"type": "httpupgrade", "path": ws.Path, "host": ws.Headers["Host"],
					"headers": ws.Headers}
			}
		case "grpc":
			out["transport"] = map[string]any{"type": "grpc", "service_name": o.GrpcOpts.GrpcServiceName}
		}
		return out, false, o.UDP, nil
	case "wireguard":
		var o mihomo.WireGuardOption
		if err = singBoxDecoder.Decode(proxy, &o); err != nil {
			return
		}
		address, err := o.Prefixes()
		if err != nil {
			return nil, false, false, err
		}
		peers := o.Peers
		if len(peers) == 0 {
			// mihomo's single peer takes every local family, whatever allowed-ips says.
			peer := o.WireGuardPeerOption
			peer.AllowedIPs = nil
			if slices.ContainsFunc(address, func(p netip.Prefix) bool { return p.Addr().Is4() }) {
				peer.AllowedIPs = append(peer.AllowedIPs, "0.0.0.0/0")
			}
			if slices.ContainsFunc(address, func(p netip.Prefix) bool { return !p.Addr().Is4() }) {
				peer.AllowedIPs = append(peer.AllowedIPs, "::/0")
			}
			peers = []mihomo.WireGuardPeerOption{peer}
		}
		var sbPeers []any
		for _, peer := range peers {
			if len(peer.Reserved) == 0 {
				peer.Reserved = o.Reserved
			}
			server := peer.Server
			if _, err := netip.ParseAddr(server); err != nil {
				ip, err := resolver.ResolveIPWithResolver(resolver.WithInitiator(ctx, resolver.InitiatorProxy), server,
					resolver.ProxyServerHostResolver)
				if err != nil {
					return nil, false, false, err
				}
				server = ip.String()
			}
			sbPeers = append(sbPeers, map[string]any{"address": server, "port": peer.Port,
				"public_key": peer.PublicKey, "pre_shared_key": peer.PreSharedKey, "allowed_ips": peer.AllowedIPs,
				"reserved": peer.Reserved, "persistent_keepalive_interval": o.PersistentKeepalive})
		}
		out = map[string]any{"type": "wireguard", "address": address, "private_key": o.PrivateKey, "peers": sbPeers,
			"mtu": o.MTU, "detour": "mihomo-unconnected"}
		return out, true, o.UDP, nil
	case "openvpn":
		var o mihomo.OpenVPNOption
		if err = singBoxDecoder.Decode(proxy, &o); err != nil {
			return
		}
		network := "udp"
		if strings.HasPrefix(strings.ToLower(o.Proto), "tcp") {
			network = "tcp"
		}
		tls := map[string]any{"certificate": o.CA}
		if o.Cert != "" {
			tls["client_certificate"], tls["client_key"] = o.Cert, o.Key
		}
		switch {
		case o.TLSAuth != "":
			tls["control_wrap"] = map[string]any{"type": "tls_auth", "key": o.TLSAuth,
				"direction": map[string]string{"0": "server", "1": "client"}[o.KeyDirection]}
		case o.TLSCrypt != "":
			tls["control_wrap"] = map[string]any{"type": "tls_crypt", "key": o.TLSCrypt}
		case o.TLSCryptV2 != "":
			tls["control_wrap"] = map[string]any{"type": "tls_crypt_v2", "key": o.TLSCryptV2}
		}
		ciphers := []string{singBoxOpenVPNName(o.Cipher, "AES-128-GCM")}
		if len(o.DataCiphers) > 0 {
			ciphers = nil
			for _, cipher := range o.DataCiphers {
				ciphers = append(ciphers, singBoxOpenVPNName(cipher, "AES-128-GCM"))
			}
		}
		out = map[string]any{"type": "openvpn-client", "server": o.Server, "server_port": o.Port, "network": network,
			"tls": tls, "username": o.Username, "password": o.Password, "data_ciphers": ciphers, "mtu": o.MTU,
			"auth": singBoxOpenVPNName(o.Auth, "SHA256"), "data_ciphers_fallback": singBoxOpenVPNName(
				cmp.Or(o.DataCipherFallback, o.Cipher), "AES-128-GCM"),
			"ping_interval": strconv.Itoa(o.Ping) + "s", "ping_restart": strconv.Itoa(o.PingRestart) + "s",
			"domain_resolver": "proxy-server"}
		// mihomo frames compression only for yes and adaptive; sing-box frames "no" too.
		if lzo := strings.ToLower(strings.TrimSpace(o.CompLZO)); lzo == "yes" || lzo == "adaptive" {
			out["compression_lzo"] = "yes"
		}
		return out, true, true, nil
	case "ssh":
		var o mihomo.SshOption
		if err = singBoxDecoder.Decode(proxy, &o); err != nil {
			return
		}
		out = map[string]any{"type": "ssh", "server": o.Server, "server_port": o.Port, "user": o.UserName,
			"password": o.Password, "private_key_passphrase": o.PrivateKeyPassphrase, "host_key": o.HostKey,
			"host_key_algorithms": o.HostKeyAlgorithms}
		if strings.Contains(o.PrivateKey, "PRIVATE KEY") {
			out["private_key"] = o.PrivateKey
		} else if o.PrivateKey != "" {
			path := C.Path.Resolve(o.PrivateKey)
			if !C.Path.IsSafePath(path) {
				return nil, false, false, C.Path.ErrNotSafePath(path)
			}
			out["private_key_path"] = path
		}
		return out, false, false, nil
	}
	return nil, false, false, fmt.Errorf("sing-box does not carry %v", proxy["type"])
}

func singBoxOpenVPNName(name, empty string) string {
	name = strings.ToUpper(strings.TrimSpace(name))
	return cmp.Or(map[string]string{"": empty, "AES-CBC": "AES-128-CBC", "SHA-1": "SHA1"}[name], name)
}

type singBoxServer struct {
	index           int
	out             map[string]any
	isEndpoint, udp bool
	dns             string
}

// startSingBox runs one sing-box for the servers it can carry, each a SOCKS user on one loopback port.
func startSingBox(proxies []map[string]any) ([]map[string]any, func(), error) {
	ports, release, err := loopbackPorts(1)
	if err != nil {
		return nil, nil, err
	}
	defer forgetPorts(ports...)
	defer release()
	port := ports[0]
	password := rand.Text()
	// WireGuard's server names resolve once as mihomo's do (sing-box's at each rekey), together: the apply holds configMu.
	ctx, cancel := context.WithTimeout(context.Background(), resolver.DefaultDNSTimeout)
	converted, convertErrs := make([]singBoxServer, len(proxies)), make([]error, len(proxies))
	var group sync.WaitGroup
	for i, proxy := range proxies {
		if singBoxServes(proxy) {
			group.Go(func() {
				c := &converted[i]
				c.out, c.isEndpoint, c.udp, convertErrs[i] = singBoxConvert(ctx, proxy)
			})
		}
	}
	group.Wait()
	cancel()
	var servers []singBoxServer
	for i, proxy := range proxies {
		if !singBoxServes(proxy) {
			continue
		}
		// What mihomo's parser refuses fails on mihomo too, so it stays there.
		parsed, err := madapter.ParseProxy(maps.Clone(proxy))
		if err == nil {
			parsed.Close()
		}
		if err = errors.Join(err, convertErrs[i]); err != nil {
			log.Warnln("[SHIKOO] sing-box cannot carry %v; mihomo does: %v", proxy["name"], err)
			continue
		}
		server := converted[i]
		server.index, server.dns = i, singBoxTunnelDNS(proxy)
		server.out["tag"] = "s" + strconv.Itoa(i)
		if server.out["detour"] == nil {
			server.out["detour"] = "mihomo"
		}
		servers = append(servers, server)
	}
	if len(servers) == 0 {
		return proxies, func() {}, nil
	}
	release()
	instance, err := singBoxNew(singBoxConfig(port, password, servers), true)
	if err != nil {
		// One server sing-box refuses would take every other to mihomo: each refused one stays there alone.
		kept := slices.DeleteFunc(slices.Clone(servers), func(server singBoxServer) bool {
			check, err := singBoxNew(singBoxConfig(port, password, []singBoxServer{server}), true)
			if err != nil {
				log.Warnln("[SHIKOO] sing-box cannot carry %v; mihomo does: %v", proxies[server.index]["name"], err)
				return true
			}
			check.Close()
			return false
		})
		if len(kept) == 0 || len(kept) == len(servers) {
			return nil, nil, err
		}
		servers = kept
		if instance, err = singBoxNew(singBoxConfig(port, password, servers), true); err != nil {
			return nil, nil, err
		}
	}
	replacements := slices.Clone(proxies)
	for _, server := range servers {
		replacements[server.index] = map[string]any{"name": proxies[server.index]["name"], "type": "socks5",
			"server": "127.0.0.1", "port": port, "username": server.out["tag"], "password": password, "udp": server.udp}
	}
	return replacements, func() { instance.Close() }, nil
}

func singBoxConfig(port int, password string, servers []singBoxServer) map[string]any {
	outbounds := []any{map[string]any{"type": "mihomo", "tag": "mihomo"}, map[string]any{"type": "block", "tag": "block"},
		map[string]any{"type": "mihomo", "tag": "mihomo-unconnected"}}
	dnsServers := []any{map[string]any{"type": "mihomo", "tag": "resolver"},
		map[string]any{"type": "mihomo-proxy-server", "tag": "proxy-server"}}
	var endpoints, users, rules, dnsRules []any
	for _, server := range servers {
		if server.isEndpoint {
			endpoints = append(endpoints, server.out)
		} else {
			outbounds = append(outbounds, server.out)
		}
		users = append(users, map[string]any{"username": server.out["tag"], "password": password})
		rules = append(rules, map[string]any{"auth_user": server.out["tag"], "outbound": server.out["tag"]})
		if server.dns != "" {
			tag := "dns-" + fmt.Sprint(server.out["tag"])
			dnsServers = append(dnsServers, map[string]any{"type": "udp", "tag": tag, "server": server.dns,
				"detour": server.out["tag"]})
			dnsRules = append(dnsRules, map[string]any{"auth_user": server.out["tag"], "server": tag})
		}
	}
	return map[string]any{
		"log": map[string]any{"level": "warn"},
		"dns": map[string]any{"final": "resolver", "servers": dnsServers, "rules": dnsRules},
		"inbounds": []any{map[string]any{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": port,
			"users": users}},
		"outbounds": outbounds,
		"endpoints": endpoints,
		"route":     map[string]any{"rules": rules, "final": "block"},
	}
}

// singBoxNew registers only what startSingBox writes, so the rest of sing-box stays out of the binary.
func singBoxNew(config map[string]any, start bool) (instance *box.Box, err error) {
	// sing-box panics on some input it should refuse (a REALITY short_id over 8 bytes), and this goroutine is mihomo's.
	defer func() {
		if r := recover(); r != nil {
			if instance != nil {
				instance.Close()
			}
			instance, err = nil, fmt.Errorf("sing-box: %v", r)
		}
	}()
	inbounds := inbound.NewRegistry()
	socks.RegisterInbound(inbounds)
	outbounds := outbound.NewRegistry()
	block.RegisterOutbound(outbounds)
	vless.RegisterOutbound(outbounds)
	ssh.RegisterOutbound(outbounds)
	outbound.Register[option.StubOptions](outbounds, "mihomo", func(_ context.Context, _ adapter.Router,
		_ sblog.ContextLogger, tag string, _ option.StubOptions) (adapter.Outbound, error) {
		return &singBoxMihomo{outbound.NewAdapter("mihomo", tag, []string{"tcp", "udp"}, nil)}, nil
	})
	endpoints := endpoint.NewRegistry()
	wireguard.RegisterEndpoint(endpoints)
	openvpn.RegisterEndpoint(endpoints)
	transports := sbdns.NewTransportRegistry()
	transport.RegisterUDP(transports)
	for kind, use := range map[string]*resolver.Resolver{
		"mihomo":              &resolver.DefaultResolver,
		"mihomo-proxy-server": &resolver.ProxyServerHostResolver,
	} {
		sbdns.RegisterTransport[option.StubOptions](transports, kind, func(_ context.Context, _ sblog.ContextLogger,
			tag string, _ option.StubOptions) (adapter.DNSTransport, error) {
			return &singBoxResolver{sbdns.NewTransportAdapter(kind, tag, nil), use}, nil
		})
	}
	ctx := box.Context(context.Background(), inbounds, outbounds, endpoints, transports, service.NewRegistry(),
		certificate.NewRegistry())
	content, err := json.Marshal(config)
	if err != nil {
		return nil, err
	}
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, content)
	if err != nil {
		return nil, err
	}
	if instance, err = box.New(box.Options{Context: ctx, Options: options}); err != nil || !start {
		return instance, err
	}
	if err = instance.Start(); err != nil {
		instance.Close()
		return nil, err
	}
	return instance, nil
}

// singBoxMihomo gives a server's sockets what mihomo's own get: Android's protect (DefaultSocketHook), Windows'
// interface binding, and mihomo's resolver for the server's name instead of the tunnel's fake-ip.
type singBoxMihomo struct{ outbound.Adapter }

func (d *singBoxMihomo) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if d.Tag() == "mihomo-unconnected" {
		// WireGuard as mihomo's own (row ۲۳): unconnected, and an IPv6 address skips the resolver that refuses it.
		conn, err := dialer.ListenPacket(ctx, "udp", "", destination.AddrPort())
		if err != nil {
			return nil, err
		}
		return bufio.NewBindPacketConn(conn, destination.UDPAddr()), nil
	}
	return dialer.DialContext(ctx, network, destination.String())
}

// WireGuard and OpenVPN resolve the server with the proxy-server resolver first, so destination is an address here.
func (d *singBoxMihomo) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return dialer.ListenPacket(ctx, "udp", "", destination.AddrPort())
}

// singBoxResolver answers from mihomo's resolver of the moment: each config apply replaces it.
type singBoxResolver struct {
	sbdns.TransportAdapter
	resolver *resolver.Resolver
}

func (t *singBoxResolver) Start(adapter.StartStage, *adapter.Scope) error { return nil }

func (t *singBoxResolver) Reset() {}

func (t *singBoxResolver) Exchange(ctx context.Context, message *mDNS.Msg) (*mDNS.Msg, error) {
	use := *t.resolver
	if use == nil {
		return nil, errors.New("mihomo has no resolver")
	}
	return use.ExchangeContext(ctx, message)
}

func (t *singBoxResolver) ExchangeAsync(ctx context.Context, message *mDNS.Msg, callback func(*mDNS.Msg, error)) {
	callback(t.Exchange(ctx, message))
}
