package main

import (
	"os"
	"strings"
	"testing"
)

// A stack buffer would move as the engine's callbacks grow the goroutine's stack, and run would answer into the old one.
func TestTheEnginesAnswerBufferIsPinnedOffTheGoroutineStack(t *testing.T) {
	source, err := os.ReadFile("shikoo_ovpn_windows.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	call := strings.Index(text, "syscall.SyscallN(run,")
	for _, want := range []string{"var pin runtime.Pinner", "defer pin.Unpin()", "pin.Pin(&out[0])"} {
		if at := strings.Index(text, want); at < 0 || call < 0 || at > call {
			t.Errorf("%q is not before the call that hands the buffer to the engine", want)
		}
	}
}
