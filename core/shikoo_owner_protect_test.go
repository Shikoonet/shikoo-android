package main

import (
	"errors"
	"net"
	"slices"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
	wgconn "golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/tun/tuntest"
)

// protectRecorder stands in for Android's VpnService.protect.
func protectRecorder(t *testing.T, answer bool) *[]int {
	t.Helper()
	asked, released := []int{}, false
	var mu sync.Mutex
	ownerProtect.set(func(fd int) bool {
		mu.Lock()
		defer mu.Unlock()
		asked = append(asked, fd)
		return answer
	}, func() { released = true })
	t.Cleanup(func() {
		ownerProtect.set(nil, nil)
		if !released {
			t.Error("the protect func's Java callback was never released")
		}
	})
	return &asked
}

func TestOwnerSocketsAreProtectedOnlyWhileAnOwnerCoresVPNHoldsTheApp(t *testing.T) {
	if err := ownerProtect.socket(5, false); err != nil {
		t.Fatalf("no owner core: a dial got %v, want it through untouched", err)
	}
	if err := ownerProtect.socket(5, true); !errors.Is(err, errOwnerUnprotected) {
		t.Fatalf("no owner core: an engine socket got %v, want %v", err, errOwnerUnprotected)
	}

	asked := protectRecorder(t, true)
	if err := ownerProtect.socket(7, false); err != nil || !slices.Equal(*asked, []int{7}) {
		t.Fatalf("an owner core: a dial got %v and protect saw %v, want fd 7 protected", err, *asked)
	}

	protectRecorder(t, false)
	if err := ownerProtect.socket(8, false); !errors.Is(err, errOwnerProtectRefused) {
		t.Fatalf("protect refused: a dial got %v, want %v, or it would loop into the tunnel", err, errOwnerProtectRefused)
	}
}

// peekBind is a real bind that shows two fds, as Android's StdNetBind shows its sockets.
type peekBind struct {
	wgconn.Bind
	closed bool
}

func (b *peekBind) PeekLookAtSocketFd4() (int, error) { return 41, nil }
func (b *peekBind) PeekLookAtSocketFd6() (int, error) { return 0, errors.New("no IPv6 socket") }
func (b *peekBind) Close() error                      { b.closed = true; return b.Bind.Close() }

func TestTheOfficialWireGuardEngineProtectsItsOwnSocketOrDoesNotOpen(t *testing.T) {
	unprotected := &peekBind{Bind: wgconn.NewDefaultBind()}
	if _, _, err := (protectedBind{unprotected}).Open(0); !errors.Is(err, errOwnerUnprotected) || !unprotected.closed {
		t.Fatalf("no protect at all: open %v, closed %v, want %v and the bind shut", err, unprotected.closed, errOwnerUnprotected)
	}

	refused := &peekBind{Bind: wgconn.NewDefaultBind()}
	protectRecorder(t, false)
	if _, _, err := (protectedBind{refused}).Open(0); err == nil || !refused.closed {
		t.Fatalf("protect refused: open %v, closed %v; the engine's socket would loop into its own tunnel", err, refused.closed)
	}

	asked := protectRecorder(t, true)
	bind := &peekBind{Bind: wgconn.NewDefaultBind()}
	startTestOwnerProtected(t, bind)
	if !slices.Equal(*asked, []int{41}) {
		t.Fatalf("protect saw %v, want the engine's socket 41 kept out of the VPN it carries", *asked)
	}
}

// startTestOwnerProtected: startTestOwner (shikoo_wg_test.go), through the Android engine's start.
func startTestOwnerProtected(t *testing.T, bind peekingBind) {
	t.Helper()
	private, public := wgKeyPair(t)
	server, _, serverPublic, port := wgServer(t, public)
	t.Cleanup(server.Close)
	_, prepared, err := wgPlan(map[string]any{
		"name": "wg", "type": "wireguard", "server": "127.0.0.1", "port": port, "ip": "10.13.13.2",
		"private-key": b64(private), "public-key": b64(serverPublic),
	}, nil, 35, noResolve)
	if err != nil {
		t.Fatal(err)
	}
	ownerMu.Lock()
	ownerPrepared = prepared
	ownerMu.Unlock()
	if err := startProtectedOwner(tuntest.NewChannelTUN().TUN(), bind); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(stopOwner)
}

func TestAnOwnerStartOpensTheListenersASwitchsStopShut(t *testing.T) {
	write := applyHome(t)
	free, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := strconv.Itoa(free.Addr().(*net.TCPAddr).Port)
	_ = free.Close()
	t.Cleanup(func() {
		isRunning.Store(false)
		listener.ReCreateMixed(0, tunnel.Tunnel)
	})
	write("mixed-port: " + port + "\nproxies: []\nrules:\n  - MATCH,DIRECT\n")
	isRunning.Store(false)
	if err := applyConfig(&SetupParams{}); err != nil {
		t.Fatal(err)
	}
	listening := func() bool {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:"+port, time.Second)
		if err == nil {
			_ = conn.Close()
		}
		return err == nil
	}
	if listening() {
		t.Fatal("the mixed port listens before any start: the test proves nothing")
	}

	restartListenersIfStopped()

	if !listening() || !isRunning.Load() {
		t.Fatal("after an owner start the mixed port is shut: the door, the report and the internet check fail")
	}
}
