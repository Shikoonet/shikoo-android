package com.follow.clash.service.models

import com.follow.clash.common.AccessControlMode
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

data class AccessControlProps(
    val enable: Boolean,
    val mode: AccessControlMode,
    val acceptList: List<String>,
    val rejectList: List<String>,
)

data class VpnOptions(
    val enable: Boolean,
    val port: Int,
    val ipv6: Boolean,
    val dnsHijacking: Boolean,
    val accessControlProps: AccessControlProps,
    val allowBypass: Boolean,
    val systemProxy: Boolean,
    val bypassDomain: List<String>,
    val stack: String,
    val routeAddress: List<String>,
    val core: String? = null,
    val server: String? = null,
    val iranDirect: Boolean = false,
)

val VpnOptions.ownsTunnel: Boolean
    get() = !core.isNullOrEmpty()

data class AppRules(
    val allowed: List<String>,
    val disallowed: List<String>,
)

// FlClash's rules for an owner core's VPN too: a switch keeps the same apps (VpnService.establishWith). This app stays
// in, since mihomo's system stack answers through tun0, so an owner's VPN holds it and its sockets need protect.
fun VpnOptions.appRules(self: String): AppRules {
    val accessControl = accessControlProps
    if (!accessControl.enable) {
        return AppRules(emptyList(), emptyList())
    }
    return when (accessControl.mode) {
        AccessControlMode.ACCEPT_SELECTED -> AppRules(accessControl.acceptList + self, emptyList())
        AccessControlMode.REJECT_SELECTED -> AppRules(emptyList(), accessControl.rejectList - self)
    }
}

data class CIDR(
    val address: InetAddress,
    val prefixLength: Int,
)

fun VpnOptions.getIpv4RouteAddress(): List<CIDR> = routeAddress
    .map(String::toCIDR)
    .filter { it.address is Inet4Address }

fun VpnOptions.getIpv6RouteAddress(): List<CIDR> = routeAddress
    .map(String::toCIDR)
    .filter { it.address is Inet6Address }

fun String.toCIDR(): CIDR {
    val parts = split("/")
    require(parts.size == 2) { "Invalid CIDR format: $this" }
    val ipAddress = parts[0]
    val prefixLength = parts[1].toIntOrNull()
        ?: throw IllegalArgumentException("Invalid prefix length: ${parts[1]}")

    val address = InetAddress.getByName(ipAddress)
    val maxPrefix = if (address.address.size == 4) 32 else 128
    require(prefixLength in 0..maxPrefix) {
        "Invalid prefix length $prefixLength for $ipAddress"
    }

    return CIDR(address, prefixLength)
}
