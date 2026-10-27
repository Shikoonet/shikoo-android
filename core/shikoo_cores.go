package main

import (
	"fmt"
	"maps"
	"slices"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// shikooCoreStart is a core behind mihomo (docs/multi-core.md): marked proxies in, their replacements out in order.
type shikooCoreStart func(proxies []map[string]any) (replacements []map[string]any, stop func(), err error)

// shikooCoreKey is what lib/shikoo/engine/cores.dart writes on a marked proxy.
const shikooCoreKey = "shikoo-core"

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
		replacements, stop, err := start(proxies)
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
			raw.Proxy[i] = replacements[j]
		}
		shikooCoresStarting = append(shikooCoresStarting, stop)
	}
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
	applyLoaded(cfg, liveSelections())
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
