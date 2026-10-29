package main

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

// The shape withDirectInbound (lib/shikoo/engine/direct_dns.dart) gives the core, its test pinning it there. The main
// rules send everything DIRECT, so only the inbound's own rules can refuse.
const directInboundConfig = `skip-auth-prefixes: []
hosts: {sub.test: 127.0.0.1, other.test: 127.0.0.1}
listeners:
  - {name: shikoo-direct, type: http, listen: 127.0.0.1, port: "%d", users: [{username: u, password: p}], rule: shikoo-direct}
sub-rules:
  shikoo-direct:
    - DOMAIN,sub.test,DIRECT
    - MATCH,REJECT
proxies: []
rules:
  - MATCH,DIRECT
`

func TestTheDirectInboundTakesItsCredentialsAndReachesOnlyTheSubscriptionHosts(t *testing.T) {
	var asked atomic.Int32
	site := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		asked.Add(1)
	}))
	t.Cleanup(site.Close)
	sitePort := strconv.Itoa(site.Listener.Addr().(*net.TCPAddr).Port)
	free, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := free.Addr().(*net.TCPAddr).Port
	_ = free.Close()
	applyHome(t)(fmt.Sprintf(directInboundConfig, port))
	isRunning.Store(true)
	t.Cleanup(func() {
		isRunning.Store(false)
		listener.PatchInboundListeners(nil, tunnel.Tunnel, true)
	})
	if err := applyConfig(&SetupParams{}); err != nil {
		t.Fatal(err)
	}
	get := func(user *url.Userinfo, host string) (int, error) {
		proxy := &url.URL{Scheme: "http", User: user, Host: "127.0.0.1:" + strconv.Itoa(port)}
		client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxy)}}
		response, err := client.Get("http://" + host + ":" + sitePort + "/")
		if err != nil {
			return 0, err
		}
		_ = response.Body.Close()
		return response.StatusCode, nil
	}

	if status, err := get(nil, "sub.test"); err != nil || status != http.StatusProxyAuthRequired {
		t.Errorf("no credentials: status %d, %v; another app on the device would leave direct by it", status, err)
	}
	if status, err := get(url.UserPassword("u", "wrong"), "sub.test"); err != nil || status != http.StatusForbidden {
		t.Errorf("a wrong password: status %d, %v", status, err)
	}
	if status, err := get(url.UserPassword("u", "p"), "other.test"); err == nil && status == http.StatusOK {
		t.Errorf("another host passed with status %d: the inbound must reach the subscription hosts only", status)
	}
	if asked.Load() != 0 {
		t.Fatalf("the site saw %d requests before the subscription host was asked", asked.Load())
	}
	if status, err := get(url.UserPassword("u", "p"), "sub.test"); err != nil || status != http.StatusOK || asked.Load() != 1 {
		t.Errorf("the subscription host: status %d, %v, the site saw %d requests", status, err, asked.Load())
	}
}
