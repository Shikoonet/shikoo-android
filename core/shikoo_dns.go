package main

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"slices"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// systemDNS: the last DNS servers ("host:53") Android's networks gave Go; a VPN a switch holds answers no DNS for this app.
var systemDNS atomic.Pointer[[]string]

var errNoSystemDNS = errors.New("no system DNS list")

func rememberSystemDNS(servers []string) {
	servers = slices.DeleteFunc(slices.Clone(servers), func(server string) bool { return server == "" })
	if len(servers) > 0 {
		systemDNS.Store(&servers)
	}
}

const dnsListWait = time.Second

// lookupOutsideVPN asks them from sockets VpnService.protect keeps out of the VPN; errNoSystemDNS with no list or no protect.
func lookupOutsideVPN(host string) ([]netip.Addr, error) {
	servers := systemDNS.Load()
	for deadline := time.Now().Add(dnsListWait); servers == nil && ownerProtect.holds() && time.Now().Before(deadline); {
		time.Sleep(50 * time.Millisecond)
		servers = systemDNS.Load()
	}
	if servers == nil {
		return nil, errNoSystemDNS
	}
	dialer := net.Dialer{Control: func(_, _ string, conn syscall.RawConn) (err error) {
		if controlErr := conn.Control(func(fd uintptr) { err = ownerProtect.socket(int(fd), true) }); controlErr != nil {
			return controlErr
		}
		return err
	}}
	var failed []string
	for _, server := range *servers {
		// The resolver dials resolv.conf's servers, which Android lacks: each dial goes to ours.
		resolver := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, server)
		}}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		ips, err := resolver.LookupNetIP(ctx, "ip", host)
		cancel()
		if err == nil {
			return ips, nil
		}
		failed = append(failed, server+": "+err.Error())
	}
	return nil, errors.New(strings.Join(failed, "; "))
}

func pinnedHost(host string) string {
	if ip, err := lookupEndpoint(host); err == nil {
		return ip.String()
	}
	return host
}
