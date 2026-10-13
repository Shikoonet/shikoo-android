package main

import (
	"context"

	"github.com/metacubex/mihomo/adapter"
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

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	delay, err := proxy.URLTest(ctx, url, anyDelayTestStatus)
	if err != nil {
		return delayData, nil
	}
	delayData.Value = delayValue(delay)
	return delayData, nil
}
