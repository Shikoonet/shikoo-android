package main

import (
	"os/exec"
	"runtime"
	"sync"
	"syscall"
	"time"
)

// Pdeathsig follows the starting thread, and Android's calling threads come and go: start on one that never ends.
var warpSpawner = sync.OnceValue(func() chan func() {
	jobs := make(chan func())
	go func() {
		runtime.LockOSThread()
		for job := range jobs {
			job()
		}
	}()
	return jobs
})

func warpStart(cmd *exec.Cmd) error {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true, Pdeathsig: syscall.SIGKILL}
	done := make(chan error)
	warpSpawner() <- func() { done <- cmd.Start() }
	return <-done
}

func warpKill(cmd *exec.Cmd) {
	group := -cmd.Process.Pid
	syscall.Kill(group, syscall.SIGTERM)
	time.AfterFunc(2*time.Second, func() { syscall.Kill(group, syscall.SIGKILL) })
}
