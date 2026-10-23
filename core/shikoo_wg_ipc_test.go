//go:build !cgo

package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestTheRegistryHandsTheCarriedServersPingToTheEngine(t *testing.T) {
	startTestOwner(t)
	registerOwner("wireguard-test")
	t.Cleanup(func() { delete(shikooOwners, "wireguard-test") })
	params, _ := json.Marshal(TestDelayParams{ProxyName: "wg", Timeout: 3000})
	fake := &fakeConn{}
	previous := swapConn(fake)
	defer swapConn(previous)
	methodHandlers[asyncTestDelayMethod](&MethodCall{ID: "1", Method: asyncTestDelayMethod, Arguments: params}, MethodResponse{ID: "1"})
	type reply struct {
		ID     string
		Result Delay
	}
	var answer reply
	for deadline := time.Now().Add(5 * time.Second); answer.ID != "1"; time.Sleep(20 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("no answer")
		}
		for _, frame := range fake.frames(t) {
			var r reply
			if json.Unmarshal(frame, &r) == nil && r.ID == "1" {
				answer = r
			}
		}
	}
	if answer.Result.Value <= 0 || answer.Result.Name != "wg" {
		t.Fatalf("answer %+v, want a delay for wg", answer.Result)
	}
}
