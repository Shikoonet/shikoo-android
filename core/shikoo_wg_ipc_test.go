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
	var frames [][]byte
	for deadline := time.Now().Add(5 * time.Second); len(frames) == 0 && time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		frames = fake.frames(t)
	}
	if len(frames) != 1 {
		t.Fatalf("%d answers", len(frames))
	}
	var answer struct{ Result Delay }
	if err := json.Unmarshal(frames[0], &answer); err != nil || answer.Result.Value <= 0 || answer.Result.Name != "wg" {
		t.Fatalf("answer %s (%v), want a delay for wg", frames[0], err)
	}
}
