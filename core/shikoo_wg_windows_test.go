//go:build windows

package main

import "testing"

func TestWindowsReportsWhatTheOfficialEngineCarries(t *testing.T) {
	carrying, ok := shikooOwners["wireguard"]
	if !ok {
		t.Fatal("the official engine is not registered as an owner")
	}
	if got := carrying(); got != "" {
		t.Errorf("an engine that never started carries %q", got)
	}
	ownerMu.Lock()
	ownerRunning = &wgOwner{server: "wg"}
	ownerMu.Unlock()
	t.Cleanup(func() {
		ownerMu.Lock()
		ownerRunning = nil
		ownerMu.Unlock()
	})
	if got := shikooOwnerNow(); got != (ShikooOwner{Core: "wireguard", Server: "wg"}) {
		t.Errorf("the core reports %+v, want wireguard carrying wg", got)
	}
}
