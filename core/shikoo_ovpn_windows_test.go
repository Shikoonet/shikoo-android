package main

import (
	"bytes"
	"errors"
	"net"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
	singtun "github.com/metacubex/sing-tun"
	"golang.org/x/sys/windows"
)

const pushedSpec = `{"addresses":["10.89.0.2/24"],"dns":["1.1.1.1"],"mtu":1500}`

func tunClosed(f *fakeWintun) bool {
	select {
	case <-f.closed:
		return true
	default:
		return false
	}
}

// fakeEngine stands in for the DLL: run blocks until a halt it does not ignore, and returns result.
type fakeEngine struct {
	ovpnLib
	mu       sync.Mutex
	halts    int
	ignore   int
	result   string
	profile  string
	packets  [][]byte
	released chan struct{}
	once     sync.Once
	entered  chan struct{}
}

func newFakeEngine() *fakeEngine {
	f := &fakeEngine{released: make(chan struct{}), entered: make(chan struct{}, 4)}
	f.run = func(profile, _, _ string) string {
		f.mu.Lock()
		f.profile = profile
		f.mu.Unlock()
		f.entered <- struct{}{}
		<-f.released
		return f.result
	}
	f.halt = func() {
		f.mu.Lock()
		f.halts++
		stop := f.halts > f.ignore
		f.mu.Unlock()
		if stop {
			f.finish()
		}
	}
	f.packet = func(p []byte) {
		f.mu.Lock()
		f.packets = append(f.packets, bytes.Clone(p))
		f.mu.Unlock()
	}
	return f
}

func (f *fakeEngine) finish() { f.once.Do(func() { close(f.released) }) }

func (f *fakeEngine) haltCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.halts
}

type wintunSeam struct {
	mu    sync.Mutex
	built []singtun.Options
	tuns  []*fakeWintun
}

func (w *wintunSeam) last() *fakeWintun {
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.tuns) == 0 {
		return nil
	}
	return w.tuns[len(w.tuns)-1]
}

func (w *wintunSeam) count() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.tuns)
}

// withEngine puts a fake engine and a fake adapter where the DLL and wintun are, and quickens the stop loop.
func withEngine(t *testing.T) (*fakeEngine, *wintunSeam) {
	t.Helper()
	engine, seam := newFakeEngine(), &wintunSeam{}
	load, build, step := ovpnLoad, wintunNew, ovpnStopStep
	ovpnLoad = func() (*ovpnLib, error) { return &engine.ovpnLib, nil }
	wintunNew = func(options singtun.Options) (singtun.WinTun, error) {
		tun := newFakeWintun()
		seam.mu.Lock()
		seam.built, seam.tuns = append(seam.built, options), append(seam.tuns, tun)
		seam.mu.Unlock()
		return tun, nil
	}
	ovpnStopStep = 5 * time.Millisecond
	t.Cleanup(func() {
		engine.finish()
		ovpnWinStop()
		ovpnLoad, wintunNew, ovpnStopStep = load, build, step
		ovpnEnded.Store(nil)
		ovpnNow.Store(nil)
		ovpnPrepared.Store(nil)
	})
	return engine, seam
}

func physicalIs(index uint32) func() uint32 { return func() uint32 { return index } }

func startFake(t *testing.T, engine *fakeEngine, set map[string]any) *ovpnWin {
	t.Helper()
	if err := ovpnWinStart("ShikooNet", ovpnMapping(set), false, physicalIs(1)); err != nil {
		t.Fatal(err)
	}
	s := ovpnLive.Load()
	select {
	case <-engine.entered:
	case <-time.After(2 * time.Second):
		t.Fatal("the engine never ran")
	}
	return s
}

func waitFor(t *testing.T, what string, ok func() bool, within ...time.Duration) {
	t.Helper()
	limit := 3 * time.Second
	if len(within) > 0 {
		limit = within[0]
	}
	for deadline := time.Now().Add(limit); time.Now().Before(deadline); time.Sleep(5 * time.Millisecond) {
		if ok() {
			return
		}
	}
	t.Fatalf("never: %s", what)
}

func echoV4(src, dst [4]byte) []byte {
	p := make([]byte, 28)
	p[0], p[8], p[9], p[3] = 0x45, 64, 1, 28
	copy(p[12:], src[:])
	copy(p[16:], dst[:])
	return p
}

func TestTheEngineIsToldThePinnedAddressAndTheServerIsCarriedFromTheStart(t *testing.T) {
	engine, _ := withEngine(t)
	s := startFake(t, engine, map[string]any{"server": "localhost"})
	if engine.profile == "" || !bytes.Contains([]byte(engine.profile), []byte("remote 127.0.0.1 1194\n")) {
		t.Errorf("profile %q: the name must be looked up before the engine runs", engine.profile)
	}
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", Server: "ov", State: stateConnecting}) {
		t.Errorf("while connecting the core says %+v", got)
	}
	s.event("CONNECTED", "an account", false)
	if got := shikooOwnerNow(); got.State != stateUp {
		t.Errorf("once connected the core says %+v", got)
	}
	s.event("RECONNECTING", "", false)
	if got := shikooOwnerNow(); got.State != stateConnecting || got.Server != "ov" {
		t.Errorf("reconnecting the core says %+v: the server stays carried, not up", got)
	}
}

func TestANameThatDoesNotResolveFailsTheSessionWithoutRunningTheEngine(t *testing.T) {
	engine, _ := withEngine(t)
	if err := ovpnWinStart("ShikooNet", ovpnMapping(map[string]any{"server": "no-such-host.invalid"}), false, physicalIs(1)); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "the failure", func() bool { return ovpnEnded.Load() != nil }, 12*time.Second)
	if got := ovpnEnded.Load(); got.state != stateFailed {
		t.Errorf("outcome %+v", got)
	}
	if len(engine.entered) != 0 {
		t.Error("the engine ran with a name nothing resolved")
	}
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", State: stateFailed}) {
		t.Errorf("the core says %+v", got)
	}
}

func TestAnEngineMissingFromTheInstallFailsTheStartAndIsAskedAgainNextTime(t *testing.T) {
	withEngine(t)
	ovpnLoad = loadOvpn
	was := ovpnDLLPath
	ovpnDLLPath = func() string { return `C:\no\such\ShikooNetOvpn3.dll` }
	t.Cleanup(func() { ovpnDLLPath = was })
	if err := ovpnWinStart("ShikooNet", ovpnMapping(nil), false, physicalIs(1)); err == nil {
		t.Fatal("a missing engine started")
	}
	if ovpnFound != nil {
		t.Error("a failed load was kept")
	}
}

func TestARefusedLoginEndsRunWithNoErrorOfItsOwnAndTheEventSaysWhy(t *testing.T) {
	engine, seam := withEngine(t)
	s := startFake(t, engine, nil)
	s.event("AUTH_FAILED", "", true)
	engine.finish()
	waitFor(t, "the end", func() bool { return ovpnLive.Load() == nil })
	if got := ovpnEnded.Load(); got == nil || got.state != stateRefused {
		t.Fatalf("outcome %+v: AUTH_FAILED must read as a refused login", got)
	}
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", State: stateRefused}) {
		t.Errorf("the core says %+v", got)
	}
	if seam.count() != 0 {
		t.Error("a refused login built a tunnel")
	}
}

func TestAnEngineThatEndsWithAReasonFailsTheSessionWithoutRefusing(t *testing.T) {
	engine, _ := withEngine(t)
	engine.result = "refused: bad profile"
	startFake(t, engine, nil)
	engine.finish()
	waitFor(t, "the end", func() bool { return ovpnLive.Load() == nil })
	if got := ovpnEnded.Load(); got == nil || got.state != stateFailed || got.reason != "refused: bad profile" {
		t.Errorf("outcome %+v", got)
	}
}

func TestAStopByTheAppIsNoFailureAndClosesTheAdapter(t *testing.T) {
	engine, seam := withEngine(t)
	s := startFake(t, engine, nil)
	if !s.establish(pushedSpec) {
		t.Fatal("establish refused")
	}
	s.event("CONNECTED", "", false)
	tun := seam.last()
	if !ovpnWinStop() {
		t.Fatal("did not stop")
	}
	if !tunClosed(tun) || ovpnEnded.Load() != nil || shikooOwnerNow() != (ShikooOwner{}) {
		t.Errorf("adapter closed %v, outcome %+v, core says %+v", tunClosed(tun), ovpnEnded.Load(), shikooOwnerNow())
	}
	s.event("DISCONNECTED", "", false)
}

func TestHaltIsRepeatedUntilTheEngineTakesIt(t *testing.T) {
	engine, _ := withEngine(t)
	engine.ignore = 3
	startFake(t, engine, nil)
	if !ovpnWinStop() {
		t.Fatal("never stopped")
	}
	if got := engine.haltCount(); got != 4 {
		t.Errorf("%d halts, want 4: the first three were lost", got)
	}
}

func TestAnEngineThatNeverStopsIsReportedAndNoNewSessionStartsOnTopOfIt(t *testing.T) {
	engine, _ := withEngine(t)
	engine.ignore = 1 << 30
	tries := ovpnStopTries
	ovpnStopTries = 4
	t.Cleanup(func() { ovpnStopTries = tries })
	startFake(t, engine, nil)
	if ovpnWinStop() {
		t.Fatal("reported a stop that did not happen")
	}
	if err := ovpnWinStart("ShikooNet", ovpnMapping(nil), false, physicalIs(1)); err == nil {
		t.Error("a second session started on top of one the engine still ran")
	}
	engine.ignore = 0
}

func TestTheNewestAskWinsAndTheOldSessionIsRefused(t *testing.T) {
	engine, seam := withEngine(t)
	old := startFake(t, engine, nil)
	if !old.establish(pushedSpec) {
		t.Fatal("the first session was refused its tunnel")
	}
	again := newFakeEngine()
	ovpnLoad = func() (*ovpnLib, error) { return &again.ovpnLib, nil }
	current := startFake(t, again, map[string]any{"name": "ov2"})

	if old == current || engine.haltCount() == 0 {
		t.Fatalf("halts of the first engine %d: the newest ask must stop the last", engine.haltCount())
	}
	if old.establish(pushedSpec) || old.protect(0, false) || old.write(echoV4([4]byte{10, 89, 0, 2}, [4]byte{10, 89, 0, 1})) {
		t.Error("a session that is no longer the latest was served")
	}
	old.event("CONNECTED", "", false)
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", Server: "ov2", State: stateConnecting}) {
		t.Errorf("the old session's word changed the core's answer to %+v", got)
	}
	if first := seam.tuns[0]; !tunClosed(first) {
		t.Error("the first session's adapter outlived it")
	}
	current.event("CONNECTED", "", false)
	if got := shikooOwnerNow(); got.Server != "ov2" || got.State != stateUp {
		t.Errorf("the core says %+v", got)
	}
}

// While the last engine still takes halts, the newer ask is already the latest: what the old one says is not heard.
func TestASessionThatIsNotTheLatestIsRefusedWhileItIsStillStopping(t *testing.T) {
	engine, _ := withEngine(t)
	engine.ignore = 1 << 30
	old := startFake(t, engine, nil)
	old.report(false)
	ovpnLatest.Store(int64(old.id) + 1)
	t.Cleanup(func() { engine.ignore = 0 })

	if old.establish(pushedSpec) || old.protect(0, false) || old.write(echoV4([4]byte{10, 89, 0, 2}, [4]byte{10, 89, 0, 1})) {
		t.Error("a session that is no longer the latest was served before it stopped")
	}
	old.event("CONNECTED", "", false)
	if got := shikooOwnerNow(); got.State != stateConnecting {
		t.Errorf("the core says %+v: a session that is not the latest cannot say it is up", got)
	}
}

func TestNoConnectionInTheLimitFailsTheSessionAndAConnectedOneIsLeftAlone(t *testing.T) {
	limit := ovpnConnectLimit
	ovpnConnectLimit = 80 * time.Millisecond
	t.Cleanup(func() { ovpnConnectLimit = limit })

	engine, _ := withEngine(t)
	startFake(t, engine, nil)
	waitFor(t, "the limit", func() bool { return ovpnLive.Load() == nil })
	if got := ovpnEnded.Load(); got == nil || got.state != stateFailed || got.reason != "no connection in 80ms" {
		t.Errorf("outcome %+v", got)
	}
	if engine.haltCount() == 0 {
		t.Error("the engine was left running past the limit")
	}

	engine2 := newFakeEngine()
	ovpnLoad = func() (*ovpnLib, error) { return &engine2.ovpnLib, nil }
	s := startFake(t, engine2, nil)
	s.event("CONNECTED", "", false)
	time.Sleep(3 * ovpnConnectLimit)
	if ovpnLive.Load() != s || engine2.haltCount() != 0 {
		t.Error("a connected session was cut at the limit")
	}
}

func TestAReconnectWithTheSamePlanKeepsTheAdapterAndANewPlanBuildsAnother(t *testing.T) {
	engine, seam := withEngine(t)
	s := startFake(t, engine, nil)
	if !s.establish(pushedSpec) || !s.establish(pushedSpec) {
		t.Fatal("establish refused")
	}
	if seam.count() != 1 {
		t.Fatalf("%d adapters for one plan", seam.count())
	}
	first := seam.last()
	options := seam.built[0]
	if len(options.Inet4Address) != 1 || options.Inet4Address[0].String() != "10.89.0.2/24" ||
		len(options.DNSServers) != 1 || options.DNSServers[0].String() != "1.1.1.1" ||
		len(options.Inet4RouteAddress) != 1 || options.Inet4RouteAddress[0].String() != "0.0.0.0/0" {
		t.Errorf("adapter options %+v", options)
	}
	if !s.establish(`{"addresses":["10.89.0.9/24"],"dns":["1.1.1.1"],"mtu":1500}`) {
		t.Fatal("establish refused")
	}
	if seam.count() != 2 || !tunClosed(first) || tunClosed(seam.last()) {
		t.Errorf("%d adapters, first closed %v: a new plan replaces the adapter", seam.count(), tunClosed(first))
	}
	if s.establish(`{"addresses":["nonsense"]}`) || s.establish(`not json`) {
		t.Error("an unreadable spec was served")
	}
}

func TestThePumpDropsAFamilyTheServerGaveNoAddressInAndCountsWhatItCarries(t *testing.T) {
	engine, seam := withEngine(t)
	s := startFake(t, engine, nil)
	if !s.establish(pushedSpec) {
		t.Fatal("establish refused")
	}
	tun := seam.last()
	up0, down0 := statistic.DefaultManager.Total()
	v4 := echoV4([4]byte{10, 89, 0, 2}, [4]byte{10, 89, 0, 1})
	v6 := append([]byte{0x60}, make([]byte, 39)...)
	tun.outbound <- v6
	tun.outbound <- []byte{}
	tun.outbound <- v4
	waitFor(t, "the IPv4 packet", func() bool { engine.mu.Lock(); defer engine.mu.Unlock(); return len(engine.packets) == 1 })
	time.Sleep(20 * time.Millisecond)
	if len(engine.packets) != 1 || !bytes.Equal(engine.packets[0], v4) {
		t.Fatalf("the engine got %d packets: only the IPv4 one belongs", len(engine.packets))
	}
	if !s.write(v4) {
		t.Fatal("a packet from the engine was refused")
	}
	select {
	case got := <-tun.inbound:
		if !bytes.Equal(got, v4) {
			t.Fatalf("the adapter got %x", got)
		}
	default:
		t.Fatal("a packet from the engine did not reach the adapter")
	}
	up, down := statistic.DefaultManager.Total()
	if up-up0 != int64(len(v4)) || down-down0 != int64(len(v4)) {
		t.Errorf("counted %d up and %d down, want %d each", up-up0, down-down0, len(v4))
	}
}

func TestNothingIsWrittenWhereThereIsNoTunnelToCarryIt(t *testing.T) {
	engine, _ := withEngine(t)
	s := startFake(t, engine, nil)
	if s.write(echoV4([4]byte{10, 89, 0, 2}, [4]byte{10, 89, 0, 1})) {
		t.Error("a packet was taken before the first establish")
	}
	if !s.establish(pushedSpec) {
		t.Fatal("establish refused")
	}
	s.closeTun()
	if s.write(echoV4([4]byte{10, 89, 0, 2}, [4]byte{10, 89, 0, 1})) {
		t.Error("a packet was taken after the adapter went")
	}
}

func TestProtectBindsTheEnginesSocketToThePhysicalInterfaceOrRefusesIt(t *testing.T) {
	loopback := loopbackIndex(t)
	engine, _ := withEngine(t)
	s := startFake(t, engine, nil)

	for _, ipv6 := range []bool{false, true} {
		family, level := windows.AF_INET, windows.IPPROTO_IP
		if ipv6 {
			family, level = windows.AF_INET6, windows.IPPROTO_IPV6
		}
		socket, err := windows.Socket(family, windows.SOCK_STREAM, windows.IPPROTO_TCP)
		if err != nil {
			t.Fatal(err)
		}
		defer windows.Closesocket(socket)
		s.physical = physicalIs(0)
		if s.protect(socket, ipv6) {
			t.Errorf("ipv6=%v: a socket was protected with no physical interface", ipv6)
		}
		s.physical = physicalIs(loopback)
		if !s.protect(socket, ipv6) {
			t.Fatalf("ipv6=%v: protect failed", ipv6)
		}
		got, err := windows.GetsockoptInt(socket, level, 31)
		// The option takes an IPv4 index in network byte order and reads back as the index itself.
		want := int(loopback)
		if err != nil || got != want {
			t.Errorf("ipv6=%v: the unicast interface reads %d (%v), want %d", ipv6, got, err, want)
		}
	}
}

func loopbackIndex(t *testing.T) uint32 {
	t.Helper()
	all, err := net.Interfaces()
	if err != nil {
		t.Fatal(err)
	}
	for _, one := range all {
		if one.Flags&net.FlagLoopback != 0 {
			return uint32(one.Index)
		}
	}
	t.Skip("no loopback interface")
	return 0
}

func TestClosingTheOwnerTunnelStopsTheOpenvpnSession(t *testing.T) {
	engine, seam := withEngine(t)
	s := startFake(t, engine, nil)
	s.establish(pushedSpec)
	(&ownerTunnel{}).close()
	if ovpnLive.Load() != nil || !tunClosed(seam.last()) {
		t.Error("the session outlived its owner tunnel")
	}
}

func TestBothOfficialEnginesAreRegisteredOnWindowsWithTheirOwnPingAndWord(t *testing.T) {
	for _, core := range []string{"wireguard", "openvpn"} {
		if owner, ok := shikooOwners[core]; !ok || owner.ping == nil {
			t.Errorf("%s is not registered with a ping", core)
		}
	}
	if shikooOwnerIdlePings["openvpn"] == nil || shikooOwnerStates["openvpn"] == nil {
		t.Error("OpenVPN has no idle ping or session word on Windows")
	}
}

func refusedOnce(t *testing.T, engine *fakeEngine) {
	t.Helper()
	s := startFake(t, engine, nil)
	s.event("AUTH_FAILED", "", true)
	engine.finish()
	waitFor(t, "the end", func() bool { return ovpnLive.Load() == nil })
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", State: stateRefused}) {
		t.Fatalf("the core says %+v after a refused session", got)
	}
}

func TestANewStartClearsWhatTheLastSessionLeft(t *testing.T) {
	engine, _ := withEngine(t)
	refusedOnce(t, engine)
	again := newFakeEngine()
	ovpnLoad = func() (*ovpnLib, error) { return &again.ovpnLib, nil }
	startFake(t, again, nil)
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", Server: "ov", State: stateConnecting}) {
		t.Errorf("a new start hears the last one's failure: %+v", got)
	}
	ovpnWinStop()
	if got := shikooOwnerNow(); got != (ShikooOwner{}) {
		t.Errorf("the new session's own stop brings the last one's failure back: %+v", got)
	}
}

func TestTheAppsStopClearsWhatTheLastSessionLeft(t *testing.T) {
	engine, _ := withEngine(t)
	refusedOnce(t, engine)
	stopOwnerTun()
	if got := shikooOwnerNow(); got != (ShikooOwner{}) {
		t.Errorf("the core says %+v after the app stopped: a later connect of another kind would read it", got)
	}
}

func TestASupersededSessionThatTimesOutLeavesNoFailureBehind(t *testing.T) {
	limit := ovpnConnectLimit
	ovpnConnectLimit = 150 * time.Millisecond
	t.Cleanup(func() { ovpnConnectLimit = limit })
	engine, _ := withEngine(t)
	old := startFake(t, engine, nil)
	ovpnLatest.Store(int64(old.id) + 1)
	waitFor(t, "the old session's end", func() bool { return ovpnLive.Load() == nil })
	if got := ovpnEnded.Load(); got != nil {
		t.Errorf("a session that was not the latest left %+v for the newer one to read", got)
	}
}

func TestTheServerIsCarriedAsSoonAsTheStartReturns(t *testing.T) {
	withEngine(t)
	was := runtime.GOMAXPROCS(1)
	t.Cleanup(func() { runtime.GOMAXPROCS(was) })
	if err := ovpnWinStart("ShikooNet", ovpnMapping(nil), false, physicalIs(1)); err != nil {
		t.Fatal(err)
	}
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "openvpn", Server: "ov", State: stateConnecting}) {
		t.Errorf("right after the start returned the core says %+v, which the app's watch reads as a death", got)
	}
}

func TestAStuckEngineIsHaltedOnceAnApplyAndNoSessionStartsOnIt(t *testing.T) {
	engine, _ := withEngine(t)
	engine.ignore = 1 << 30
	tries := ovpnStopTries
	ovpnStopTries = 4
	t.Cleanup(func() { ovpnStopTries, engine.ignore = tries, 0 })
	startFake(t, engine, nil)
	if ovpnWinStop() {
		t.Fatal("reported a stop that did not happen")
	}
	halts := engine.haltCount()
	if err := ovpnWinStart("ShikooNet", ovpnMapping(nil), false, physicalIs(1)); err == nil {
		t.Error("a session started on an engine that would not stop")
	}
	if more := engine.haltCount() - halts; more != 0 {
		t.Errorf("%d more halts: an apply with a stuck engine waits out one halt loop, not a second", more)
	}
}

type brokenWintun struct{ *fakeWintun }

func (brokenWintun) ReadPacket() ([]byte, func(), error) {
	return nil, nil, errors.New("device gone")
}

func TestAnAdapterThatFailsEndsItsSessionAsFailed(t *testing.T) {
	engine, _ := withEngine(t)
	wintunNew = func(singtun.Options) (singtun.WinTun, error) { return brokenWintun{newFakeWintun()}, nil }
	s := startFake(t, engine, nil)
	if !s.establish(pushedSpec) {
		t.Fatal("establish refused")
	}
	waitFor(t, "the end", func() bool { return ovpnLive.Load() == nil })
	if got := ovpnEnded.Load(); got == nil || got.state != stateFailed || !bytes.Contains([]byte(got.reason), []byte("device gone")) {
		t.Errorf("outcome %+v", got)
	}
}

func TestAnAdapterFailureOfAnOldSessionLeavesTheNewOneRunning(t *testing.T) {
	engine, _ := withEngine(t)
	old := startFake(t, engine, nil)
	again := newFakeEngine()
	ovpnLoad = func() (*ovpnLib, error) { return &again.ovpnLib, nil }
	current := startFake(t, again, map[string]any{"name": "ov2"})
	old.breaks(errors.New("device gone"))
	if ovpnLive.Load() != current || again.haltCount() != 0 {
		t.Errorf("the new session was halted by the old one's adapter: live %v, halts %d", ovpnLive.Load() == current, again.haltCount())
	}
}
