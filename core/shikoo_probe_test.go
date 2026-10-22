package main

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"runtime"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/dialer"
)

func answerAfter(t *testing.T, wait time.Duration) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(wait)
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)
	return server.URL + "/generate_204"
}

func TestTestProxyDelayIsDispatchable(t *testing.T) {
	if _, ok := methodHandlers[testProxyDelayMethod]; !ok {
		t.Fatal("testProxyDelay answers not_implemented")
	}
}

func TestTestProxyDelayMeasuresAMappingThroughTheSocketHook(t *testing.T) {
	var hooked atomic.Int32
	previous := dialer.DefaultSocketHook
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		hooked.Add(1)
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = previous })

	delay, err := handleTestProxyDelay(&TestProxyDelayParams{
		Proxy:   map[string]any{"name": "هلند ۱", "type": "direct"},
		TestUrl: answerAfter(t, 5*time.Millisecond),
		Timeout: 2000,
	})
	if err != nil || delay == nil {
		t.Fatalf("delay %v, err %v", delay, err)
	}
	if delay.Name != "هلند ۱" || delay.Value <= 0 {
		t.Fatalf("got %+v, want the mapping's name and a time", delay)
	}
	if hooked.Load() == 0 {
		t.Fatal("the probe's socket skipped the hook that protects sockets from the tunnel")
	}
}

func TestTestProxyDelayTimesOutAsNoAnswer(t *testing.T) {
	delay, err := handleTestProxyDelay(&TestProxyDelayParams{
		Proxy:   map[string]any{"name": "dead", "type": "direct"},
		TestUrl: answerAfter(t, time.Second),
		Timeout: 200,
	})
	if err != nil || delay == nil || delay.Value != -1 {
		t.Fatalf("delay %+v, err %v; want -1 and no error", delay, err)
	}
}

func TestTestProxyDelayRejectsAMappingItCannotBuild(t *testing.T) {
	for _, mapping := range []map[string]any{
		{"name": "no type"},
		{"name": "unknown", "type": "teleport"},
		{"name": "bad key", "type": "wireguard", "server": "127.0.0.1", "port": 1, "private-key": "%%", "public-key": "%%", "ip": "10.0.0.2"},
	} {
		if delay, err := handleTestProxyDelay(&TestProxyDelayParams{Proxy: mapping, Timeout: 200}); err == nil {
			t.Errorf("%v: got %+v and no error", mapping["name"], delay)
		}
	}
}

func TestTestProxyDelayReleasesItsWireGuardDevice(t *testing.T) {
	withWireGuardGrace(t, 0)
	probe := func() {
		delay, err := handleTestProxyDelay(&TestProxyDelayParams{
			Proxy:   deadWireGuard(),
			TestUrl: "http://10.0.0.1/generate_204",
			Timeout: 300,
		})
		if err != nil || delay == nil || delay.Value != -1 {
			t.Fatalf("delay %+v, err %v; want -1 from a peer that never answers", delay, err)
		}
	}
	settled := func() int {
		time.Sleep(200 * time.Millisecond)
		return runtime.NumGoroutine()
	}

	probe()
	before := settled()
	probe()
	deadline := time.Now().Add(3 * time.Second)
	for runtime.NumGoroutine() > before && time.Now().Before(deadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if after := runtime.NumGoroutine(); after > before {
		t.Fatalf("%d goroutines after the probe, %d before: its WireGuard device is still running", after, before)
	}
}

func withWireGuardGrace(t *testing.T, grace time.Duration) {
	previous := wireGuardGrace
	wireGuardGrace = grace
	t.Cleanup(func() { wireGuardGrace = previous })
}

func deadWireGuard() map[string]any {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	return map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": 1,
		"private-key": key, "public-key": key, "ip": "10.0.0.2", "udp": true,
	}
}

func TestProbeTimeoutGivesWireGuardOneMoreHandshake(t *testing.T) {
	for _, tc := range []struct {
		mapping map[string]any
		want    time.Duration
	}{
		{deadWireGuard(), 13 * time.Second},
		{map[string]any{"name": "direct", "type": "direct"}, 8 * time.Second},
	} {
		proxy, err := adapter.ParseProxy(tc.mapping)
		if err != nil {
			t.Fatal(err)
		}
		if got := probeTimeout(proxy, 8*time.Second); got != tc.want {
			t.Errorf("%s: %v, want %v", tc.mapping["type"], got, tc.want)
		}
		_ = proxy.Close()
	}
}

func TestTestProxyDelayWaitsTheGraceForWireGuard(t *testing.T) {
	withWireGuardGrace(t, 400*time.Millisecond)
	start := time.Now()
	delay, err := handleTestProxyDelay(&TestProxyDelayParams{
		Proxy:   deadWireGuard(),
		TestUrl: "http://10.0.0.1/generate_204",
		Timeout: 200,
	})
	if err != nil || delay == nil || delay.Value != -1 {
		t.Fatalf("delay %+v, err %v; want -1 from a peer that never answers", delay, err)
	}
	if took := time.Since(start); took < 600*time.Millisecond {
		t.Fatalf("gave up after %v, before the 200 ms timeout and the 400 ms grace", took)
	}
}
