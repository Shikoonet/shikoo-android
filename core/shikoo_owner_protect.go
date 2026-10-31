package main

import (
	"errors"
	"sync"

	wgconn "golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/tun"
)

var (
	errOwnerUnprotected    = errors.New("blocked: no VpnService.protect for a socket an owner core's VPN would take")
	errOwnerProtectRefused = errors.New("blocked: VpnService.protect refused a socket beside an owner core's VPN")
)

// ownerProtector: an owner core's VPN holds this app too (VpnOptions.appRules), so while no mihomo TUN is up its own
// sockets need Android's VpnService.protect, which lib.go's setOwnerProtector hands in.
type ownerProtector struct {
	mu      sync.RWMutex
	protect func(fd int) bool
	release func()
}

var ownerProtect ownerProtector

func (o *ownerProtector) set(protect func(fd int) bool, release func()) {
	o.mu.Lock()
	last := o.release
	o.protect, o.release = protect, release
	o.mu.Unlock()
	if last != nil {
		last()
	}
}

func (o *ownerProtector) holds() bool {
	o.mu.RLock()
	defer o.mu.RUnlock()
	return o.protect != nil
}

// socket protects fd while an owner core's VPN holds the app; with none, only a socket that must be kept out fails.
func (o *ownerProtector) socket(fd int, mustProtect bool) error {
	o.mu.RLock()
	defer o.mu.RUnlock()
	switch {
	case o.protect == nil && mustProtect:
		return errOwnerUnprotected
	case o.protect == nil:
		return nil
	case !o.protect(fd):
		return errOwnerProtectRefused
	}
	return nil
}

type peekingBind interface {
	wgconn.Bind
	PeekLookAtSocketFd4() (int, error)
	PeekLookAtSocketFd6() (int, error)
}

type protectedBind struct{ peekingBind }

func (b protectedBind) Open(port uint16) ([]wgconn.ReceiveFunc, uint16, error) {
	fns, actual, err := b.peekingBind.Open(port)
	if err != nil {
		return fns, actual, err
	}
	for _, peek := range []func() (int, error){b.PeekLookAtSocketFd4, b.PeekLookAtSocketFd6} {
		fd, err := peek()
		if err != nil {
			continue
		}
		if err := ownerProtect.socket(fd, true); err != nil {
			_ = b.peekingBind.Close()
			return nil, 0, err
		}
	}
	return fns, actual, nil
}

func startProtectedOwner(t tun.Device, bind peekingBind) error {
	return startOwner(t, protectedBind{bind})
}

// As startTUN does: a switch's stop can reach Go after its start's listeners, which left the mixed port shut.
func restartListenersIfStopped() {
	if !isRunning.Load() {
		handleStartListener()
	}
}
