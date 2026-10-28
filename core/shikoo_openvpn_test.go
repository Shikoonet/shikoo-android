package main

import (
	"testing"
	"time"

	ovpn "github.com/metacubex/mihomo/transport/openvpn"
)

// The PUSH_REPLY OpenVPN 2.6 sent for "keepalive 10 60" (.notes/mc-movpn-2026-10-27).
const pushedKeepalive = "PUSH_REPLY,dhcp-option DNS 1.1.1.1,route-gateway 10.8.3.1,topology subnet,ping 10," +
	"ping-restart 60,ifconfig 10.8.3.2 255.255.255.0,peer-id 0,cipher AES-256-GCM"

func TestOpenVPNTakesTheServersKeepaliveWhenTheConfigSetsNone(t *testing.T) {
	push, err := ovpn.ParsePushReply(pushedKeepalive)
	if err != nil {
		t.Fatal(err)
	}
	ping, restart := ovpn.ClientConfig{}.ShikooKeepalive(push)
	if ping != 10*time.Second || restart != 60*time.Second {
		t.Fatalf("got ping %s and ping-restart %s, want the pushed 10s and 60s: a UDP session the server "+
			"dropped (idle, or the same account elsewhere) would never be noticed", ping, restart)
	}

	set := ovpn.ClientConfig{PingInterval: 5 * time.Second, PingRestart: 30 * time.Second}
	if ping, restart := set.ShikooKeepalive(push); ping != 5*time.Second || restart != 30*time.Second {
		t.Fatalf("the config's own ping 5s and ping-restart 30s gave %s and %s", ping, restart)
	}

	bare, err := ovpn.ParsePushReply("PUSH_REPLY,ifconfig 10.8.3.2 255.255.255.0")
	if err != nil {
		t.Fatal(err)
	}
	if ping, restart := (ovpn.ClientConfig{}).ShikooKeepalive(bare); ping != 0 || restart != 0 {
		t.Fatalf("nothing pushed and nothing set gave ping %s and ping-restart %s, want none", ping, restart)
	}
}
