//go:build go1.23

package main

import (
	"os"
	"path/filepath"
	"runtime/debug"
)

// Android copies a panic to logcat (tag Go) until the buffer turns over; the file outlives it.
func setCrashOutput(home string) {
	file, err := os.OpenFile(filepath.Join(home, "go-crash.txt"), os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	_ = debug.SetCrashOutput(file, debug.CrashOptions{})
	// The API 25 emulator ran the core with no traceback level: the panic's first line only.
	debug.SetTraceback("single")
}
