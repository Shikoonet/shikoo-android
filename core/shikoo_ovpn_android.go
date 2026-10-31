//go:build android

package main

// Android only: Windows's OpenVPN engine waits for its own package.
func init() {
	registerShikooOwner("openvpn", ovpnCarrying, ovpnPing)
	shikooOwnerIdlePings["openvpn"] = ovpnIdlePing
}
