package main

import (
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	C "github.com/metacubex/mihomo/constant"
	mDNS "github.com/miekg/dns"
	"golang.org/x/crypto/ssh"
)

func TestSingBoxServesWhatDartSays(t *testing.T) {
	content, err := os.ReadFile("testdata/sing_box_serves.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []struct {
		Serves bool           `json:"serves"`
		Proxy  map[string]any `json:"proxy"`
	}
	if err := json.Unmarshal(content, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		if got := singBoxServes(c.Proxy); got != c.Serves {
			t.Errorf("%v: serves %v, want %v", c.Proxy["name"], got, c.Serves)
		}
	}
}

// x25519 gives a key pair the way WireGuard (std) or REALITY (raw URL) writes it.
func x25519(t *testing.T, encoding *base64.Encoding) (private, public string) {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return encoding.EncodeToString(key.Bytes()), encoding.EncodeToString(key.PublicKey().Bytes())
}

func TestSingBoxCarriesEveryTypeItServesAndStopsWithItsGeneration(t *testing.T) {
	_, realityPublic := x25519(t, base64.RawURLEncoding)
	wgPrivate, wgPublic := x25519(t, base64.StdEncoding)
	ca := e2ePKI(t, t.TempDir())
	_, clientKey := e2eSSHKey(t)
	proxies := fmt.Sprintf(`
proxies:
  - {name: reality, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, flow: xtls-rprx-vision, servername: a.test, reality-opts: {public-key: %s, short-id: 0123abcd}, shikoo-core: singBox}
  - {name: ws, type: vless, server: a.test, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: ws, ws-opts: {path: /p, headers: {Host: a.test}}, shikoo-core: singBox}
  - {name: grpc, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: grpc, grpc-opts: {grpc-service-name: g}, client-fingerprint: firefox, shikoo-core: singBox}
  - {name: xhttp, type: vless, server: 127.0.0.1, port: 1, uuid: 4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11, tls: true, network: xhttp, shikoo-core: singBox}
  - {name: wg, type: wireguard, server: 127.0.0.1, port: 1, ip: 10.0.0.2, private-key: %q, public-key: %q, udp: true, shikoo-core: singBox}
  - {name: ovpn, type: openvpn, server: 127.0.0.1, port: 1, ca: %q, username: u, password: p, shikoo-core: singBox}
  - {name: ssh, type: ssh, server: 127.0.0.1, port: 1, username: u, private-key: %q, shikoo-core: singBox}
`, realityPublic, wgPrivate, wgPublic, ca, clientKey)
	t.Cleanup(func() { shikooCoresRunning, shikooCoresStarting = nil, nil })

	cfg := parseShikooCores(t, proxies)
	shikooCoresCommit()

	got := proxyTypes(cfg, "reality", "ws", "grpc", "xhttp", "wg", "ovpn", "ssh")
	want := []C.AdapterType{C.Socks5, C.Socks5, C.Socks5, C.Vless, C.Socks5, C.Socks5, C.Socks5}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("types %v, want %v: XHTTP stays on mihomo, every other server goes to sing-box", got, want)
		}
	}
	if !cfg.Proxies["wg"].SupportUDP() || !cfg.Proxies["ovpn"].SupportUDP() || cfg.Proxies["ssh"].SupportUDP() {
		t.Error("UDP must follow what mihomo's own adapter carries")
	}
	first := cfg.Proxies["reality"].Addr()
	if conn, err := net.Dial("tcp", first); err != nil {
		t.Fatalf("sing-box is not listening at %s: %v", first, err)
	} else {
		conn.Close()
	}

	if again := parseShikooCores(t, proxies); again.Proxies["reality"].Type() != C.Socks5 {
		t.Fatal("the next generation did not start while the previous one still runs")
	}
	shikooCoresCommit()
	if conn, err := net.DialTimeout("tcp", first, time.Second); err == nil {
		conn.Close()
		t.Fatal("the previous sing-box still listens after the next generation was committed")
	}
	for _, stop := range shikooCoresRunning {
		stop()
	}
}

// The end-to-end test runs official servers from SHIKOO_E2E_BIN, unpacked, never installed:
// mihomo (v1.19.32 release), sing-box (1.14.3 release), and usr/sbin/openvpn and usr/sbin/sshd from Ubuntu's
// openvpn and openssh-server packages (apt-get download, dpkg -x) with their libraries under usr/lib.
// OpenVPN needs root for its tun; sshd runs as nobody, so it takes keys only.
func TestSingBoxEndToEnd(t *testing.T) {
	bin := os.Getenv("SHIKOO_E2E_BIN")
	if bin == "" {
		t.Skip("SHIKOO_E2E_BIN names the folder of the official servers")
	}
	var hookMu sync.Mutex
	var hooked []string
	previous := dialer.DefaultSocketHook
	dialer.DefaultSocketHook = func(network, address string, _ syscall.RawConn) error {
		hookMu.Lock()
		defer hookMu.Unlock()
		hooked = append(hooked, network+" "+address)
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = previous })
	freshHook := func() {
		hookMu.Lock()
		defer hookMu.Unlock()
		hooked = nil
	}
	sawHook := func(t *testing.T, want string) {
		t.Helper()
		hookMu.Lock()
		defer hookMu.Unlock()
		for _, h := range hooked {
			if strings.Contains(h, want) {
				return
			}
		}
		t.Errorf("no socket to %q went through mihomo's socket hook: %v", want, hooked)
	}
	host := e2eHostIP(t)
	echo := e2eEcho(t)
	uuid := "4b2a7d3e-1f4c-4c4e-9f53-2b8f0c1d9e11"

	t.Run("VLESS REALITY against mihomo v1.19.32", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		dest := e2eTLS(t)
		private, public := x25519(t, base64.RawURLEncoding)
		port := e2ePort(t)
		e2eFile(t, dir, "config.yaml", fmt.Sprintf(`mode: direct
log-level: debug
listeners:
  - {name: reality-in, type: vless, listen: 127.0.0.1, port: %d, users: [{username: u, uuid: %s, flow: xtls-rprx-vision}],
     reality-config: {dest: %q, private-key: %s, short-id: ["0123abcd"], server-names: [reality.test]}}
`, port, uuid, dest, private))
		e2eRun(t, dir, filepath.Join(bin, "mihomo"), "-d", dir)
		e2eWait(t, port)
		proxy := e2eThrough(t, fmt.Sprintf(`{name: r, type: vless, server: 127.0.0.1, port: %d, uuid: %s, tls: true, udp: true,
  flow: xtls-rprx-vision, servername: reality.test, client-fingerprint: chrome,
  reality-opts: {public-key: %s, short-id: 0123abcd}}`, port, uuid, public), "127.0.0.1", echo)
		sawHook(t, fmt.Sprintf("127.0.0.1:%d", port))

		page := e2eHTTP(t)
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if delay, err := proxy.URLTest(ctx, page, nil); err != nil || delay == 0 {
			t.Errorf("ping through sing-box: %d ms, %v", delay, err)
		}
		e2eLog(t, dir, "REALITY")
	})

	t.Run("a dead server fails its ping, so the app sees failed", func(t *testing.T) {
		_, public := x25519(t, base64.RawURLEncoding)
		cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: dead, type: vless, server: 127.0.0.1, port: %d, uuid: %s, tls: true, servername: reality.test,
     reality-opts: {public-key: %s, short-id: 0123abcd}, shikoo-core: singBox}
`, e2ePort(t), uuid, public))
		t.Cleanup(e2eStop)
		if cfg.Proxies["dead"].Type() != C.Socks5 {
			t.Fatal("sing-box did not take the server")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if delay, err := cfg.Proxies["dead"].URLTest(ctx, e2eHTTP(t), nil); err == nil {
			t.Fatalf("a ping through sing-box to a closed port answered in %d ms", delay)
		} else {
			t.Logf("ping error: %v", err)
		}
	})

	t.Run("WireGuard against sing-box 1.14.3, server by name, TCP and UDP", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		serverPrivate, serverPublic := x25519(t, base64.StdEncoding)
		clientPrivate, clientPublic := x25519(t, base64.StdEncoding)
		port := e2ePort(t)
		e2eFile(t, dir, "config.json", fmt.Sprintf(`{"log": {"level": "warn"},
  "endpoints": [{"type": "wireguard", "tag": "wg", "listen_port": %d, "address": ["10.66.0.1/24"], "private_key": %q,
    "peers": [{"public_key": %q, "allowed_ips": ["10.66.0.2/32"]}]}],
  "outbounds": [{"type": "direct", "tag": "direct"}], "route": {"final": "direct"}}`, port, serverPrivate, clientPublic))
		e2eRun(t, dir, filepath.Join(bin, "sing-box"), "run", "-c", filepath.Join(dir, "config.json"))
		time.Sleep(time.Second)
		names := e2eNames(t, &resolver.ProxyServerHostResolver, map[string]string{"wg.shikoo.test.": "127.0.0.1"})
		e2eNames(t, &resolver.DefaultResolver, nil)

		proxy := e2eThrough(t, fmt.Sprintf(`{name: w, type: wireguard, server: wg.shikoo.test, port: %d, ip: 10.66.0.2,
  private-key: %q, public-key: %q, udp: true, mtu: 1280}`, port, clientPrivate, serverPublic), host, echo)
		if len(*names) == 0 {
			t.Error("sing-box resolved the server's name without mihomo's proxy-server resolver")
		}
		sawHook(t, "udp")

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		target := e2eTarget(host, echo)
		target.NetWork = C.UDP
		packets, err := proxy.ListenPacketContext(ctx, target)
		if err != nil {
			t.Fatalf("UDP through sing-box: %v", err)
		}
		defer packets.Close()
		to := net.UDPAddrFromAddrPort(netip.AddrPortFrom(netip.MustParseAddr(host), echo))
		if _, err := packets.WriteTo([]byte("shikoo"), to); err != nil {
			t.Fatal(err)
		}
		packets.SetReadDeadline(time.Now().Add(5 * time.Second))
		buf := make([]byte, 64)
		if n, _, err := packets.ReadFrom(buf); err != nil || string(buf[:n]) != "shikoo" {
			t.Fatalf("UDP echo %q, %v", buf[:n], err)
		}
	})

	t.Run("OpenVPN against OpenVPN 2.6, tls-auth and a password", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		ca := e2ePKI(t, dir)
		e2eFile(t, dir, "check.sh", "#!/bin/sh\n[ \"$(sed -n 1p \"$1\")\" = shikoo ] && [ \"$(sed -n 2p \"$1\")\" = test-pass ]\n")
		os.Chmod(filepath.Join(dir, "check.sh"), 0o755)
		openvpn := filepath.Join(bin, "usr/sbin/openvpn")
		if out, err := e2eCommand(bin, openvpn, "--genkey", "secret", filepath.Join(dir, "ta.key")).CombinedOutput(); err != nil {
			t.Fatalf("genkey: %v %s", err, out)
		}
		port := e2ePort(t)
		e2eFile(t, dir, "server.conf", fmt.Sprintf(`dev sbxtun
dev-type tun
proto udp4
local 127.0.0.1
port %d
server 10.89.0.0 255.255.255.0
topology subnet
ca %[2]s/ca.crt
cert %[2]s/server.crt
key %[2]s/server.key
dh none
tls-auth %[2]s/ta.key 0
auth SHA256
verify-client-cert none
username-as-common-name
script-security 2
auth-user-pass-verify %[2]s/check.sh via-file
tmp-dir %[2]s
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
verb 3
`, port, dir))
		e2eRun(t, dir, openvpn, "--config", filepath.Join(dir, "server.conf"))
		time.Sleep(2 * time.Second)
		taKey, _ := os.ReadFile(filepath.Join(dir, "ta.key"))
		e2eThrough(t, fmt.Sprintf(`{name: o, type: openvpn, server: 127.0.0.1, port: %d, proto: udp, ca: %q, username: shikoo,
  password: test-pass, tls-auth: %q, key-direction: "1", auth: SHA256}`, port, ca, taKey), host, echo)
		sawHook(t, "udp")
		e2eLog(t, dir, "Peer Connection Initiated")
	})

	t.Run("SSH against OpenSSH sshd, a password and a key", func(t *testing.T) {
		freshHook()
		dir := t.TempDir()
		hostPublic, hostKey := e2eSSHKey(t)
		clientPublic, clientKey := e2eSSHKey(t)
		hash, err := exec.Command("openssl", "passwd", "-6", "test-pass").Output()
		if err != nil {
			t.Fatal(err)
		}
		port := e2ePort(t)
		e2eFile(t, dir, "host_key", hostKey)
		e2eFile(t, dir, "authorized_keys", clientPublic)
		for _, path := range []string{filepath.Dir(dir), dir, filepath.Join(dir, "authorized_keys")} {
			os.Chmod(path, 0o755) // sshd reads the keys as the user
		}
		// sshd wants its privsep user "sshd" and an unlocked account; both exist only in its own mount namespace.
		e2eFile(t, dir, "passwd", "root:x:0:0::/root:/bin/sh\nsshd:x:65534:65534::/run/sshd:/usr/sbin/nologin\n"+
			"shikoo:x:65534:65534::/tmp:/bin/sh\n")
		e2eFile(t, dir, "shadow", "shikoo:"+strings.TrimSpace(string(hash))+":20000:0:99999:7:::\n")
		e2eFile(t, dir, "sshd_config", fmt.Sprintf(`Port %d
ListenAddress 127.0.0.1
HostKey %[2]s/host_key
PidFile %[2]s/sshd.pid
AuthorizedKeysFile %[2]s/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication yes
AllowTcpForwarding yes
`, port, dir))
		e2eRun(t, dir, "unshare", "--mount", "--propagation", "private", "sh", "-c", fmt.Sprintf(
			"mount --bind %[1]s/passwd /etc/passwd && mount --bind %[1]s/shadow /etc/shadow && "+
				"mount -t tmpfs tmpfs /run && mkdir /run/sshd && exec %[2]s -D -e -f %[1]s/sshd_config",
			dir, filepath.Join(bin, "usr/sbin/sshd")))
		e2eWait(t, port)
		e2eThrough(t, fmt.Sprintf(`{name: s, type: ssh, server: 127.0.0.1, port: %d, username: shikoo, password: test-pass,
  host-key: [%q]}`, port, strings.TrimSpace(hostPublic)), "127.0.0.1", echo)
		sawHook(t, fmt.Sprintf("127.0.0.1:%d", port))
		e2eThrough(t, fmt.Sprintf(`{name: s, type: ssh, server: 127.0.0.1, port: %d, username: shikoo, private-key: %q}`,
			port, clientKey), "127.0.0.1", echo)
		e2eLog(t, dir, "Accepted")
	})
}

func e2eStop() {
	for _, stop := range shikooCoresStarting {
		stop()
	}
	shikooCoresStarting = nil
}

// e2eThrough marks the mapping for sing-box, checks mihomo now holds a SOCKS5 in its place, and echoes once through it.
func e2eThrough(t *testing.T, mapping, ip string, port uint16) C.Proxy {
	t.Helper()
	cfg := parseShikooCores(t, "proxies:\n  - "+strings.ReplaceAll(strings.TrimSuffix(mapping, "}"), "\n", " ")+
		", shikoo-core: singBox}\n")
	t.Cleanup(e2eStop)
	var proxy C.Proxy
	for _, p := range cfg.Proxies {
		if p.Type() == C.Socks5 {
			proxy = p
		}
	}
	if proxy == nil {
		t.Fatal("sing-box did not take the server")
	}
	// OpenVPN refuses connections until its handshake is done, and WireGuard's first packet starts one.
	var err error
	for deadline := time.Now().Add(15 * time.Second); time.Now().Before(deadline); time.Sleep(300 * time.Millisecond) {
		if err = e2eEchoOnce(proxy, ip, port); err == nil {
			return proxy
		}
	}
	t.Fatalf("echo through sing-box: %v", err)
	return proxy
}

func e2eEchoOnce(proxy C.Proxy, ip string, port uint16) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := proxy.DialContext(ctx, e2eTarget(ip, port))
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("shikoo")); err != nil {
		return err
	}
	buf := make([]byte, 6)
	if _, err := conn.Read(buf); err != nil || string(buf) != "shikoo" {
		return fmt.Errorf("echo %q, %v", buf, err)
	}
	return nil
}

func e2eTarget(ip string, port uint16) *C.Metadata {
	return &C.Metadata{NetWork: C.TCP, DstIP: netip.MustParseAddr(ip), DstPort: port}
}

func e2eEcho(t *testing.T) uint16 {
	t.Helper()
	tcp, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		t.Fatal(err)
	}
	port := uint16(tcp.Addr().(*net.TCPAddr).Port)
	udp, err := net.ListenPacket("udp", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { tcp.Close(); udp.Close() })
	go func() {
		for {
			conn, err := tcp.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				buf := make([]byte, 64)
				n, _ := conn.Read(buf)
				conn.Write(buf[:n])
			}()
		}
	}()
	go func() {
		buf := make([]byte, 64)
		for {
			n, from, err := udp.ReadFrom(buf)
			if err != nil {
				return
			}
			udp.WriteTo(buf[:n], from)
		}
	}()
	return port
}

func e2eHTTP(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})}
	go server.Serve(listener)
	t.Cleanup(func() { server.Close() })
	return "http://" + listener.Addr().String() + "/"
}

// e2eTLS is REALITY's dest: a TLS 1.3 server the REALITY server borrows its handshake from.
func e2eTLS(t *testing.T) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), DNSNames: []string{"reality.test"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{MinVersion: tls.VersionTLS13,
		Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go http.Serve(listener, http.NotFoundHandler())
	return listener.Addr().String()
}

// e2ePKI writes a CA and a server certificate for OpenVPN into dir, and returns the CA in PEM.
func e2ePKI(t *testing.T, dir string) string {
	t.Helper()
	write := func(name string, block *pem.Block) string {
		data := pem.EncodeToMemory(block)
		e2eFile(t, dir, name, string(data))
		return string(data)
	}
	issue := func(template, parent *x509.Certificate, signer *ecdsa.PrivateKey) (*x509.Certificate, *ecdsa.PrivateKey, []byte) {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		if signer == nil {
			signer = key
		}
		der, err := x509.CreateCertificate(rand.Reader, template, parent, &key.PublicKey, signer)
		if err != nil {
			t.Fatal(err)
		}
		cert, _ := x509.ParseCertificate(der)
		return cert, key, der
	}
	caTemplate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "shikoo-test-ca"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour), IsCA: true,
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	caCert, caKey, caDER := issue(caTemplate, caTemplate, nil)
	ca := write("ca.crt", &pem.Block{Type: "CERTIFICATE", Bytes: caDER})
	_, serverKey, serverDER := issue(&x509.Certificate{SerialNumber: big.NewInt(2),
		Subject: pkix.Name{CommonName: "shikoo-test-server"}, NotBefore: time.Now().Add(-time.Hour),
		NotAfter: time.Now().Add(24 * time.Hour), KeyUsage: x509.KeyUsageDigitalSignature,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}, caCert, caKey)
	write("server.crt", &pem.Block{Type: "CERTIFICATE", Bytes: serverDER})
	der, _ := x509.MarshalECPrivateKey(serverKey)
	write("server.key", &pem.Block{Type: "EC PRIVATE KEY", Bytes: der})
	return ca
}

func e2eSSHKey(t *testing.T) (authorized, private string) {
	t.Helper()
	public, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(key, "")
	if err != nil {
		t.Fatal(err)
	}
	sshPublic, _ := ssh.NewPublicKey(public)
	return string(ssh.MarshalAuthorizedKey(sshPublic)), string(pem.EncodeToMemory(block))
}

// e2eNames points one of mihomo's resolvers at fixed answers and records each name asked.
func e2eNames(t *testing.T, at *resolver.Resolver, answers map[string]string) *[]string {
	t.Helper()
	previous := *at
	fake := &fakeResolver{answers: answers}
	*at = fake
	t.Cleanup(func() { *at = previous })
	return &fake.asked
}

type fakeResolver struct {
	answers map[string]string
	asked   []string
}

func (f *fakeResolver) ExchangeContext(_ context.Context, m *mDNS.Msg) (*mDNS.Msg, error) {
	f.asked = append(f.asked, m.Question[0].Name)
	reply := new(mDNS.Msg)
	reply.SetReply(m)
	if ip, ok := f.answers[m.Question[0].Name]; ok && m.Question[0].Qtype == mDNS.TypeA {
		rr, _ := mDNS.NewRR(m.Question[0].Name + " 60 IN A " + ip)
		reply.Answer = append(reply.Answer, rr)
	}
	return reply, nil
}

func (f *fakeResolver) LookupIP(context.Context, string) ([]netip.Addr, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) LookupIPv4(context.Context, string) ([]netip.Addr, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) LookupIPv6(context.Context, string) ([]netip.Addr, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) ResolveECH(context.Context, string) ([]byte, error) {
	return nil, errors.New("fake")
}
func (f *fakeResolver) Invalid() bool    { return false }
func (f *fakeResolver) ClearCache()      {}
func (f *fakeResolver) ResetConnection() {}

func e2eHostIP(t *testing.T) string {
	t.Helper()
	addresses, _ := net.InterfaceAddrs()
	for _, address := range addresses {
		if prefix, err := netip.ParsePrefix(address.String()); err == nil && prefix.Addr().Is4() &&
			!prefix.Addr().IsLoopback() && !strings.HasPrefix(prefix.Addr().String(), "10.") {
			return prefix.Addr().String()
		}
	}
	t.Skip("no outside address to reach through a tunnel")
	return ""
}

func e2ePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func e2eWait(t *testing.T, port int) {
	t.Helper()
	for i := 0; i < 50; i++ {
		if conn, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port)); err == nil {
			conn.Close()
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("nothing listens on %d", port)
}

func e2eFile(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func e2eCommand(bin, name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.Env = append(os.Environ(), "LD_LIBRARY_PATH="+filepath.Join(bin, "usr/lib/x86_64-linux-gnu")+":"+
		filepath.Join(bin, "lib/x86_64-linux-gnu"))
	return cmd
}

// e2eRun starts a server whose output goes to dir/server.log, which e2eLog prints.
func e2eRun(t *testing.T, dir, name string, args ...string) {
	t.Helper()
	logFile, err := os.Create(filepath.Join(dir, "server.log"))
	if err != nil {
		t.Fatal(err)
	}
	cmd := e2eCommand(os.Getenv("SHIKOO_E2E_BIN"), name, args...)
	cmd.Stdout, cmd.Stderr = logFile, logFile
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill()
		cmd.Wait()
		logFile.Close()
	})
}

// e2eLog prints the server's lines that hold want, as evidence that it saw the client.
func e2eLog(t *testing.T, dir, want string) {
	t.Helper()
	content, _ := os.ReadFile(filepath.Join(dir, "server.log"))
	for _, line := range strings.Split(string(content), "\n") {
		if strings.Contains(line, want) {
			t.Log(line)
		}
	}
}
