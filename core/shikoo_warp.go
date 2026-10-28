package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"maps"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/dialer"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/transport/socks5"
)

// The WARP bridge (docs/warp-bridge.md): aether, in a process of its own, behind the one socks5 proxy Dart marks
// `shikoo-core: warp`. Its own sockets leave through serveWarpUpstream, which dials with mihomo's dialer, so
// Android's protect and Windows' interface binding keep them out of our tunnel.
const warpCore = "warp"

// warpEndpoint is the file Dart reads to send its own requests through the bridge; the process's lifetime.
const warpEndpoint = "endpoint.json"

type warpProcess struct {
	dir            string
	socks, http    string
	user, pass     string
	upstream       net.Listener
	ports          []int
	release        func()
	upUser, upPass string
	refs           int
	stop           chan struct{}
	mu             sync.Mutex
	cmd            *exec.Cmd
}

var (
	warpMu  sync.Mutex
	warpNow *warpProcess

	// Test seams.
	warpCommand = func() *exec.Cmd { return exec.Command(warpBinary()) }
	warpRestart = 5 * time.Second
)

func init() {
	registerShikooCore(warpCore, startWarp)
}

// startWarp keeps one process across config applies: each generation holds a reference, and the last one let go stops it.
func startWarp(proxies []map[string]any) ([]map[string]any, func(), error) {
	warpMu.Lock()
	defer warpMu.Unlock()
	if warpNow == nil {
		run, err := launchWarp()
		if err != nil {
			return nil, nil, err
		}
		warpNow = run
	}
	run := warpNow
	run.refs++
	out := make([]map[string]any, len(proxies))
	for i, proxy := range proxies {
		out[i] = maps.Clone(proxy)
		maps.Copy(out[i], map[string]any{
			"type": "socks5", "server": "127.0.0.1", "port": portOf(run.socks),
			"username": run.user, "password": run.pass, "udp": true,
		})
	}
	var once sync.Once
	return out, func() {
		once.Do(func() {
			warpMu.Lock()
			defer warpMu.Unlock()
			if run.refs--; run.refs == 0 {
				run.close()
				if warpNow == run {
					warpNow = nil
				}
			}
		})
	}, nil
}

func launchWarp() (_ *warpProcess, err error) {
	dir := filepath.Join(C.Path.HomeDir(), "warp")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	// A killed app leaves its last endpoint behind.
	os.Remove(filepath.Join(dir, warpEndpoint))
	defer func() {
		if err != nil {
			writeWarpFile(dir, map[string]string{"error": err.Error()})
		}
	}()
	if _, err := os.Stat(warpCommand().Path); err != nil {
		return nil, err
	}
	up, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	run := &warpProcess{
		dir: dir, upstream: up, stop: make(chan struct{}),
		user: secret(), pass: secret(), upUser: secret(), upPass: secret(),
	}
	// shortcut: aether's socks UDP relay takes the first datagram from 127.0.0.1 as its client, so a local app that finds
	// the relay port first can take over mihomo's UDP through the bridge. Upgrade if aether pins the ASSOCIATE client.
	if run.ports, run.release, err = loopbackPorts(2); err != nil {
		up.Close()
		return nil, err
	}
	run.socks = net.JoinHostPort("127.0.0.1", strconv.Itoa(run.ports[0]))
	run.http = net.JoinHostPort("127.0.0.1", strconv.Itoa(run.ports[1]))
	go serveWarpUpstream(up, auth.NewAuthenticator([]auth.AuthUser{{User: run.upUser, Pass: run.upPass}}))
	go run.supervise()
	return run, nil
}

func writeWarpFile(dir string, fields map[string]string) error {
	data, err := json.Marshal(fields)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, warpEndpoint), data, 0o600)
}

func (w *warpProcess) env() []string {
	env := []string{
		"AETHER_SOCKS=" + w.socks,
		"AETHER_HTTP_PROXY=" + w.http,
		"AETHER_PROXY_AUTH=" + w.user + ":" + w.pass,
		"AETHER_UPSTREAM=socks5h://" + w.upUser + ":" + w.upPass + "@" + w.upstream.Addr().String(),
		"AETHER_PROTOCOL=masque",
		"AETHER_MASQUE_HTTP2=1",
		"AETHER_TLS_VERIFY=1",
		"AETHER_SCAN=balanced",
		"AETHER_IP=v4",
		"AETHER_QUICK_RECONNECT=1",
		"AETHER_LOG_LEVEL=warn",
	}
	for _, kv := range os.Environ() {
		name, _, _ := strings.Cut(kv, "=")
		if upper := strings.ToUpper(name); !strings.HasPrefix(upper, "AETHER_") && !strings.HasSuffix(upper, "_PROXY") {
			env = append(env, kv)
		}
	}
	return env
}

func (w *warpProcess) supervise() {
	delay := warpRestart
	for {
		started := time.Now()
		err := w.runOnce()
		select {
		case <-w.stop:
			return
		default:
		}
		if time.Since(started) > time.Minute {
			delay = warpRestart
		}
		log.Warnln("[SHIKOO] warp bridge ended (%v); again in %s", err, delay)
		select {
		case <-w.stop:
			return
		case <-time.After(delay):
		}
		delay = min(2*delay, time.Minute)
	}
}

func (w *warpProcess) runOnce() error {
	cmd := warpCommand()
	cmd.Dir, cmd.Env = w.dir, w.env()
	read, write, err := os.Pipe()
	if err != nil {
		return err
	}
	cmd.Stdout, cmd.Stderr = write, write
	w.mu.Lock()
	select {
	case <-w.stop:
		w.mu.Unlock()
		read.Close()
		write.Close()
		return nil
	default:
	}
	w.release()
	err = warpStart(cmd)
	if err == nil {
		w.cmd = cmd
		if err := writeWarpFile(w.dir, map[string]string{"http": w.http, "auth": w.user + ":" + w.pass}); err != nil {
			log.Warnln("[SHIKOO] warp endpoint: %v", err)
		}
	}
	w.mu.Unlock()
	write.Close()
	if err != nil {
		read.Close()
		return err
	}
	go func() {
		defer read.Close()
		scanner := bufio.NewScanner(read)
		for scanner.Scan() {
			log.Warnln("[SHIKOO] warp: %s", redactWarp(scanner.Text()))
		}
	}()
	err = cmd.Wait()
	os.Remove(filepath.Join(w.dir, warpEndpoint))
	// Whatever it started dies with it, and lets go of the log pipe.
	warpKill(cmd)
	return err
}

func (w *warpProcess) close() {
	close(w.stop)
	w.upstream.Close()
	w.release()
	forgetPorts(w.ports...)
	w.mu.Lock()
	defer w.mu.Unlock()
	os.Remove(filepath.Join(w.dir, warpEndpoint))
	if w.cmd != nil {
		warpKill(w.cmd)
	}
}

// The device's WARP identity and its keys stay out of the log, and so out of the report the app sends.
var warpSecrets = regexp.MustCompile(`[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[A-Za-z0-9+/_-]{32,}={0,2}`)

func redactWarp(line string) string {
	return warpSecrets.ReplaceAllString(line, "<hidden>")
}

// serveWarpUpstream: aether's way out, socks5 CONNECT with a password; the scan, the WARP API and MASQUE over
// HTTP/2 are all TCP.
func serveWarpUpstream(listener net.Listener, authenticator auth.Authenticator) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		go func() {
			defer conn.Close()
			conn.SetDeadline(time.Now().Add(10 * time.Second))
			target, command, _, err := socks5.ServerHandshake(conn, authenticator)
			if err != nil || command != socks5.CmdConnect {
				return
			}
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			remote, err := dialer.DialContext(ctx, "tcp", target.String())
			cancel()
			if err != nil {
				return
			}
			conn.SetDeadline(time.Time{})
			N.Relay(conn, remote)
		}()
	}
}

func warpBinary() string {
	name := "shikoowarp"
	if runtime.GOOS == "windows" {
		name = "ShikooNetWarp.exe"
	}
	if features.Android {
		// A program runs only from the app's native library folder, the one libclash.so was loaded from.
		if dir, err := loadedFrom("libclash.so"); err == nil {
			return filepath.Join(dir, "libshikoowarp.so")
		}
	}
	self, err := os.Executable()
	if err != nil {
		return name
	}
	return filepath.Join(filepath.Dir(self), name)
}

func loadedFrom(library string) (string, error) {
	mapped, err := os.ReadFile("/proc/self/maps")
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(mapped), "\n") {
		if at := strings.Index(line, "/"); at >= 0 && strings.HasSuffix(line, "/"+library) {
			return filepath.Dir(line[at:]), nil
		}
	}
	return "", errors.New(library + " is not loaded")
}

func secret() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func portOf(address string) int {
	_, port, _ := net.SplitHostPort(address)
	n, _ := strconv.Atoi(port)
	return n
}
