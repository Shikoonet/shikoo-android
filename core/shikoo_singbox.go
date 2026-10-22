package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"net"
	"net/netip"
	"slices"
	"strconv"
	"strings"

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
	sblog "github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/block"
	"github.com/sagernet/sing-box/protocol/openvpn"
	"github.com/sagernet/sing-box/protocol/socks"
	"github.com/sagernet/sing-box/protocol/ssh"
	"github.com/sagernet/sing-box/protocol/vless"
	"github.com/sagernet/sing-box/protocol/wireguard"
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

// The uTLS fingerprints that mihomo and sing-box name alike.
const singBoxFingerprints = "none chrome firefox safari ios android edge 360 qq random randomized"

func singBoxServes(proxy map[string]any) bool {
	kind := strings.ToLower(fmt.Sprint(proxy["type"]))
	keys, ok := singBoxKeys[kind]
	if !ok {
		return false
	}
	for key := range proxy {
		if !slices.Contains(strings.Fields(keys+" name type server port udp"), key) {
			return false
		}
	}
	if proxy["remote-dns-resolve"] == true {
		return false
	}
	switch kind {
	case "vless":
		return singBoxOneOf(proxy["encryption"], "none") && singBoxOneOf(proxy["network"], "tcp ws grpc") &&
			singBoxOneOf(proxy["flow"], "xtls-rprx-vision") &&
			singBoxOneOf(proxy["client-fingerprint"], singBoxFingerprints)
	case "openvpn":
		return singBoxOneOf(proxy["dev"], "tun")
	}
	return true
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
func singBoxConvert(proxy map[string]any) (out map[string]any, isEndpoint, udp bool, err error) {
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
			fingerprint := o.ClientFingerprint
			if o.RealityOpts.PublicKey != "" {
				tls["reality"] = map[string]any{"enabled": true, "public_key": o.RealityOpts.PublicKey,
					"short_id": o.RealityOpts.ShortID}
				if fingerprint == "" || fingerprint == "none" {
					fingerprint = "chrome" // sing-box's REALITY refuses to start without uTLS
				}
			}
			if fingerprint != "" && fingerprint != "none" {
				tls["utls"] = map[string]any{"enabled": true, "fingerprint": fingerprint}
			}
			out["tls"] = tls
		}
		switch ws := o.WSOpts; o.Network {
		case "ws":
			out["transport"] = map[string]any{"type": "ws", "path": ws.Path, "headers": ws.Headers,
				"max_early_data": ws.MaxEarlyData, "early_data_header_name": ws.EarlyDataHeaderName}
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
		peers := o.Peers
		if len(peers) == 0 {
			peers = []mihomo.WireGuardPeerOption{o.WireGuardPeerOption}
		}
		var sbPeers []any
		for _, peer := range peers {
			allowed := peer.AllowedIPs
			if len(allowed) == 0 {
				allowed = []string{"0.0.0.0/0", "::/0"}
			}
			sbPeers = append(sbPeers, map[string]any{"address": peer.Server, "port": peer.Port,
				"public_key": peer.PublicKey, "pre_shared_key": peer.PreSharedKey,
				"allowed_ips": singBoxPrefixes(allowed...), "reserved": peer.Reserved,
				"persistent_keepalive_interval": o.PersistentKeepalive})
		}
		address := singBoxPrefixes(o.Ip, o.Ipv6)
		out = map[string]any{"type": "wireguard", "address": address, "private_key": o.PrivateKey, "peers": sbPeers,
			"mtu": o.MTU, "domain_resolver": "proxy-server"}
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
		fallback := o.DataCipherFallback
		if fallback == "" {
			fallback = o.Cipher
		}
		out = map[string]any{"type": "openvpn-client", "server": o.Server, "server_port": o.Port, "network": network,
			"tls": tls, "username": o.Username, "password": o.Password, "data_ciphers": o.DataCiphers,
			"data_ciphers_fallback": fallback, "auth": o.Auth, "compression_lzo": o.CompLZO, "mtu": o.MTU,
			"ping_interval": strconv.Itoa(o.Ping) + "s", "ping_restart": strconv.Itoa(o.PingRestart) + "s",
			"domain_resolver": "proxy-server"}
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

func singBoxPrefixes(ips ...string) (prefixes []string) {
	for _, ip := range ips {
		if addr, err := netip.ParseAddr(ip); err == nil {
			ip = netip.PrefixFrom(addr, addr.BitLen()).String()
		}
		if ip != "" {
			prefixes = append(prefixes, ip)
		}
	}
	return prefixes
}

type singBoxServer struct {
	index           int
	out             map[string]any
	isEndpoint, udp bool
}

// startSingBox runs one sing-box for the servers it can carry, each a SOCKS user on one loopback port.
func startSingBox(proxies []map[string]any) ([]map[string]any, func(), error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, nil, err
	}
	// shortcut: the port is free when picked; a program that takes it before sing-box binds fails this start, and
	// mihomo carries these servers until the next config apply.
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	password := rand.Text()
	var servers []singBoxServer
	for i, proxy := range proxies {
		if !singBoxServes(proxy) {
			continue
		}
		// A bad OpenVPN key panics in sing-openvpn's own goroutine and ends the app: mihomo's parser refuses it first.
		parsed, err := madapter.ParseProxy(maps.Clone(proxy))
		if err == nil {
			parsed.Close()
		}
		out, isEndpoint, udp, convertErr := singBoxConvert(proxy)
		if err = errors.Join(err, convertErr); err != nil {
			log.Warnln("[SHIKOO] sing-box cannot carry %v; mihomo does: %v", proxy["name"], err)
			continue
		}
		out["tag"], out["detour"] = "s"+strconv.Itoa(i), "mihomo"
		servers = append(servers, singBoxServer{i, out, isEndpoint, udp})
	}
	if len(servers) == 0 {
		return proxies, func() {}, nil
	}
	instance, err := singBoxNew(singBoxConfig(port, password, servers), true)
	if err != nil {
		// One server sing-box refuses would take every other to mihomo: each refused one stays there alone.
		kept := slices.DeleteFunc(slices.Clone(servers), func(server singBoxServer) bool {
			check, err := singBoxNew(singBoxConfig(port, password, []singBoxServer{server}), false)
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
	outbounds := []any{map[string]any{"type": "mihomo", "tag": "mihomo"}, map[string]any{"type": "block", "tag": "block"}}
	var endpoints, users, rules []any
	for _, server := range servers {
		if server.isEndpoint {
			endpoints = append(endpoints, server.out)
		} else {
			outbounds = append(outbounds, server.out)
		}
		users = append(users, map[string]any{"username": server.out["tag"], "password": password})
		rules = append(rules, map[string]any{"auth_user": server.out["tag"], "outbound": server.out["tag"]})
	}
	return map[string]any{
		"log": map[string]any{"level": "warn"},
		"dns": map[string]any{"final": "resolver", "servers": []any{
			map[string]any{"type": "mihomo", "tag": "resolver"},
			map[string]any{"type": "mihomo-proxy-server", "tag": "proxy-server"},
		}},
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
