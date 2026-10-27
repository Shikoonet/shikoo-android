//go:build windows

package main

import (
	"encoding/json"
	"testing"
	"time"
)

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

// The engine's start holds configMu for seconds (the endpoint's DNS, wintun, routes); the app waits 2 s at most.
func TestTheCoreSaysWhatTheEngineCarriesWhileTheTunnelIsBeingBuilt(t *testing.T) {
	ownerRunning.Store(&wgOwner{server: "wg"})
	t.Cleanup(func() { ownerRunning.Store(nil) })
	configMu.Lock()
	defer configMu.Unlock()
	start := time.Now()
	frame := captureSingleFrame(t, func() {
		methodHandlers[shikooOwnerMethod](&MethodCall{ID: "1", Method: shikooOwnerMethod}, MethodResponse{ID: "1"})
	})
	if took := time.Since(start); took > 200*time.Millisecond {
		t.Errorf("the answer took %v", took)
	}
	var answer struct{ Result ShikooOwner }
	if err := json.Unmarshal(frame, &answer); err != nil || answer.Result != (ShikooOwner{Core: "wireguard", Server: "wg"}) {
		t.Errorf("answer %s (%v)", frame, err)
	}
}

func TestASecondDeathWithinAMinuteLeavesTheServerToMihomoForOneConnection(t *testing.T) {
	var hold ownerHold
	at := time.Now()
	hold.died("k", at)
	if hold.key != "" {
		t.Fatal("one death held the engine off")
	}
	hold.died("k", at.Add(2*time.Minute))
	if hold.key != "" {
		t.Fatal("deaths two minutes apart held the engine off")
	}
	hold.died("k", at.Add(2*time.Minute+30*time.Second))
	if hold.key != "k" {
		t.Fatal("a second death within a minute did not hold the engine off")
	}
	hold.stopped()
	if hold.key != "k" {
		t.Fatal("the app's own reconnect after the death lifted the hold")
	}
	hold.stopped()
	if hold.key != "" {
		t.Fatal("the user's next disconnect did not lift the hold")
	}
}
