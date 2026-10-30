package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

// The same file is test/shikoo/controller_wiring_test.dart's: Dart reads as refused exactly what Go answers.
func TestTestProxyDelayAnswersARefusedLoginAsDartReadsIt(t *testing.T) {
	content, err := os.ReadFile("testdata/ovpn_login_refused.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Value int32  `json:"value"`
		Error string `json:"error"`
	}
	if err := json.Unmarshal(content, &fixture); err != nil {
		t.Fatal(err)
	}
	before := proxyURLTest
	t.Cleanup(func() { proxyURLTest = before })
	for _, answer := range []struct {
		err  error
		want int32
	}{
		{errors.New(fixture.Error), fixture.Value},
		{errors.New("connect OpenVPN server: dial udp 203.0.113.9:1194: connect: connection refused"), -1},
	} {
		proxyURLTest = func(context.Context, C.Proxy, string) (uint16, error) { return 0, answer.err }
		delay, err := handleTestProxyDelay(&TestProxyDelayParams{Proxy: ovpnMapping(nil), Timeout: 1000})
		if err != nil || delay == nil {
			t.Fatalf("%v: %v %v", answer.err, delay, err)
		}
		if delay.Value != answer.want {
			t.Errorf("%v: answered %d, not %d", answer.err, delay.Value, answer.want)
		}
	}
}

func TestARefusedOpenvpnLoginIsToldApartFromEveryOtherFailure(t *testing.T) {
	refusal := errors.New(ovpnAuthFailedText)
	for _, err := range []error{
		fmt.Errorf("make OpenVPN handshake: %w", fmt.Errorf("%w: AUTH_FAILED", refusal)),
		fmt.Errorf("dial: %v", fmt.Errorf("make OpenVPN handshake: %w", refusal)),
	} {
		if !ovpnRefusedLogin(err) {
			t.Errorf("not read as refused: %v", err)
		}
	}
	for _, err := range []error{
		nil,
		errors.New("connect OpenVPN server: dial udp 203.0.113.9:1194: connect: connection refused"),
		errors.New("make OpenVPN handshake: openvpn tls handshake: context deadline exceeded"),
		errors.New("make OpenVPN handshake: openvpn push reply missing ifconfig address"),
	} {
		if ovpnRefusedLogin(err) {
			t.Errorf("read as refused: %v", err)
		}
	}
}

// A tripwire for a core update: mihomo keeps the error unexported, so its message is what testProxyDelay matches.
func TestMihomosOpenvpnClientStillNamesARefusalAsMatched(t *testing.T) {
	source, err := os.ReadFile("Clash.Meta/transport/openvpn/client.go")
	if err != nil {
		t.Fatal(err)
	}
	want := `errAuthFailed = errors.New("` + ovpnAuthFailedText + `")`
	if !strings.Contains(string(source), want) {
		t.Fatalf("transport/openvpn no longer declares %s", want)
	}
}
