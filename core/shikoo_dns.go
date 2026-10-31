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

// lastEndpoint: the host and address of the owner session running unbroken (a full stop or mihomo's tunnel clears it).
var lastEndpoint atomic.Pointer[pinnedEndpoint]

type pinnedEndpoint struct {
	host string
	addr netip.Addr
}

func rememberSystemDNS(servers []string) {
	servers = slices.DeleteFunc(slices.Clone(servers), func(server string) bool { return server == "" })
	if len(servers) > 0 {
		systemDNS.Store(&servers)
	}
}

const (
	dnsListWait      = time.Second
	dnsServerTimeout = 2 * time.Second
	deviceTimeout    = 5 * time.Second
)

var dnsBudget = 6 * time.Second

var deviceResolver = func() *net.Resolver { return net.DefaultResolver }

// resolveEndpoint: a fresh start asks the device's resolver; a rebuild under a held VPN, which answers no DNS, does not.
func resolveEndpoint(host string, held bool) (netip.Addr, error) {
	if ip, err := netip.ParseAddr(host); err == nil {
		return ip.Unmap(), nil
	}
	if last := lastEndpoint.Load(); held && last != nil && last.host == host {
		return last.addr, nil
	}
	lookups := []func(string) ([]netip.Addr, error){lookupDevice, lookupOutsideVPN}
	if held {
		slices.Reverse(lookups)
	}
	var failed []string
	for _, lookup := range lookups {
		ips, err := lookup(host)
		if err != nil {
			failed = append(failed, err.Error())
			continue
		}
		addr := ips[0].Unmap()
		if i := slices.IndexFunc(ips, func(ip netip.Addr) bool { return ip.Unmap().Is4() }); i >= 0 {
			addr = ips[i].Unmap()
		}
		lastEndpoint.Store(&pinnedEndpoint{host, addr})
		return addr, nil
	}
	return netip.Addr{}, errors.New(strings.Join(failed, "; "))
}

func lookupEndpoint(host string) (netip.Addr, error) { return resolveEndpoint(host, false) }

func pinnedHost(host string, held bool) string {
	if ip, err := resolveEndpoint(host, held); err == nil {
		return ip.String()
	}
	return host
}

func lookupDevice(host string) ([]netip.Addr, error) {
	ctx, cancel := context.WithTimeout(context.Background(), deviceTimeout)
	defer cancel()
	ips, err := deviceResolver().LookupNetIP(ctx, "ip", host)
	if err == nil && len(ips) == 0 {
		err = errors.New("no address")
	}
	return ips, err
}

// lookupOutsideVPN: the networks' DNS from protected sockets; a private, loopback, link-local or unspecified answer is poison.
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
	end := time.Now().Add(dnsBudget)
	for _, server := range *servers {
		if !time.Now().Before(end) {
			break
		}
		resolver := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, server)
		}}
		ctx, cancel := context.WithTimeout(context.Background(), min(dnsServerTimeout, time.Until(end)))
		ips, err := resolver.LookupNetIP(ctx, "ip", host)
		cancel()
		if err == nil {
			ips = slices.DeleteFunc(ips, func(ip netip.Addr) bool {
				ip = ip.Unmap()
				return ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
			})
			if len(ips) > 0 {
				return ips, nil
			}
			err = errors.New("no address a server can have")
		}
		failed = append(failed, server+": "+err.Error())
	}
	return nil, errors.New("network DNS " + strings.Join(failed, "; "))
}
