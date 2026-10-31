package main

import (
	"fmt"
	"maps"
	"net"
	"os"
	"path/filepath"
	"slices"
	"sync"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

type shikooCoreStart func(proxies []map[string]any) (replacements []map[string]any, stop func(), err error)

// shikooCoreKey is what lib/shikoo/engine/cores.dart writes on a marked proxy.
const shikooCoreKey = "shikoo-core"

// shikooCoreStartingFile names the core being started; left behind, the app takes that pick back on its next start
// (`forgetCrashed` in lib/shikoo/engine/settings.dart).
const shikooCoreStartingFile = "shikoo-core-starting"

var (
	shikooCores = map[string]shikooCoreStart{}

	// Changed only under configMu.
	shikooCoresRunning  []func()
	shikooCoresStarting []func()
	shikooLastConfig    []byte
	shikooLastSelected  map[string]string
)

func registerShikooCore(name string, start shikooCoreStart) {
	if _, exists := shikooCores[name]; exists {
		panic("shikoo core registered twice: " + name)
	}
	shikooCores[name] = start
}

// shikooCoresParse leaves the proxies of a core this build lacks, or of one that fails, to mihomo.
func shikooCoresParse(raw *config.RawConfig) (*config.Config, error) {
	shikooCoresRewrite(raw)
	// After the rewrite: a server a core took is its loopback SOCKS by now, so only what mihomo carries is checked.
	leaveOutBadServers(raw)
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		for _, stop := range shikooCoresStarting {
			stop()
		}
		shikooCoresStarting = nil
		return cfg, err
	}
	shikooOwnerGates(raw, cfg)
	return cfg, nil
}

func shikooCoresRewrite(raw *config.RawConfig) {
	marked := map[string][]int{}
	var names []string
	for i, proxy := range raw.Proxy {
		value, ok := proxy[shikooCoreKey]
		if !ok {
			continue
		}
		delete(proxy, shikooCoreKey)
		name := fmt.Sprint(value)
		if _, seen := marked[name]; !seen {
			names = append(names, name)
		}
		marked[name] = append(marked[name], i)
	}
	for _, name := range names {
		at := marked[name]
		start := shikooCores[name]
		if start == nil {
			log.Warnln("[SHIKOO] core %s is not in this build; mihomo carries its %d servers", name, len(at))
			continue
		}
		proxies := make([]map[string]any, len(at))
		for j, i := range at {
			proxies[j] = raw.Proxy[i]
		}
		starting := filepath.Join(constant.Path.HomeDir(), shikooCoreStartingFile)
		_ = os.WriteFile(starting, []byte(name), 0o600)
		replacements, stop, err := start(proxies)
		_ = os.Remove(starting)
		if err == nil {
			if err = shikooCoresMatch(proxies, replacements); err != nil {
				stop()
			}
		}
		if err != nil {
			log.Warnln("[SHIKOO] core %s failed; mihomo carries its %d servers: %v", name, len(at), err)
			continue
		}
		for j, i := range at {
			shikooRemoteDNS(proxies[j], replacements[j])
			raw.Proxy[i] = replacements[j]
		}
		shikooCoresStarting = append(shikooCoresStarting, stop)
	}
}

func shikooRemoteDNS(server, replacement map[string]any) {
	if replacement["type"] != "socks5" || server["remote-dns-resolve"] == false {
		return
	}
	dns, _ := server["dns"].([]any)
	if server["remote-dns-resolve"] != true || len(dns) == 0 {
		dns = []any{"1.1.1.1", "8.8.8.8"}
	}
	replacement["remote-dns-resolve"], replacement["dns"] = true, dns
}

// shikooCoresMatch: a replacement under another name leaves the groups naming a proxy that is gone, and the config fails.
func shikooCoresMatch(proxies, replacements []map[string]any) error {
	if len(replacements) != len(proxies) {
		return fmt.Errorf("%d replacements for %d servers", len(replacements), len(proxies))
	}
	for j, proxy := range proxies {
		if name := fmt.Sprint(replacements[j]["name"]); name != fmt.Sprint(proxy["name"]) {
			return fmt.Errorf("replacement %d is named %q, not %q", j, name, fmt.Sprint(proxy["name"]))
		}
	}
	return nil
}

// shikooCoresAfterTun: a socket a core opened at apply before Android's tunnel has no protect (multi-core.md §4).
func shikooCoresAfterTun() {
	configMu.Lock()
	defer configMu.Unlock()
	if len(shikooCoresRunning) == 0 {
		return
	}
	// From memory, not config.yaml, which Dart may be writing in place right now.
	raw, err := config.UnmarshalRawConfig(shikooLastConfig)
	if err != nil {
		logError("rebuilding the cores once the tunnel is up: %v", err)
		return
	}
	cfg, err := shikooCoresParse(raw)
	if err != nil {
		logError("rebuilding the cores once the tunnel is up: %v", err)
		return
	}
	applyLoaded(cfg, liveSelections(), true)
}

func liveSelections() map[string]string {
	selectMu.Lock()
	defer selectMu.Unlock()
	selected := maps.Clone(shikooLastSelected)
	if selected == nil {
		selected = map[string]string{}
	}
	for name, proxy := range tunnel.AllProxies() {
		if outbound, ok := proxy.(*adapter.Proxy); ok {
			if selector, ok := outbound.ProxyAdapter.(*outboundgroup.Selector); ok {
				selected[name] = selector.Now()
			}
		}
	}
	return selected
}

func shikooCoresShutdown() {
	for _, stop := range slices.Concat(shikooCoresRunning, shikooCoresStarting) {
		stop()
	}
	shikooCoresRunning, shikooCoresStarting = nil, nil
}

func shikooCoresCommit() {
	for _, stop := range shikooCoresRunning {
		stop()
	}
	shikooCoresRunning, shikooCoresStarting = shikooCoresStarting, nil
}

var (
	portsMu    sync.Mutex
	portsTaken = map[int]bool{}
)

// loopbackPorts holds n listeners open together till release, so no port repeats (Xray's SO_REUSEPORT shares one).
// shortcut: a port can be taken before each Xray, sing-box or WARP bind; hand the core its listener if ever seen.
func loopbackPorts(n int) (ports []int, release func(), err error) {
	portsMu.Lock()
	defer portsMu.Unlock()
	var held []net.Listener
	release = func() {
		for _, listener := range held {
			_ = listener.Close()
		}
	}
	for len(ports) < n {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			release()
			return nil, nil, err
		}
		held = append(held, listener)
		if port := listener.Addr().(*net.TCPAddr).Port; !portsTaken[port] {
			ports = append(ports, port)
		}
	}
	for _, port := range ports {
		portsTaken[port] = true
	}
	return ports, release, nil
}

func forgetPorts(ports ...int) {
	portsMu.Lock()
	defer portsMu.Unlock()
	for _, port := range ports {
		delete(portsTaken, port)
	}
}
