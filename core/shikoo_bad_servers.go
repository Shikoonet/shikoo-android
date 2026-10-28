package main

import (
	"errors"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
)

var errNameTaken = errors.New("a server by this name came first")

// shortcut: a rule naming a dropped server still refuses the config (it fails closed); panels name groups in rules.
// shortcut: proxy-providers' servers go unchecked, a bad one sends its group DIRECT; check them once a sub ships one.
func leaveOutBadServers(raw *config.RawConfig) {
	kept, taken, bad := raw.Proxy[:0], map[string]bool{}, map[string]bool{}
	for _, mapping := range raw.Proxy {
		name, _ := mapping["name"].(string)
		proxy, err := adapter.ParseProxy(mapping)
		if err == nil {
			_ = proxy.Close()
			if taken[name] {
				err = errNameTaken
			}
		}
		if err != nil {
			log.Warnln("[SHIKOO] server %q left out: %v", name, err)
			bad[name] = true
			continue
		}
		taken[name] = true
		kept = append(kept, mapping)
	}
	raw.Proxy = kept
	for _, group := range raw.ProxyGroup {
		names, _ := group["proxies"].([]any)
		members := names[:0]
		for _, member := range names {
			if name, _ := member.(string); bad[name] && !taken[name] {
				continue
			}
			members = append(members, member)
		}
		if names != nil {
			group["proxies"] = members
		}
	}
}

func failClosedConfig() (*config.Config, error) {
	raw := config.DefaultRawConfig()
	raw.Rule = []string{"MATCH,REJECT"}
	return config.ParseRawConfig(raw)
}
