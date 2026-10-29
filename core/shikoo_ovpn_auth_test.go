package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
)

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
