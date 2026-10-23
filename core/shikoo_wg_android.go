//go:build android

package main

// Windows registers its own "wireguard" owner: a name registered twice panics.
func init() {
	registerShikooOwner("wireguard", ownerServer)
}
