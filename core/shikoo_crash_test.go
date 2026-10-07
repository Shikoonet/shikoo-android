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
	child.Env = append(os.Environ(), "SHIKOO_CRASH_HOME="+home)
	if err := child.Run(); err == nil {
		t.Fatal("the child survived its panic")
	}
	out, err := os.ReadFile(filepath.Join(home, "go-crash.txt"))
	if err != nil || !strings.Contains(string(out), "panic: shikoo test panic") {
		t.Fatalf("go-crash.txt = %q, %v", out, err)
	}
}
