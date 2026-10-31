package main

import "strings"

// ovpnLoginRefused is testProxyDelay's answer when the OpenVPN server itself said AUTH_FAILED: the account is
// refused, not unreachable. Every other failure stays -1; Dart reads any value up to 0 as no answer.
const ovpnLoginRefused int32 = -2

// ovpnAuthFailedText is the message of errAuthFailed in mihomo's transport/openvpn (client.go), which keeps it
// unexported; a match on it survives every wrap between the handshake and the URL test.
const ovpnAuthFailedText = "openvpn authentication failed"

func ovpnRefusedLogin(err error) bool {
	return err != nil && strings.Contains(err.Error(), ovpnAuthFailedText)
}
