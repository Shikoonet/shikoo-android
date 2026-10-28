//go:build !windows

package main

import (
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/tunnel"
)

// Only Windows' TUN mode hands its tun to the owner core here; Android's VPN service does it through lib.go.
func reCreateTun(conf LC.Tun) { listener.ReCreateTun(conf, tunnel.Tunnel) }

func stopOwnerTun() {}
