package main

import (
	"context"
	"fmt"
	"time"

	"github.com/metacubex/mihomo/adapter"
	C "github.com/metacubex/mihomo/constant"
)

// testProxyDelay is handleTestDelay on a proxy built from a profile the core has not loaded, closed
// after, as a WireGuard one holds a device and a socket. The tunnel's socket hook protects it too.
const testProxyDelayMethod CoreMethod = "testProxyDelay"

type TestProxyDelayParams struct {
	Proxy   map[string]any `json:"proxy"`
	TestUrl string         `json:"test-url"`
	Timeout int64          `json:"timeout"`
}

func init() {
	registerMethod(testProxyDelayMethod, withArguments(func(params *TestProxyDelayParams, response MethodResponse) {
		safeGo(response, func() {
			delay, err := handleTestProxyDelay(params)
			if err != nil {
				response.failure("invalid_proxy", err.Error(), nil)
				return
			}
			response.success(delay)
		})
	}))
}

func handleTestProxyDelay(params *TestProxyDelayParams) (*Delay, error) {
	if idle := shikooOwnerIdlePings[fmt.Sprint(params.Proxy[shikooOwnerKey])]; idle != nil {
		name := fmt.Sprint(params.Proxy["name"])
		return idle(params.Proxy, &TestDelayParams{ProxyName: name, TestUrl: params.TestUrl, Timeout: params.Timeout}), nil
	}
	proxy, err := adapter.ParseProxy(params.Proxy)
	if err != nil {
		return nil, err
	}
	defer func() { _ = proxy.Close() }()

	url := params.TestUrl
	if url == "" {
		url = currentTestURL()
	}
	delayData := &Delay{Name: proxy.Name(), Url: url, Value: -1}
	timeout := delayTestTimeout(params.Timeout)

	queueCtx, cancelQueue := context.WithTimeout(context.Background(), timeout)
	granted := acquireDelayTestSlot(queueCtx)
	cancelQueue()
	if !granted {
		return nil, nil
	}
	defer releaseDelayTestSlot()

	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout(proxy, timeout))
	defer cancel()
	delay, err := proxyURLTest(ctx, proxy, url)
	if ovpnRefusedLogin(err) {
		delayData.Value = ovpnLoginRefused
	}
	if err != nil {
		return delayData, nil
	}
	delayData.Value = delayValue(delay)
	return delayData, nil
}

// A var so a test hands handleTestProxyDelay a server's answer, AUTH_FAILED among them, without a server.
var proxyURLTest = func(ctx context.Context, proxy C.Proxy, url string) (uint16, error) {
	return proxy.URLTest(ctx, url, anyDelayTestStatus)
}

// wireGuardGrace is wireguard-go's RekeyTimeout: a probe's first dial builds the device, and a lost
// first handshake goes out again only this much later (SHIKOO_PATCHES 60). A var so tests skip it.
var wireGuardGrace = 5 * time.Second

func probeTimeout(proxy C.Proxy, timeout time.Duration) time.Duration {
	if proxy.Type() == C.WireGuard {
		return timeout + wireGuardGrace
	}
	return timeout
}
