package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// A working server, a second one under its name, and one of each bad server a panel was seen able to send. Any one of
// them used to make the core refuse the whole subscription and fall back to a config that sends everything direct.
const oneGoodServerAndBadOnes = `proxies:
  - {name: good, type: http, server: 127.0.0.1, port: 1}
  - {name: good, type: http, server: 127.0.0.1, port: 2}
  - {name: reality-key, type: vless, server: 127.0.0.1, port: 443, uuid: ccb7f421-4834-4fb2-9e96-1e564c8c96b1, tls: true, servername: a.example, client-fingerprint: chrome, reality-opts: {public-key: "not*base64!", short-id: 6ba85179}}
  - {name: reality-short-id, type: vless, server: 127.0.0.1, port: 443, uuid: ccb7f421-4834-4fb2-9e96-1e564c8c96b1, tls: true, servername: a.example, client-fingerprint: chrome, reality-opts: {public-key: abNRbP0RHPmECwfieunkaXCFZA8QT7RgCpu733m1UGA, short-id: zz}}
  - {name: flow, type: vless, server: 127.0.0.1, port: 443, uuid: ccb7f421-4834-4fb2-9e96-1e564c8c96b1, tls: true, flow: xtls-rprx-unknown}
  - {name: wg-key, type: wireguard, server: 127.0.0.1, port: 51820, ip: 10.0.0.2, private-key: "not*base64!", public-key: abNRbP0RHPmECwfieunkaXCFZA8QT7RgCpu733m1UGA=}
  - {name: wg-ip, type: wireguard, server: 127.0.0.1, port: 51820, ip: 10.0.0, private-key: WJhIawYqQgyJEwcrssTSFp3CW9Q8a6HivseOgQ2643U=, public-key: abNRbP0RHPmECwfieunkaXCFZA8QT7RgCpu733m1UGA=}
  - {name: future, type: futureproto, server: 127.0.0.1, port: 1}
proxy-groups:
  - {name: PROXY, type: select, proxies: [good, reality-key, reality-short-id, flow, wg-key, wg-ip, future]}
rules:
  - MATCH,PROXY
`

func TestABadServerLeavesTheRestOfTheSubscription(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte(oneGoodServerAndBadOnes), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := loadConfig(path)

	if err != nil {
		t.Fatalf("loadConfig = %v: one bad server refused the whole subscription", err)
	}
	for _, name := range []string{"reality-key", "reality-short-id", "flow", "wg-key", "wg-ip", "future"} {
		if _, ok := cfg.Proxies[name]; ok {
			t.Errorf("the bad server %q was kept", name)
		}
	}
	if good, ok := cfg.Proxies["good"]; !ok || good.Addr() != "127.0.0.1:1" {
		t.Fatalf("the first server named good is gone or replaced by the second: %v", good)
	}
	raw, err := json.Marshal(cfg.Proxies["PROXY"])
	if err != nil {
		t.Fatal(err)
	}
	var group struct{ All []string }
	if err := json.Unmarshal(raw, &group); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(group.All, []string{"good"}) {
		t.Errorf("group PROXY lists %v, want only [good]", group.All)
	}
}

func TestAFailedApplyRejectsInsteadOfGoingDirect(t *testing.T) {
	home := constant.Path.HomeDir()
	dir := t.TempDir()
	constant.SetHomeDir(dir)
	previous := currentConfig
	t.Cleanup(func() {
		constant.SetHomeDir(home)
		tunnel.UpdateRules(nil, nil, nil)
		currentConfig = previous
	})
	// A rule naming a server that does not exist: no single server to leave out, the whole config is refused.
	broken := "proxies: []\nrules:\n  - MATCH,missing\n"
	if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(broken), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := applyConfig(&SetupParams{}); err == nil {
		t.Fatal("a config the core cannot parse applied without an error, so the app would not stop")
	}

	rules := tunnel.Rules()
	if len(rules) == 0 || rules[len(rules)-1].Adapter() != "REJECT" {
		t.Fatalf("the fallback's rules are %v: with no rule, everything leaves direct while the app shows connected", rules)
	}
}
