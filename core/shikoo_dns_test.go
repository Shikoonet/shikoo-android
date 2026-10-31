package main

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"strings"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// answeringDNS answers every A question with ip, on a loopback UDP port.
func answeringDNS(t *testing.T, ip string) string {
	t.Helper()
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &dns.Server{PacketConn: conn, Handler: dns.HandlerFunc(func(w dns.ResponseWriter, r *dns.Msg) {
		reply := new(dns.Msg)
		reply.SetReply(r)
		if question := r.Question[0]; question.Qtype == dns.TypeA {
			header := dns.RR_Header{Name: question.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60}
			reply.Answer = []dns.RR{&dns.A{Hdr: header, A: net.ParseIP(ip)}}
		}
		_ = w.WriteMsg(reply)
	})}
	go func() { _ = server.ActivateAndServe() }()
	t.Cleanup(func() { _ = server.Shutdown() })
	return conn.LocalAddr().String()
}

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

func systemDNSIs(t *testing.T, servers ...string) {
	t.Helper()
	systemDNS.Store(nil)
	t.Cleanup(func() { systemDNS.Store(nil) })
	if len(servers) > 0 {
		rememberSystemDNS(servers)
	}
}

func TestAnEndpointNameIsAskedOfTheSystemDNSFromProtectedSockets(t *testing.T) {
	asked := protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "203.0.113.7"))

	ip, err := lookupEndpoint("wg.shikoo.test")
	if err != nil || ip != netip.MustParseAddr("203.0.113.7") {
		t.Fatalf("lookupEndpoint = %v, %v; want 203.0.113.7", ip, err)
	}
	if len(*asked) == 0 {
		t.Fatal("the DNS socket was never protected: inside an owner core's VPN its query goes nowhere")
	}
}

func TestADeadSystemDNSServerPassesTheNameOnToTheNext(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t), answeringDNS(t, "203.0.113.8"))

	ip, err := lookupEndpoint("wg.shikoo.test")
	if err != nil || ip != netip.MustParseAddr("203.0.113.8") {
		t.Fatalf("lookupEndpoint = %v, %v; want the second server's 203.0.113.8", ip, err)
	}
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
	server := answeringDNS(t, "203.0.113.10")
	go func() {
		time.Sleep(150 * time.Millisecond)
		rememberSystemDNS([]string{server})
	}()

	if ip, err := lookupEndpoint("wg.shikoo.test"); err != nil || ip != netip.MustParseAddr("203.0.113.10") {
		t.Fatalf("lookupEndpoint = %v, %v; want the list's answer, 203.0.113.10", ip, err)
	}
}

func TestWithoutAnOwnerCoresVPNNothingWaitsForADNSList(t *testing.T) {
	systemDNSIs(t)

	begun := time.Now()
	if _, err := lookupOutsideVPN("wg.shikoo.test"); !errors.Is(err, errNoSystemDNS) || time.Since(begun) > dnsListWait/2 {
		t.Fatalf("lookupOutsideVPN = %v after %v; want errNoSystemDNS at once, for the device is own DNS to answer", err, time.Since(begun))
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

func TestAFailedLookupOutsideTheVPNFallsBackToTheDevicesOwnDNS(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t))
	device := answeringDNS(t, "203.0.113.12")
	previous := net.DefaultResolver
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, device)
	}}
	t.Cleanup(func() { net.DefaultResolver = previous })

	if ip, err := lookupEndpoint("wg.shikoo.test"); err != nil || ip != netip.MustParseAddr("203.0.113.12") {
		t.Fatalf("lookupEndpoint = %v, %v; want the default resolver answer, 203.0.113.12", ip, err)
	}
}

func TestAnOpenvpnRemoteNameGoesToTheEngineAsItsAddressAndStaysAName(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, answeringDNS(t, "203.0.113.21"))
	t.Cleanup(func() { ovpnPrepared.Store(nil) })

	plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": "ov.shikoo.test"}), false)
	if err != nil || !strings.Contains(plan.Profile, "\nremote 203.0.113.21 1194\n") || strings.Contains(plan.Profile, "shikoo.test") {
		t.Fatalf("profile = %q, %v; want the address and no name", plan, err)
	}
	if prepared := ovpnPrepared.Load(); prepared == nil || prepared.config.RemoteHost != "ov.shikoo.test" {
		t.Fatalf("the pings and the session need the name: %+v", prepared)
	}
}

func TestAnOpenvpnRemoteAddressNeedsNoDNSAndAnUnansweredNameStaysTheName(t *testing.T) {
	protectRecorder(t, true)
	systemDNSIs(t, closedUDP(t))
	previous := net.DefaultResolver
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, closedUDP(t))
	}}
	t.Cleanup(func() { net.DefaultResolver = previous; ovpnPrepared.Store(nil) })

	for _, remote := range []string{"203.0.113.9", "2001:db8::9", "ov.shikoo.test"} {
		plan, err := ovpnPrepare(ovpnMapping(map[string]any{"server": remote}), false)
		if err != nil || !strings.Contains(plan.Profile, "\nremote "+remote+" 1194\n") {
			t.Errorf("remote %s: profile %q, %v; want it as it came", remote, plan, err)
		}
	}
}
