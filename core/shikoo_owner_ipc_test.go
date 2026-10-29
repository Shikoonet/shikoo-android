//go:build !cgo

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"sync/atomic"
	"testing"
	"time"

	ovpn "github.com/metacubex/mihomo/transport/openvpn"
	"github.com/metacubex/mihomo/tunnel"
)

// askDelay is Dart's ping of a server; a server outside the applied config gets mihomo's -1.
func askDelay(t *testing.T, name string) int32 {
	t.Helper()
	arguments, _ := json.Marshal(TestDelayParams{ProxyName: name, Timeout: 300})
	fake := &fakeConn{}
	previous := swapConn(fake)
	defer swapConn(previous)
	methodHandlers[asyncTestDelayMethod](
		&MethodCall{ID: "ping", Method: asyncTestDelayMethod, Arguments: arguments}, MethodResponse{ID: "ping"})
	for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
		for _, frame := range fake.frames(t) {
			var answer struct {
				ID     string
				Result Delay
			}
			if json.Unmarshal(frame, &answer) == nil && answer.ID == "ping" {
				return answer.Result.Value
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("no answer for %q", name)
	return 0
}

func TestTheOwnerAnswersThePingOfTheServerItCarries(t *testing.T) {
	var pinged atomic.Int32
	carrying := fakeOwner(t, func(params *TestDelayParams) *Delay {
		pinged.Add(1)
		return &Delay{Name: params.ProxyName, Value: 42}
	})

	*carrying = "W"
	if got := askDelay(t, "W"); got != 42 || pinged.Load() != 1 {
		t.Errorf("answer %d after %d engine pings, want the engine's 42 from one", got, pinged.Load())
	}
	*carrying = "X"
	if got := askDelay(t, "W"); got != -1 || pinged.Load() != 1 {
		t.Errorf("W while X is carried: answer %d after %d engine pings, want mihomo's -1", got, pinged.Load())
	}
	*carrying = ""
	if got := askDelay(t, ""); got != -1 || pinged.Load() != 1 {
		t.Errorf("a nameless ping with nothing carried: answer %d after %d engine pings, want mihomo's -1",
			got, pinged.Load())
	}
}

func TestAMarkedServerItsOwnerDoesNotCarryGetsTheCoresIdlePing(t *testing.T) {
	carrying := fakeOwner(t, func(params *TestDelayParams) *Delay { return &Delay{Name: params.ProxyName, Value: 42} })
	shikooOwnerIdlePings["fake-owner"] = ovpnIdlePing
	t.Cleanup(func() { delete(shikooOwnerIdlePings, "fake-owner") })
	address, heard := resetServer(t, "udp", nil, ovpn.PControlHardResetServerV2)
	host, port, _ := net.SplitHostPort(address)
	cfg := parseShikooCores(t, fmt.Sprintf(`proxies:
  - {name: ov, type: openvpn, server: %s, port: %s, ca: %q, username: shikoo, password: secret, shikoo-owner: fake-owner}
`, host, port, testCA))
	proxies, providers := tunnel.Proxies(), tunnel.Providers()
	tunnel.UpdateProxies(cfg.Proxies, providers)
	t.Cleanup(func() { tunnel.UpdateProxies(proxies, providers) })

	if got := askDelay(t, "ov"); got <= 0 || got == 42 || len(heard()) != 1 {
		t.Errorf("answer %d after the server heard %d packets, want the reset's own time from one", got, len(heard()))
	}
	*carrying = "ov"
	if got := askDelay(t, "ov"); got != 42 || len(heard()) != 1 {
		t.Errorf("carried: answer %d after the server heard %d packets, want the engine's 42", got, len(heard()))
	}
}

func TestAnOwnerWithNoPingLeavesItToMihomo(t *testing.T) {
	*fakeOwner(t, nil) = "W"

	if got := askDelay(t, "W"); got != -1 {
		t.Errorf("answer %d, want mihomo's -1", got)
	}
}
