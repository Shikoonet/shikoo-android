package main

import (
	"fmt"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
)

// shikooCoreStart is a core behind mihomo (docs/multi-core.md): marked proxies in, their replacements out in order.
type shikooCoreStart func(proxies []map[string]any) (replacements []map[string]any, stop func(), err error)

// shikooCoreKey is what lib/shikoo/engine/cores.dart writes on a marked proxy.
const shikooCoreKey = "shikoo-core"

var (
	shikooCores = map[string]shikooCoreStart{}

	// Only applyConfig changes these, under configMu.
	shikooCoresRunning  []func()
	shikooCoresStarting []func()
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
	}
	return cfg, err
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
		if err == nil && len(replacements) != len(at) {
			stop()
			err = fmt.Errorf("%d replacements for %d servers", len(replacements), len(at))
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

func shikooCoresCommit() {
	for _, stop := range shikooCoresRunning {
		stop()
	}
	shikooCoresRunning, shikooCoresStarting = shikooCoresStarting, nil
}
