package main

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"os"
	"regexp"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// dnsServer answers every A question with ip on a loopback UDP port, counting them in asked when it is not nil.
func dnsServer(t *testing.T, ip string, asked *atomic.Int32) string {
	t.Helper()
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &dns.Server{PacketConn: conn, Handler: dns.HandlerFunc(func(w dns.ResponseWriter, r *dns.Msg) {
		reply := new(dns.Msg)
		reply.SetReply(r)
		if question := r.Question[0]; question.Qtype == dns.TypeA {
			if asked != nil {
				asked.Add(1)
			}
			header := dns.RR_Header{Name: question.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60}
			reply.Answer = []dns.RR{&dns.A{Hdr: header, A: net.ParseIP(ip)}}
		}
		_ = w.WriteMsg(reply)
	})}
	go func() { _ = server.ActivateAndServe() }()
	t.Cleanup(func() { _ = server.Shutdown() })
	return conn.LocalAddr().String()
}

func answeringDNS(t *testing.T, ip string) string { return dnsServer(t, ip, nil) }

// closedUDP is a loopback port nothing listens on: a dial there is refused at once.
func closedUDP(t *testing.T) string {
	t.Helper()
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := conn.LocalAddr().String()
	_ = conn.Close()
	return addr
}

// silentUDP takes every query and never answers.
func silentUDP(t *testing.T) string {
	t.Helper()
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn.LocalAddr().String()
}

func systemDNSIs(t *testing.T, servers ...string) {
	t.Helper()
	systemDNS.Store(nil)
	t.Cleanup(func() { systemDNS.Store(nil) })
	if len(servers) > 0 {
		rememberSystemDNS(servers)
	}
}

// deviceDNSIs makes the device's own resolver ask the server at addr, and forgets the last start's address.
func deviceDNSIs(t *testing.T, addr string) {
	t.Helper()
	lastEndpoint.Store(nil)
	previous := deviceResolver
	resolver := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, addr)
	}}
	deviceResolver = func() *net.Resolver { return resolver }
	t.Cleanup(func() { deviceResolver = previous; lastEndpoint.Store(nil) })
}

func wantAddress(t *testing.T, host string, held bool, want string) {
	t.Helper()
	if ip, err := resolveEndpoint(host, held); err != nil || ip != netip.MustParseAddr(want) {
		t.Fatalf("resolveEndpoint(%s, held=%v) = %v, %v; want %s", host, held, ip, err, want)
	}
}

func TestAHeldVPNsRebuildAsksTheNetworksDNSFromProtectedSockets(t *testing.T) {
	asked := protectRecorder(t, true)
	var network, device atomic.Int32
	systemDNSIs(t, dnsServer(t, "203.0.113.7", &network))
	deviceDNSIs(t, dnsServer(t, "198.51.100.7", &device))

	wantAddress(t, "wg.shikoo.test", true, "203.0.113.7")
	if len(*asked) == 0 || device.Load() != 0 {
		t.Fatalf("protected sockets: %d, the device resolver asked %d times; want a protected query and none by the device", len(*asked), device.Load())
	}
}

func TestAFreshStartAsksTheDevicesResolverFirstAsItAlwaysHas(t *testing.T) {
	asked := protectRecorder(t, true)
	var network atomic.Int32
	systemDNSIs(t, dnsServer(t, "203.0.113.7", &network))
	deviceDNSIs(t, answeringDNS(t, "198.51.100.7"))

	wantAddress(t, "wg.shikoo.test", false, "198.51.100.7")
	if network.Load() != 0 || len(*asked) != 0 {
		t.Fatalf("the networks' DNS was asked %d times with %d protected sockets before the device's answer", network.Load(), len(*asked))
	}
}

func TestAFreshStartWhoseDeviceResolverFailsAsksTheNetworksDNS(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "203.0.113.8"))
	deviceDNSIs(t, closedUDP(t))

	wantAddress(t, "wg.shikoo.test", false, "203.0.113.8")
}

func TestARebuildReusesTheAddressOfTheStartBeforeForItsHostOnly(t *testing.T) {
	protectRecorder(t, true)
	var network, device atomic.Int32
	systemDNSIs(t, dnsServer(t, "203.0.113.7", &network))
	deviceDNSIs(t, dnsServer(t, "198.51.100.7", &device))

	wantAddress(t, "wg.shikoo.test", false, "198.51.100.7")
	asked := device.Load()
	wantAddress(t, "wg.shikoo.test", true, "198.51.100.7")
	if network.Load() != 0 || device.Load() != asked {
		t.Fatalf("a rebuild for the same host asked DNS: networks %d, device %d more", network.Load(), device.Load()-asked)
	}
	wantAddress(t, "other.shikoo.test", true, "203.0.113.7")
}

func TestAFreshStartResolvesAgainWhatTheLastStartKept(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t)
	deviceDNSIs(t, answeringDNS(t, "198.51.100.7"))
	wantAddress(t, "wg.shikoo.test", false, "198.51.100.7")
	kept := lastEndpoint.Load()

	deviceDNSIs(t, answeringDNS(t, "198.51.100.9"))
	lastEndpoint.Store(kept)
	wantAddress(t, "wg.shikoo.test", false, "198.51.100.9")
}

func TestAnAnswerNoVPNServerCanHaveIsNoAnswerForTheNextServer(t *testing.T) {
	protectRecorder(t, true)
	deviceDNSIs(t, closedUDP(t))
	for _, poisoned := range []string{"10.10.34.5", "192.168.1.1", "172.16.0.9", "127.0.0.1", "169.254.1.1", "0.0.0.0"} {
		systemDNSIs(t, answeringDNS(t, poisoned), answeringDNS(t, "203.0.113.9"))
		lastEndpoint.Store(nil)
		wantAddress(t, "wg.shikoo.test", true, "203.0.113.9")
	}
}

func TestNetworkAnswersAllPoisonedLeaveTheDevicesResolverTheLastWord(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "10.10.34.5"))
	deviceDNSIs(t, answeringDNS(t, "198.51.100.7"))

	wantAddress(t, "wg.shikoo.test", true, "198.51.100.7")
	if _, err := lookupOutsideVPN("wg.shikoo.test"); err == nil {
		t.Fatal("a poisoned answer was taken for a server's address")
	}
}

func TestADeadSystemDNSServerPassesTheNameOnToTheNext(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t), answeringDNS(t, "203.0.113.8"))
	deviceDNSIs(t, closedUDP(t))

	wantAddress(t, "wg.shikoo.test", true, "203.0.113.8")
}

func TestARefusedProtectLeavesTheNameUnresolvedOutsideTheVPN(t *testing.T) {
	asked := protectRecorder(t, false)
	systemDNSIs(t, answeringDNS(t, "203.0.113.9"))

	_, err := lookupOutsideVPN("wg.shikoo.test")
	if err == nil || !strings.Contains(err.Error(), errOwnerProtectRefused.Error()) || len(*asked) == 0 {
		t.Fatalf("lookupOutsideVPN = %v after %d protect asks; want the refused protect named", err, len(*asked))
	}
}

func TestTheFirstDNSListOfAStartIsWaitedFor(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t)
	deviceDNSIs(t, answeringDNS(t, "198.51.100.10"))
	server := answeringDNS(t, "203.0.113.10")
	go func() {
		time.Sleep(150 * time.Millisecond)
		rememberSystemDNS([]string{server})
	}()

	wantAddress(t, "wg.shikoo.test", true, "203.0.113.10")
}

func TestWithoutAnOwnerCoresVPNNothingWaitsForADNSList(t *testing.T) {
	systemDNSIs(t)

	begun := time.Now()
	if _, err := lookupOutsideVPN("wg.shikoo.test"); !errors.Is(err, errNoSystemDNS) || time.Since(begun) > dnsListWait/2 {
		t.Fatalf("lookupOutsideVPN = %v after %v; want errNoSystemDNS at once, for the device's own DNS to answer", err, time.Since(begun))
	}
}

func TestAFailedLookupOutsideTheVPNFallsBackToTheDevicesOwnDNS(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t))
	deviceDNSIs(t, answeringDNS(t, "203.0.113.12"))

	wantAddress(t, "wg.shikoo.test", true, "203.0.113.12")
}

func TestASilentDNSServerIsGivenUpOnWithinItsTimeout(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, silentUDP(t))

	begun := time.Now()
	if _, err := lookupOutsideVPN("wg.shikoo.test"); err == nil || time.Since(begun) > 3*time.Second {
		t.Fatalf("a silent server: %v after %v; want an error within about 2 s", err, time.Since(begun))
	}
}

func TestTheNetworksDNSIsAskedWithinOneBudgetWhateverTheirNumber(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, silentUDP(t), silentUDP(t), silentUDP(t))
	budget := dnsBudget
	dnsBudget = time.Second
	t.Cleanup(func() { dnsBudget = budget })

	begun := time.Now()
	if _, err := lookupOutsideVPN("wg.shikoo.test"); err == nil || time.Since(begun) > 2*time.Second {
		t.Fatalf("three silent servers: %v after %v; want an error within the 1 s budget", err, time.Since(begun))
	}
}

func TestAnEmptyDNSListKeepsTheLastOneAndALiteralNeedsNone(t *testing.T) {
	systemDNSIs(t, "192.0.2.1:53")
	rememberSystemDNS([]string{""})
	rememberSystemDNS(nil)
	if got := systemDNS.Load(); got == nil || len(*got) != 1 || (*got)[0] != "192.0.2.1:53" {
		t.Fatalf("an empty list from Android replaced the last one: %v", got)
	}
	rememberSystemDNS([]string{"192.0.2.2:53", ""})
	if got := systemDNS.Load(); len(*got) != 1 || (*got)[0] != "192.0.2.2:53" {
		t.Fatalf("a new list is the last one without its empty entries: %v", *got)
	}
	if ip, err := lookupEndpoint("198.51.100.4"); err != nil || ip != netip.MustParseAddr("198.51.100.4") {
		t.Fatalf("a literal address needs no DNS: %v, %v", ip, err)
	}
}

// lib.go builds only for Android with cgo, so no test here can run it: its source is read.
func TestTheUpdateDnsHandlerKeepsTheListTheEndpointLookupAsks(t *testing.T) {
	source, err := os.ReadFile("lib.go")
	if err != nil {
		t.Fatal(err)
	}
	body := regexp.MustCompile(`(?s)func handleUpdateDns\(value string\) \{(.*?)\n\}`).FindSubmatch(source)
	if body == nil || !strings.Contains(string(body[1]), `rememberSystemDNS(strings.Split(value, ","))`) {
		t.Fatal("handleUpdateDns no longer gives Android's DNS list to rememberSystemDNS")
	}
}

func TestAnOpenvpnRemoteNameGoesToTheEngineAsItsAddressAndStaysAName(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "203.0.113.21"))
	deviceDNSIs(t, closedUDP(t))
	t.Cleanup(func() { ovpnPrepared.Store(nil) })

	plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": "ov.shikoo.test"}), false, true)
	if err != nil || !strings.Contains(plan.Profile, "\nremote 203.0.113.21 1194\n") || strings.Contains(plan.Profile, "shikoo.test") {
		t.Fatalf("profile = %q, %v; want the address and no name", plan, err)
	}
	if prepared := ovpnPrepared.Load(); prepared == nil || prepared.config.RemoteHost != "ov.shikoo.test" {
		t.Fatalf("the pings and the session need the name: %+v", prepared)
	}
}

func TestAnOpenvpnRebuildDialsTheAddressItsStartResolved(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "203.0.113.21"))
	deviceDNSIs(t, answeringDNS(t, "198.51.100.21"))
	t.Cleanup(func() { ovpnPrepared.Store(nil) })

	for _, held := range []bool{false, true} {
		plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": "ov.shikoo.test"}), false, held)
		if err != nil || !strings.Contains(plan.Profile, "\nremote 198.51.100.21 1194\n") {
			t.Fatalf("held=%v: profile %q, %v; want the start's address, 198.51.100.21", held, plan, err)
		}
	}
}

func TestAnOpenvpnRemoteAddressNeedsNoDNSAndAnUnansweredNameStaysTheName(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t))
	deviceDNSIs(t, closedUDP(t))
	t.Cleanup(func() { ovpnPrepared.Store(nil) })

	for _, remote := range []string{"203.0.113.9", "2001:db8::9", "ov.shikoo.test"} {
		plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": remote}), false, true)
		if err != nil || !strings.Contains(plan.Profile, "\nremote "+remote+" 1194\n") {
			t.Errorf("remote %s: profile %q, %v; want it as it came", remote, plan, err)
		}
	}
}
