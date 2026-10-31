package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/bits"
	"net/netip"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"github.com/metacubex/mihomo/log"
	ovpn "github.com/metacubex/mihomo/transport/openvpn"
	"github.com/metacubex/mihomo/tunnel/statistic"
	singtun "github.com/metacubex/sing-tun"
	"golang.org/x/sys/windows"
)

// The official OpenVPN engine on Windows: OpenVPN 3 in ShikooNetOvpn3.dll, run as OpenVpn.kt runs it, with wintun as the tunnel.

const (
	ovpnDLLName = "ShikooNetOvpn3.dll"
	// OpenVPN 3's event, and so the session's error, when the server refused the username and password.
	ovpnAuthFailed = "AUTH_FAILED"
)

var (
	ovpnConnectLimit = 20 * time.Second
	ovpnStopTries    = 50
	ovpnStopStep     = 200 * time.Millisecond
)

type ovpnLib struct {
	run    func(profile, username, password string) string
	halt   func()
	packet func(packet []byte)
}

var (
	ovpnLibMu sync.Mutex
	ovpnFound *ovpnLib

	// Beside the core, as ShikooNetWarp.exe is (shikoo_warp.go): the installer puts both in Program Files.
	ovpnDLLPath = func() string {
		exe, _ := os.Executable()
		return filepath.Join(filepath.Dir(exe), ovpnDLLName)
	}
	ovpnLoad  = loadOvpn
	wintunNew = newWintun

	ovpnLive    atomic.Pointer[ovpnWin]
	ovpnLiveMu  sync.Mutex
	ovpnLatest  atomic.Int64
	ovpnCounter atomic.Int64
)

// Made once: a Go callback's slot is never freed.
type ovpnCallbacks struct{ protect, establish, write, event uintptr }

var ovpnCallbacksOnce = sync.OnceValue(func() *ovpnCallbacks {
	return &ovpnCallbacks{
		protect: syscall.NewCallback(func(socket, ipv6 uintptr) uintptr {
			return guarded(0, func() uintptr {
				if s := ovpnLive.Load(); s != nil && s.protect(windows.Handle(socket), ipv6 != 0) {
					return 1
				}
				return 0
			})
		}),
		establish: syscall.NewCallback(func(spec *byte) uintptr {
			return guarded(1, func() uintptr {
				if s := ovpnLive.Load(); s != nil && s.establish(windows.BytePtrToString(spec)) {
					return 0
				}
				return 1
			})
		}),
		write: syscall.NewCallback(func(packet *byte, size uintptr) uintptr {
			return guarded(1, func() uintptr {
				if s := ovpnLive.Load(); s != nil && s.write(unsafe.Slice(packet, size)) {
					return 0
				}
				return 1
			})
		}),
		event: syscall.NewCallback(func(name, info *byte, isError uintptr) uintptr {
			return guarded(0, func() uintptr {
				if s := ovpnLive.Load(); s != nil {
					s.event(windows.BytePtrToString(name), windows.BytePtrToString(info), isError != 0)
				}
				return 0
			})
		}),
	}
})

// guarded: a panic on the engine's thread would take the whole core with it.
func guarded(refused uintptr, call func() uintptr) (answer uintptr) {
	defer func() {
		if r := recover(); r != nil {
			log.Errorln("[OpenVPN] callback panicked: %v", r)
			answer = refused
		}
	}()
	return call()
}

func loadOvpn() (*ovpnLib, error) {
	ovpnLibMu.Lock()
	defer ovpnLibMu.Unlock()
	if ovpnFound != nil {
		return ovpnFound, nil
	}
	handle, err := windows.LoadLibraryEx(ovpnDLLPath(), 0, windows.LOAD_LIBRARY_SEARCH_SYSTEM32)
	if err != nil {
		return nil, err
	}
	var run, halt, packet uintptr
	for name, slot := range map[string]*uintptr{"shikoo_ovpn3_run": &run, "shikoo_ovpn3_halt": &halt, "shikoo_ovpn3_packet": &packet} {
		if *slot, err = windows.GetProcAddress(handle, name); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
	}
	callbacks := ovpnCallbacksOnce()
	ovpnFound = &ovpnLib{
		run: func(profile, username, password string) string {
			var text [3]*byte
			for i, value := range []string{profile, username, password} {
				var perr error
				if text[i], perr = windows.BytePtrFromString(value); perr != nil {
					return "refused: " + perr.Error()
				}
			}
			// The engine writes its answer here when run ends, minutes on: on this goroutine's stack it would have moved.
			var pin runtime.Pinner
			defer pin.Unpin()
			out := make([]byte, 512)
			pin.Pin(&out[0])
			syscall.SyscallN(run, uintptr(unsafe.Pointer(text[0])), uintptr(unsafe.Pointer(text[1])), uintptr(unsafe.Pointer(text[2])),
				uintptr(unsafe.Pointer(callbacks)), uintptr(unsafe.Pointer(&out[0])), uintptr(len(out)))
			return windows.ByteSliceToString(out)
		},
		halt: func() { syscall.SyscallN(halt) },
		packet: func(data []byte) {
			syscall.SyscallN(packet, uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)))
		},
	}
	return ovpnFound, nil
}

type ovpnWin struct {
	id       int
	server   string
	device   string
	config   *ovpn.ClientConfig
	lib      *ovpnLib
	physical func() uint32
	ended    chan struct{}

	connected, stopping, stuck, timedOut, broken atomic.Bool
	lastError, result                            atomic.Value
	tun                                          atomic.Pointer[ovpnTun]
	mu                                           sync.Mutex
}

type ovpnTun struct {
	wintun   singtun.WinTun
	plan     *ownerPlan
	v4, v6   bool
	finished chan struct{}
}

// startOpenvpn fails only for what it sees now: the server pushes the tunnel's address once connected, and the rest ends in ovpnEnded.
func (o *ownerTunnel) startOpenvpn(device string, mapping map[string]any, iranDirect bool) (err error) {
	defer func() {
		if err != nil {
			ovpnEnded.Store(&ovpnOutcome{state: stateFailed, reason: err.Error()})
		}
	}()
	if err = o.startMonitor(); err != nil {
		return err
	}
	o.watch(func() {})
	o.install()
	return ovpnWinStart(device, mapping, iranDirect, o.physicalIndex)
}

func ovpnWinStart(device string, mapping map[string]any, iranDirect bool, physical func() uint32) error {
	if _, err := ovpnPrepare(mapping, iranDirect); err != nil {
		return err
	}
	lib, err := ovpnLoad()
	if err != nil {
		return fmt.Errorf("no engine: %w", err)
	}
	if live := ovpnLive.Load(); live != nil && live.stuck.Load() {
		return errors.New("the last session did not stop")
	}
	prepared := ovpnPrepared.Load()
	s := &ovpnWin{
		id: int(ovpnCounter.Add(1)), server: prepared.server, device: device, config: prepared.config, lib: lib,
		physical: physical, ended: make(chan struct{}),
	}
	// The newest ask first, so what the last session still says is refused while it stops.
	ovpnLatest.Store(int64(s.id))
	if !ovpnWinStop() {
		return errors.New("the last session did not stop")
	}
	// After the stop: the last session's end may still be storing its failure, which this start must not read as its own.
	ovpnEnded.Store(nil)
	ovpnLiveMu.Lock()
	ovpnLive.Store(s)
	ovpnLiveMu.Unlock()
	// First, so mihomo's own client of this server is shut before ours dials, and the server is carried at once.
	s.report(false)
	go s.run()
	return nil
}

// halt() is lost until the session takes calls from another thread, so it is repeated.
func ovpnWinStop() bool {
	s := ovpnLive.Load()
	if s == nil {
		return true
	}
	s.stopping.Store(true)
	if s.stuck.Load() {
		s.kick()
		return false
	}
	if s.halt() {
		return true
	}
	s.stuck.Store(true)
	log.Warnln("[OpenVPN] did not stop in time")
	return false
}

func (s *ovpnWin) halt() bool {
	for range ovpnStopTries {
		select {
		case <-s.ended:
			return true
		default:
		}
		s.kick()
		select {
		case <-s.ended:
			return true
		case <-time.After(ovpnStopStep):
		}
	}
	return false
}

// kick halts the DLL's one session, and only while s is still the live one: a newer session may have started.
func (s *ovpnWin) kick() {
	ovpnLiveMu.Lock()
	defer ovpnLiveMu.Unlock()
	if ovpnLive.Load() == s {
		s.lib.halt()
	}
}

func (s *ovpnWin) stale() bool {
	return s.stopping.Load() || ovpnLatest.Load() != int64(s.id)
}

func (s *ovpnWin) report(up bool) {
	ovpnState(&ovpnStateParams{Session: s.id, Server: s.server, Up: up})
}

func (s *ovpnWin) run() {
	defer s.finish()
	limit := time.AfterFunc(ovpnConnectLimit, s.timeout)
	defer limit.Stop()
	if s.stopping.Load() {
		return
	}
	// The name is looked up before the tunnel is up: a reconnect's lookup would ask the tunnel's own DNS.
	ip, err := lookupEndpoint(s.config.RemoteHost)
	if err != nil {
		s.result.Store(fmt.Sprintf("endpoint %s: %v", s.config.RemoteHost, err))
		return
	}
	if s.stopping.Load() {
		return
	}
	s.result.Store(s.lib.run(ovpnPinned(s.config, ip), s.config.Username, s.config.Password))
}

func (s *ovpnWin) timeout() {
	if s.connected.Load() || s.stopping.Load() {
		return
	}
	s.timedOut.Store(true)
	s.stopping.Store(true)
	s.halt()
}

func (s *ovpnWin) finish() {
	s.closeTun()
	if ovpnLatest.Load() == int64(s.id) {
		if outcome := s.outcome(); outcome != nil {
			ovpnEnded.Store(outcome)
		}
	}
	ovpnState(&ovpnStateParams{Session: s.id})
	ovpnLive.CompareAndSwap(s, nil)
	close(s.ended)
	log.Infoln("[OpenVPN] session %d ended", s.id)
}

// outcome: a refused login ends run() without an error of its own, so the event said why (OpenVpn.kt's lastError).
func (s *ovpnWin) outcome() *ovpnOutcome {
	switch reason, _ := s.result.Load().(string); {
	case s.timedOut.Load():
		return &ovpnOutcome{stateFailed, fmt.Sprintf("no connection in %v", ovpnConnectLimit)}
	case s.stopping.Load() && !s.broken.Load():
		return nil
	default:
		if reason == "" {
			reason, _ = s.lastError.Load().(string)
		}
		state := stateFailed
		if strings.Contains(reason, ovpnAuthFailed) {
			state = stateRefused
		}
		return &ovpnOutcome{state, reason}
	}
}

func (s *ovpnWin) event(name, info string, isError bool) {
	if name == "LOG" || s.stale() {
		return
	}
	switch name {
	case "CONNECTED":
		s.connected.Store(true)
		s.report(true)
	case "RECONNECTING", "PAUSE", "DISCONNECTED":
		s.report(false)
	}
	if isError {
		s.lastError.Store(name + ": " + info)
		log.Warnln("[OpenVPN] %s: %s", name, info)
		return
	}
	log.Infoln("[OpenVPN] %s", name) // CONNECTED's info names the account
}

// shortcut: a socket keeps the interface it was made on, so a network change waits for the engine's reconnect; follow the monitor if slow.
func (s *ovpnWin) protect(socket windows.Handle, ipv6 bool) bool {
	if s.stale() {
		return false
	}
	index := s.physical()
	if index == 0 {
		return false
	}
	var err error
	if ipv6 {
		err = windows.SetsockoptInt(socket, windows.IPPROTO_IPV6, 31, int(index)) // IPV6_UNICAST_IF
	} else {
		// IP_UNICAST_IF takes an IPv4 interface index in network byte order.
		err = windows.SetsockoptInt(socket, windows.IPPROTO_IP, 31, int(bits.ReverseBytes32(index)))
	}
	if err != nil {
		log.Warnln("[OpenVPN] socket not bound to interface %d: %v", index, err)
	}
	return err == nil
}

// A reconnect asks again: the same plan keeps the adapter, and packets read meanwhile go nowhere, so none leaves around it.
func (s *ovpnWin) establish(text string) bool {
	var spec ovpnTunnelSpec
	if s.stale() || json.Unmarshal([]byte(text), &spec) != nil {
		return false
	}
	plan, err := ovpnTunnel(&spec, windowsSdk)
	if err != nil {
		log.Warnln("[OpenVPN] tunnel plan: %v", err)
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if have := s.tun.Load(); have != nil {
		if reflect.DeepEqual(have.plan, plan) {
			return true
		}
		s.closeTunLocked()
	}
	wintun, err := wintunNew(wintunOptions(s.device, plan))
	if err != nil {
		log.Warnln("[OpenVPN] wintun not built: %v", err)
		return false
	}
	tun := &ovpnTun{wintun: wintun, plan: plan, finished: make(chan struct{})}
	for _, address := range plan.Addresses {
		if netip.MustParsePrefix(address).Addr().Is4() {
			tun.v4 = true
		} else {
			tun.v6 = true
		}
	}
	s.tun.Store(tun)
	go s.pump(tun)
	return true
}

// pump drops a family the server gave no address in, as WireGuard's allowed IPs do.
func (s *ovpnWin) pump(tun *ovpnTun) {
	defer close(tun.finished)
	for {
		packet, release, err := tun.wintun.ReadPacket()
		if err != nil {
			if s.tun.Load() == tun && !s.stale() {
				go s.breaks(err)
			}
			return
		}
		if len(packet) > 0 && (packet[0]>>4 == 4 && tun.v4 || packet[0]>>4 == 6 && tun.v6) {
			statistic.DefaultManager.PushUploaded(false, int64(len(packet)))
			s.lib.packet(packet)
		}
		release()
	}
}

func (s *ovpnWin) breaks(err error) {
	log.Warnln("[OpenVPN] wintun read: %v", err)
	s.lastError.Store("wintun: " + err.Error())
	s.broken.Store(true)
	s.stopping.Store(true)
	s.halt()
}

func (s *ovpnWin) write(packet []byte) bool {
	tun := s.tun.Load()
	if tun == nil || s.stale() {
		return false
	}
	if _, err := tun.wintun.Write(packet); err != nil {
		return false
	}
	statistic.DefaultManager.PushDownloaded(false, int64(len(packet)))
	return true
}

func (s *ovpnWin) closeTun() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closeTunLocked()
}

func (s *ovpnWin) closeTunLocked() {
	if tun := s.tun.Swap(nil); tun != nil {
		_ = tun.wintun.Close()
		<-tun.finished
	}
}
