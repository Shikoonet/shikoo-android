//go:build go1.23

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestSetCrashOutputKeepsAnUnrecoveredPanic(t *testing.T) {
	if home := os.Getenv("SHIKOO_CRASH_HOME"); home != "" {
		setCrashOutput(home)
		go func() { panic("shikoo test panic") }()
		select {}
	}
	home := t.TempDir()
	child := exec.Command(os.Args[0], "-test.run=^TestSetCrashOutputKeepsAnUnrecoveredPanic$")
	// As the API 25 emulator ran the core: no traceback level, so only the panic's first line.
	child.Env = append(os.Environ(), "SHIKOO_CRASH_HOME="+home, "GOTRACEBACK=none")
	if err := child.Run(); err == nil {
		t.Fatal("the child survived its panic")
	}
	out, err := os.ReadFile(filepath.Join(home, "go-crash.txt"))
	if err != nil || !strings.Contains(string(out), "panic: shikoo test panic") ||
		!strings.Contains(string(out), "shikoo_crash_test.go:") {
		t.Fatalf("go-crash.txt = %q, %v", out, err)
	}
}
