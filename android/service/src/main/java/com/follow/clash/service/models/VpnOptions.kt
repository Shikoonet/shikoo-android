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

fun VpnOptions.appRules(self: String): AppRules {
    val accessControl = accessControlProps
    if (!accessControl.enable) {
        return AppRules(emptyList(), if (ownsTunnel) listOf(self) else emptyList())
    }
    return when (accessControl.mode) {
        // shortcut: an owner core with nothing else selected takes every app, this one too; Shikoo shows no app list.
        AccessControlMode.ACCEPT_SELECTED -> AppRules(
            if (ownsTunnel) accessControl.acceptList - self else accessControl.acceptList + self,
            emptyList(),
        )

        AccessControlMode.REJECT_SELECTED -> AppRules(
            emptyList(),
            if (ownsTunnel) accessControl.rejectList + self else accessControl.rejectList - self,
        )
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
