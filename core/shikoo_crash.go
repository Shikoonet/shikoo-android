//go:build go1.23

package main

import (
	"os"
	"path/filepath"
	"runtime/debug"
)

// Android shows no fd 2, so an unrecovered panic is kept for Shikoo's report (SHIKOO_PATCHES.md row 20).
func setCrashOutput(home string) {
	file, err := os.OpenFile(filepath.Join(home, "go-crash.txt"), os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	_ = debug.SetCrashOutput(file, debug.CrashOptions{})
}
