//go:build android || windows

package main

// A file name ending in _android.go would build for Android alone, whatever the tag says.
func init() {
	registerShikooOwner("openvpn", ovpnCarrying, ovpnPing)
	shikooOwnerIdlePings["openvpn"] = ovpnIdlePing
	shikooOwnerStates["openvpn"] = ovpnOwnerState
}
