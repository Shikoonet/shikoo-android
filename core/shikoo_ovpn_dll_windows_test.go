package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	_ "embed"
	"encoding/binary"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
	singtun "github.com/metacubex/sing-tun"
)

// These run the real ShikooNetOvpn3.dll (SHIKOO_OVPN_DLL) against a throwaway OpenVPN server in a --rm container on
// 127.0.0.1 (SHIKOO_OVPN_IMAGE, default ovpn3-srvu:local, openvpn 2.6). The adapter is a fake: no driver, route or DNS.

//go:embed testdata/ovpn-server.sh
var ovpnServerScript []byte

const serverGateway = "10.89.0.1"

func withRealEngine(t *testing.T) *wintunSeam {
	t.Helper()
	path := os.Getenv("SHIKOO_OVPN_DLL")
	if _, err := os.Stat(path); path == "" || err != nil {
		t.Skip("SHIKOO_OVPN_DLL is not set to a built ShikooNetOvpn3.dll")
	}
	seam := &wintunSeam{}
	was, build, load, found := ovpnDLLPath, wintunNew, ovpnLoad, ovpnFound
	ovpnDLLPath = func() string { return path }
	ovpnLoad = loadOvpn
	wintunNew = func(options singtun.Options) (singtun.WinTun, error) {
		tun := newFakeWintun()
		seam.mu.Lock()
		seam.built, seam.tuns = append(seam.built, options), append(seam.tuns, tun)
		seam.mu.Unlock()
		return tun, nil
	}
	t.Cleanup(func() {
		ovpnWinStop()
		ovpnDLLPath, wintunNew, ovpnLoad, ovpnFound = was, build, load, found
		ovpnEnded.Store(nil)
		ovpnNow.Store(nil)
		ovpnPrepared.Store(nil)
	})
	return seam
}

type ovpnServer struct {
	name    string
	port    int
	mapping map[string]any
}

func startOvpnServer(t *testing.T) *ovpnServer {
	t.Helper()
	image := os.Getenv("SHIKOO_OVPN_IMAGE")
	if image == "" {
		image = "ovpn3-srvu:local"
	}
	if _, err := exec.LookPath("docker"); err != nil {
		t.Skip("no docker")
	}
	if out, err := exec.Command("docker", "image", "inspect", image).CombinedOutput(); err != nil {
		t.Skipf("no image %s: %s", image, out)
	}
	free, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := free.Addr().(*net.TCPAddr).Port
	free.Close()

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "srv.sh"), ovpnServerScript, 0o755); err != nil {
		t.Fatal(err)
	}
	server := &ovpnServer{name: fmt.Sprintf("shikoo-ovpn-win-test-%d", os.Getpid()), port: port}
	cmd := exec.Command("docker", "run", "--rm", "--name", server.name, "--cap-add", "NET_ADMIN", "--device", "/dev/net/tun",
		"-e", fmt.Sprintf("PORT=%d", port), "-p", fmt.Sprintf("127.0.0.1:%d:%d/tcp", port, port), "-v", dir+":/out", image, "sh", "/out/srv.sh")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = exec.Command("docker", "stop", "-t", "1", server.name).Run()
		_ = cmd.Wait()
		if log, err := os.ReadFile(filepath.Join(dir, "server.log")); err == nil && (t.Failed() || os.Getenv("SHIKOO_OVPN_SERVER_LOG") != "") {
			t.Logf("server log:\n%s", log)
		}
	})
	waitFor(t, "the server", func() bool {
		log, _ := os.ReadFile(filepath.Join(dir, "server.log"))
		return bytes.Contains(log, []byte("Initialization Sequence Completed"))
	}, 60*time.Second)

	profile, err := os.ReadFile(filepath.Join(dir, "client.ovpn"))
	if err != nil {
		t.Fatal(err)
	}
	block := func(tag string) string {
		_, rest, _ := strings.Cut(string(profile), "<"+tag+">\n")
		body, _, _ := strings.Cut(rest, "\n</"+tag+">")
		return body
	}
	server.mapping = map[string]any{
		"name": "OV", "type": "openvpn", "server": "127.0.0.1", "port": port, "proto": "tcp", "cipher": "AES-256-CBC", "auth": "SHA1",
		"ca": block("ca"), "cert": block("cert"), "key": block("key"), "username": "shikoo", "password": "test-pass",
		shikooOwnerKey: "openvpn",
	}
	return server
}

func (s *ovpnServer) with(set map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range s.mapping {
		out[key] = value
	}
	for key, value := range set {
		out[key] = value
	}
	return out
}

func (s *ovpnServer) kill(t *testing.T, signal string) {
	t.Helper()
	if out, err := exec.Command("docker", "kill", "--signal="+signal, s.name).CombinedOutput(); err != nil {
		t.Fatalf("docker kill: %v: %s", err, out)
	}
}

func internetChecksum(b []byte) uint16 {
	var total uint32
	for i := 0; i+1 < len(b); i += 2 {
		total += uint32(b[i])<<8 | uint32(b[i+1])
	}
	for total>>16 != 0 {
		total = total&0xffff + total>>16
	}
	return ^uint16(total)
}

// echoTo is an ICMP echo request in an IPv4 packet: 20 + 8 + 16 bytes.
func echoTo(src netip.Addr, dst string) []byte {
	p := make([]byte, 44)
	p[0], p[3], p[8], p[9] = 0x45, 44, 64, 1
	copy(p[12:], src.AsSlice())
	copy(p[16:], netip.MustParseAddr(dst).AsSlice())
	p[20], p[25], p[27] = 8, 0x48, 1
	copy(p[28:], "shikoo-ovpn-win!")
	binary.BigEndian.PutUint16(p[22:], internetChecksum(p[20:]))
	binary.BigEndian.PutUint16(p[10:], internetChecksum(p[:20]))
	return p
}

// pingThroughTheEngine sends an echo into the adapter and waits for the gateway's reply out of the engine.
func pingThroughTheEngine(t *testing.T, tun *fakeWintun, local netip.Addr) {
	t.Helper()
	tun.outbound <- echoTo(local, serverGateway)
	timeout := time.After(10 * time.Second)
	for {
		select {
		case reply := <-tun.inbound:
			// The server's own router solicitations come first on some runs.
			if len(reply) >= 28 && reply[0]>>4 == 4 && reply[9] == 1 && reply[20] == 0 &&
				netip.AddrFrom4([4]byte(reply[12:16])) == netip.MustParseAddr(serverGateway) {
				return
			}
		case <-timeout:
			t.Fatal("no echo reply came back through the engine")
		}
	}
}

// connectedWithin waits for the session to be up and to stay up: a server that restarts may drop it once more.
func connectedWithin(t *testing.T, limit time.Duration) {
	t.Helper()
	var since time.Time
	waitFor(t, "the session up", func() bool {
		if shikooOwnerNow().State != stateUp {
			since = time.Time{}
			return false
		}
		if since.IsZero() {
			since = time.Now()
		}
		return time.Since(since) > 1500*time.Millisecond
	}, limit)
}

func TestTheRealEngineConnectsCarriesAPingAndHaltsCleanly(t *testing.T) {
	seam := withRealEngine(t)
	server := startOvpnServer(t)
	loopback := loopbackIndex(t)

	if err := ovpnWinStart("ShikooNet", server.mapping, false, physicalIs(loopback)); err != nil {
		t.Fatal(err)
	}
	connectedWithin(t, 30*time.Second)
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", Server: "OV", State: stateUp}) {
		t.Errorf("the core says %+v", got)
	}
	if seam.count() != 1 {
		t.Fatalf("%d adapters built", seam.count())
	}
	options := seam.built[0]
	if len(options.Inet4Address) != 1 || options.Inet4Address[0].String() != "10.89.0.2/24" ||
		len(options.DNSServers) != 1 || options.DNSServers[0].String() != "1.1.1.1" || options.MTU == 0 {
		t.Errorf("the adapter was asked for %+v", options)
	}

	up0, down0 := statistic.DefaultManager.Total()
	pingThroughTheEngine(t, seam.last(), options.Inet4Address[0].Addr())
	up, down := statistic.DefaultManager.Total()
	if up <= up0 || down <= down0 {
		t.Errorf("counters %d/%d did not move from %d/%d", up, down, up0, down0)
	}

	tun := seam.last()
	begin := time.Now()
	if !ovpnWinStop() {
		t.Fatal("the engine did not halt")
	}
	t.Logf("halted in %v", time.Since(begin).Round(time.Millisecond))
	if !tunClosed(tun) || ovpnLive.Load() != nil || ovpnEnded.Load() != nil || shikooOwnerNow() != (ShikooOwner{}) {
		t.Errorf("after a halt: adapter closed %v, live %v, outcome %+v, core says %+v",
			tunClosed(tun), ovpnLive.Load() != nil, ovpnEnded.Load(), shikooOwnerNow())
	}
}

func TestTheRealEngineTakesAWrongPasswordForARefusedLoginAndBuildsNoTunnel(t *testing.T) {
	seam := withRealEngine(t)
	server := startOvpnServer(t)

	if err := ovpnWinStart("ShikooNet", server.with(map[string]any{"password": "wrong"}), false, physicalIs(loopbackIndex(t))); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "the refusal", func() bool { return ovpnEnded.Load() != nil }, 30*time.Second)
	if got := ovpnEnded.Load(); got.state != stateRefused || !strings.Contains(got.reason, ovpnAuthFailed) {
		t.Errorf("outcome %+v", got)
	}
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", State: stateRefused}) {
		t.Errorf("the core says %+v", got)
	}
	if seam.count() != 0 || ovpnLive.Load() != nil {
		t.Errorf("%d adapters, live %v: a refused login leaves nothing behind", seam.count(), ovpnLive.Load() != nil)
	}
}

func TestTheRealEngineReconnectsAfterTheServerRestartsAndKeepsThePlansAdapter(t *testing.T) {
	seam := withRealEngine(t)
	server := startOvpnServer(t)
	if err := ovpnWinStart("ShikooNet", server.mapping, false, physicalIs(loopbackIndex(t))); err != nil {
		t.Fatal(err)
	}
	connectedWithin(t, 30*time.Second)
	tun := seam.last()

	server.kill(t, "USR1")
	waitFor(t, "the session to notice", func() bool { return shikooOwnerNow().State != stateUp }, 30*time.Second)
	if got := shikooOwnerNow(); got.Server != "OV" {
		t.Errorf("while reconnecting the core says %+v: the server stays carried", got)
	}
	connectedWithin(t, 60*time.Second)
	if seam.count() != 1 || seam.last() != tun || tunClosed(tun) {
		t.Fatalf("%d adapters after a reconnect: an unchanged plan must keep the adapter", seam.count())
	}
	pingThroughTheEngine(t, tun, seam.built[0].Inet4Address[0].Addr())
}

func TestTheRealEngineIsHaltedWhenNothingAnswersWithinTheLimit(t *testing.T) {
	seam := withRealEngine(t)
	silent, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer silent.Close()
	go func() {
		for {
			conn, err := silent.Accept()
			if err != nil {
				return
			}
			go io.Copy(io.Discard, conn)
		}
	}()
	limit := ovpnConnectLimit
	ovpnConnectLimit = 3 * time.Second
	t.Cleanup(func() { ovpnConnectLimit = limit })

	mapping := ovpnMapping(map[string]any{
		"server": "127.0.0.1", "port": silent.Addr().(*net.TCPAddr).Port, "proto": "tcp", "ca": someCA(t),
	})
	if err := ovpnWinStart("ShikooNet", mapping, false, physicalIs(loopbackIndex(t))); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "the limit", func() bool { return ovpnLive.Load() == nil }, 20*time.Second)
	if got := ovpnEnded.Load(); got == nil || got.state != stateFailed || got.reason != "no connection in 3s" {
		t.Errorf("outcome %+v", got)
	}
	if seam.count() != 0 {
		t.Error("a tunnel was built for a server that never answered")
	}
}

// someCA is a certificate OpenVPN 3 can parse, for a server that never gets as far as a handshake.
func someCA(t *testing.T) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "test-ca"}, IsCA: true,
		BasicConstraintsValid: true, NotBefore: time.Now(), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
}

func TestTheRealEngineEndsAProfileItCannotReadAtOnceWithTheReasonItGives(t *testing.T) {
	withRealEngine(t)
	if err := ovpnWinStart("ShikooNet", ovpnMapping(nil), false, physicalIs(1)); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "the refusal", func() bool { return ovpnLive.Load() == nil }, 20*time.Second)
	if got := ovpnEnded.Load(); got == nil || got.state != stateFailed || !strings.Contains(got.reason, "error parsing ca certificate") {
		t.Errorf("outcome %+v", got)
	}
}

// floodUntil keeps echo requests going into the adapter, as the system would, until stop is closed.
func floodUntil(tun *fakeWintun, local netip.Addr, stop <-chan struct{}) {
	for {
		select {
		case tun.outbound <- echoTo(local, serverGateway):
		case <-stop:
			return
		case <-tun.closed:
			return
		}
		select {
		case <-tun.inbound:
		default:
		}
	}
}

// SHIKOO_OVPN_STRESS=n repeats the halt and the server's restart n times with packets flowing: a native crash in the
// engine shows as the test binary dying with exit code 0xC0000005, not as a Go failure.
func TestTheRealEngineSurvivesHaltsAndServerRestartsWithPacketsFlowing(t *testing.T) {
	rounds := 0
	fmt.Sscan(os.Getenv("SHIKOO_OVPN_STRESS"), &rounds)
	if rounds == 0 {
		t.Skip("SHIKOO_OVPN_STRESS is not set")
	}
	seam := withRealEngine(t)
	server := startOvpnServer(t)
	loopback := loopbackIndex(t)
	for round := 0; round < rounds; round++ {
		if err := ovpnWinStart("ShikooNet", server.mapping, false, physicalIs(loopback)); err != nil {
			t.Fatal(err)
		}
		waitFor(t, "the session up", func() bool { return shikooOwnerNow().State == stateUp }, 30*time.Second)
		tun := seam.last()
		stop := make(chan struct{})
		go floodUntil(tun, seam.built[len(seam.built)-1].Inet4Address[0].Addr(), stop)
		switch round % 3 {
		case 0:
			server.kill(t, "USR1")
			waitFor(t, "the drop", func() bool { return shikooOwnerNow().State != stateUp }, 30*time.Second)
			waitFor(t, "the session up again", func() bool { return shikooOwnerNow().State == stateUp }, 60*time.Second)
		case 1:
			// Halted while the engine is between two connections.
			server.kill(t, "USR1")
			waitFor(t, "the drop", func() bool { return shikooOwnerNow().State != stateUp }, 30*time.Second)
		}
		if !ovpnWinStop() {
			t.Fatalf("round %d: did not halt", round)
		}
		close(stop)
	}
}
