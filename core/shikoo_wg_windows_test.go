//go:build windows

package main

import "testing"

func TestWindowsReportsWhatTheOfficialEngineCarries(t *testing.T) {
	owner, ok := shikooOwners["wireguard"]
	if !ok || owner.ping == nil {
		t.Fatal("the official engine is not registered with its own ping")
	}
	if got := owner.carrying(); got != "" {
		t.Errorf("an engine that never started carries %q", got)
	}
	ownerRunning.Store(&wgOwner{server: "wg"})
	t.Cleanup(func() { ownerRunning.Store(nil) })
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "wireguard", Server: "wg"}) {
		t.Errorf("the core reports %+v, want wireguard carrying wg", got)
	}
	if delay := owner.ping(&TestDelayParams{ProxyName: "other"}); delay.Value != -1 {
		t.Errorf("a server the engine does not carry got %d, want -1 at once", delay.Value)
	}
}
