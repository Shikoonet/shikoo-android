//go:build !windows

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/socks5"
	"github.com/metacubex/mihomo/tunnel"
)

// TestWarpFakeAether is the bridge's stand-in when SHIKOO_WARP_FAKE is set: it notes its pid and settings, starts a
// child of its own, and stays up ("run") or ends ("end").
func TestWarpFakeAether(t *testing.T) {
	mode := os.Getenv("SHIKOO_WARP_FAKE")
	if mode == "" {
		t.Skip("the bridge's stand-in")
	}
	if mode == "child" {
		time.Sleep(time.Minute)
		return
	}
	if mode == "socks" {
		fakeBridgeServes(t)
		return
	}
	child := exec.Command(os.Args[0], "-test.run=^TestWarpFakeAether$")
	child.Env = append(os.Environ(), "SHIKOO_WARP_FAKE=child")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	seen := map[string]string{"pid": strconv.Itoa(os.Getpid()), "child": strconv.Itoa(child.Process.Pid)}
	for _, kv := range os.Environ() {
		if name, value, _ := strings.Cut(kv, "="); strings.HasPrefix(name, "AETHER_") || strings.HasSuffix(name, "_PROXY") {
			seen[name] = value
		}
	}
	data, _ := json.Marshal(seen)
	f, _ := os.OpenFile("runs.jsonl", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	f.Write(append(data, '\n'))
	f.Close()
	if mode == "end" {
		os.Exit(3)
	}
	time.Sleep(time.Minute)
}

// fakeBridgeServes is aether minus WARP: socks5 with the password it was given, every connection out through the upstream.
func fakeBridgeServes(t *testing.T) {
	user, pass, _ := strings.Cut(os.Getenv("AETHER_PROXY_AUTH"), ":")
	upstream, err := url.Parse(os.Getenv("AETHER_UPSTREAM"))
	if err != nil {
		t.Fatal(err)
	}
	upPass, _ := upstream.User.Password()
	listener, err := net.Listen("tcp", os.Getenv("AETHER_SOCKS"))
	if err != nil {
		t.Fatal(err)
	}
	authenticator := auth.NewAuthenticator([]auth.AuthUser{{User: user, Pass: pass}})
	for {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		go func() {
			defer conn.Close()
			target, _, _, err := socks5.ServerHandshake(conn, authenticator)
			if err != nil {
				return
			}
			f, _ := os.OpenFile("runs.jsonl", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
			data, _ := json.Marshal(map[string]string{"connect": target.String()})
			f.Write(append(data, '\n'))
			f.Close()
			out, err := net.Dial("tcp", upstream.Host)
			if err != nil {
				return
			}
			defer out.Close()
			user := &socks5.User{Username: upstream.User.Username(), Password: upPass}
			if _, err := socks5.ClientHandshake(out, target, socks5.CmdConnect, user); err != nil {
				return
			}
			go io.Copy(out, conn)
			io.Copy(conn, out)
		}()
	}
}

func useFakeWarp(t *testing.T, mode string) string {
	t.Helper()
	home, previous := t.TempDir(), constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Setenv("SHIKOO_WARP_FAKE", mode)
	t.Setenv("HTTPS_PROXY", "http://127.0.0.1:9")
	command, restart := warpCommand, warpRestart
	warpCommand = func() *exec.Cmd { return exec.Command(os.Args[0], "-test.run=^TestWarpFakeAether$") }
	warpRestart = 50 * time.Millisecond
	t.Cleanup(func() {
		shikooCoresShutdown()
		warpMu.Lock()
		if warpNow != nil {
			warpNow.close()
			warpNow = nil
		}
		warpMu.Unlock()
		warpCommand, warpRestart = command, restart
		constant.SetHomeDir(previous)
	})
	return filepath.Join(home, "warp")
}

func warpRuns(t *testing.T, dir string, want int) []map[string]string {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		data, _ := os.ReadFile(filepath.Join(dir, "runs.jsonl"))
		var runs []map[string]string
		for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
			var run map[string]string
			if json.Unmarshal([]byte(line), &run) == nil {
				runs = append(runs, run)
			}
		}
		if len(runs) >= want {
			return runs
		}
		if time.Now().After(deadline) {
			t.Fatalf("%d bridge runs, want %d", len(runs), want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func alive(pid string) bool {
	n, _ := strconv.Atoi(pid)
	err := syscall.Kill(n, 0)
	if err != nil {
		return false
	}
	// A zombie still answers kill 0: its parent has not reaped it yet.
	stat, _ := os.ReadFile("/proc/" + pid + "/stat")
	return !strings.Contains(string(stat), ") Z ")
}

func gone(t *testing.T, pids ...string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for _, pid := range pids {
		for alive(pid) {
			if time.Now().After(deadline) {
				t.Fatalf("process %s outlived the bridge", pid)
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
}

func TestOneBridgeServesEveryGenerationAndTheLastToLetGoEndsItsWholeGroup(t *testing.T) {
	dir := useFakeWarp(t, "run")
	marked := []map[string]any{{"name": "shikoo-warp", "type": "socks5", "server": "127.0.0.1", "port": 1}}

	first, stopFirst, err := startWarp(marked)
	if err != nil {
		t.Fatal(err)
	}
	second, stopSecond, err := startWarp(marked)
	if err != nil {
		t.Fatal(err)
	}
	run := warpRuns(t, dir, 1)[0]
	proxy := first[0]
	if proxy["name"] != "shikoo-warp" || proxy["server"] != "127.0.0.1" || proxy["udp"] != true ||
		proxy["username"] == "" || proxy["password"] == "" ||
		net.JoinHostPort("127.0.0.1", strconv.Itoa(proxy["port"].(int))) != run["AETHER_SOCKS"] {
		t.Fatalf("replacement %v for a bridge on %s", proxy, run["AETHER_SOCKS"])
	}
	if second[0]["port"] != proxy["port"] || second[0]["password"] != proxy["password"] {
		t.Fatalf("the second generation got another bridge: %v", second[0])
	}
	if run["AETHER_PROXY_AUTH"] != proxy["username"].(string)+":"+proxy["password"].(string) ||
		run["AETHER_TLS_VERIFY"] != "1" || run["AETHER_MASQUE_HTTP2"] != "1" || run["HTTPS_PROXY"] != "" ||
		!strings.HasPrefix(run["AETHER_UPSTREAM"], "socks5h://") {
		t.Fatalf("the bridge ran with %v", run)
	}
	var endpoint map[string]string
	data, err := os.ReadFile(filepath.Join(dir, warpEndpoint))
	if err != nil || json.Unmarshal(data, &endpoint) != nil {
		t.Fatalf("endpoint: %v %s", err, data)
	}
	if endpoint["http"] != run["AETHER_HTTP_PROXY"] || endpoint["auth"] != run["AETHER_PROXY_AUTH"] {
		t.Fatalf("endpoint %v for a bridge run with %v", endpoint, run)
	}
	if info, _ := os.Stat(filepath.Join(dir, warpEndpoint)); info.Mode().Perm() != 0o600 {
		t.Fatalf("endpoint is %v", info.Mode())
	}

	stopFirst()
	stopFirst()
	time.Sleep(200 * time.Millisecond)
	if !alive(run["pid"]) {
		t.Fatal("the bridge stopped while a generation still held it")
	}
	stopSecond()
	gone(t, run["pid"], run["child"])
	if _, err := os.Stat(filepath.Join(dir, warpEndpoint)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("endpoint left behind: %v", err)
	}
	if runs := warpRuns(t, dir, 1); len(runs) != 1 {
		t.Fatalf("a stopped bridge started again: %d runs", len(runs))
	}
}

func TestABridgeThatEndsStartsAgainOnTheSamePortAndPassword(t *testing.T) {
	dir := useFakeWarp(t, "end")
	_, stop, err := startWarp([]map[string]any{{"name": "shikoo-warp"}})
	if err != nil {
		t.Fatal(err)
	}
	runs := warpRuns(t, dir, 2)
	stop()
	for _, key := range []string{"AETHER_SOCKS", "AETHER_HTTP_PROXY", "AETHER_PROXY_AUTH", "AETHER_UPSTREAM"} {
		if runs[0][key] != runs[1][key] {
			t.Fatalf("%s changed across a restart: %q, then %q", key, runs[0][key], runs[1][key])
		}
	}
}

func TestTheMarkedProxyReachesTheBridgeAndTheConfigParses(t *testing.T) {
	useFakeWarp(t, "run")
	raw, err := config.UnmarshalRawConfig([]byte(`
proxies:
  - {name: shikoo-warp, type: socks5, server: 127.0.0.1, port: 1, shikoo-core: warp}
  - {name: server, type: http, server: 1.1.1.1, port: 1, dialer-proxy: shikoo-warp}
`))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := shikooCoresParse(raw); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(shikooCoresCommit)
	bridge := raw.Proxy[0]
	if _, marked := bridge[shikooCoreKey]; marked || bridge["password"] == nil || bridge["port"] == 1 {
		t.Fatalf("the bridge's proxy is %v", bridge)
	}
}

func TestTheBridgesWayOutWantsItsPasswordAndDialsThroughMihomo(t *testing.T) {
	target, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { target.Close() })
	go func() {
		for {
			conn, err := target.Accept()
			if err != nil {
				return
			}
			go func() { io.Copy(conn, conn); conn.Close() }()
		}
	}()
	up, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { up.Close() })
	go serveWarpUpstream(up, auth.NewAuthenticator([]auth.AuthUser{{User: "u", Pass: "right"}}))
	hooked := hookSockets(t)
	dial := func(user *socks5.User) (net.Conn, error) {
		conn, err := net.Dial("tcp", up.Addr().String())
		if err != nil {
			return nil, err
		}
		conn.SetDeadline(time.Now().Add(5 * time.Second))
		_, err = socks5.ClientHandshake(conn, socks5.ParseAddr(target.Addr().String()), socks5.CmdConnect, user)
		return conn, err
	}

	for _, user := range []*socks5.User{nil, {Username: "u", Password: "wrong"}} {
		if conn, err := dial(user); err == nil {
			conn.Close()
			t.Fatalf("let in with %v", user)
		}
	}
	if hooked.Load() != 0 {
		t.Fatalf("dialed %d times for clients without the password", hooked.Load())
	}
	conn, err := dial(&socks5.User{Username: "u", Password: "right"})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.Write([]byte("ping"))
	echo := make([]byte, 4)
	if _, err := io.ReadFull(conn, echo); err != nil || string(echo) != "ping" {
		t.Fatalf("echo %q, %v", echo, err)
	}
	if hooked.Load() != 1 {
		t.Fatalf("mihomo's dialer ran %d times, want 1", hooked.Load())
	}
}

func TestTheBridgesIdentityStaysOutOfTheLog(t *testing.T) {
	line := "[+] warp enabled for device 0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0 key bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo= at 162.159.198.1:443"
	got := redactWarp(line)
	if strings.Contains(got, "0f1e2d3c") || strings.Contains(got, "bmXOC") || !strings.Contains(got, "162.159.198.1:443") {
		t.Fatalf("logged %q", got)
	}
}

// SHIKOO_WARP_CHAIN="host:port uuid" names a VLESS+TLS server (a Docker mihomo in the r2 notes); WARP itself is the one hop
// left out, the stand-in bridge dialing straight on through its way out.
func TestAServerBehindTheBridgeIsReachedThroughTheBridgeAndItsWayOut(t *testing.T) {
	chain := os.Getenv("SHIKOO_WARP_CHAIN")
	if chain == "" {
		t.Skip("needs a VLESS+TLS server: SHIKOO_WARP_CHAIN='host:port uuid'")
	}
	server, uuid, _ := strings.Cut(chain, " ")
	host, port, _ := net.SplitHostPort(server)
	dir := useFakeWarp(t, "socks")
	hooked := hookSockets(t)
	raw, err := config.UnmarshalRawConfig([]byte(fmt.Sprintf(`
proxies:
  - {name: server, type: vless, server: %s, port: %s, uuid: %s, tls: true, skip-cert-verify: true, servername: shikoo.test, dialer-proxy: shikoo-warp}
  - {name: shikoo-warp, type: socks5, server: 127.0.0.1, port: 1, shikoo-core: warp}
`, host, port, uuid)))
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := shikooCoresParse(raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(shikooCoresCommit)
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	var answer []byte
	deadline := time.Now().Add(15 * time.Second)
	for len(answer) == 0 && time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		conn, err := cfg.Proxies["server"].DialContext(ctx, &constant.Metadata{NetWork: constant.TCP, Host: "www.cloudflare.com", DstPort: 80})
		cancel()
		if err != nil {
			time.Sleep(200 * time.Millisecond)
			continue
		}
		conn.SetDeadline(time.Now().Add(10 * time.Second))
		conn.Write([]byte("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n"))
		answer, _ = io.ReadAll(conn)
		conn.Close()
	}
	if !strings.Contains(string(answer), "200 OK") || !strings.Contains(string(answer), "ip=") {
		t.Fatalf("no answer through the chain: %q", answer)
	}
	connects := 0
	for _, run := range warpRuns(t, dir, 1) {
		if run["connect"] != "" {
			if run["connect"] != server {
				t.Fatalf("the bridge was asked for %s, not the server %s", run["connect"], server)
			}
			connects++
		}
	}
	if connects == 0 || hooked.Load() == 0 {
		t.Fatalf("%d connects through the bridge, %d dials through mihomo's dialer", connects, hooked.Load())
	}
	t.Logf("through the bridge to %s: %d connects, %d protected dials; %s", server, connects, hooked.Load(),
		strings.Join(strings.Fields(string(answer[strings.Index(string(answer), "ip="):]))[:3], " "))
}
