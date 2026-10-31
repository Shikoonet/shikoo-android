package com.follow.clash.service.models

import com.follow.clash.common.AccessControlMode
import com.follow.clash.core.OWNER_HELD
import com.follow.clash.core.OWNER_IRAN_DIRECT
import java.io.File
import java.net.Inet4Address
import java.net.Inet6Address
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

private fun optionsWithRoutes(routeAddress: List<String>) = VpnOptions(
    enable = true,
    port = 7890,
    ipv6 = true,
    dnsHijacking = false,
    accessControlProps = AccessControlProps(
        enable = false,
        mode = AccessControlMode.ACCEPT_SELECTED,
        acceptList = emptyList(),
        rejectList = emptyList(),
    ),
    allowBypass = false,
    systemProxy = true,
    bypassDomain = emptyList(),
    stack = "gvisor",
    routeAddress = routeAddress,
)

class ToCIDRTest {
    @Test
    fun `parses an IPv4 network`() {
        val cidr = "192.168.1.0/24".toCIDR()

        assertTrue(cidr.address is Inet4Address)
        assertEquals("192.168.1.0", cidr.address.hostAddress)
        assertEquals(24, cidr.prefixLength)
    }

    @Test
    fun `parses an IPv6 network`() {
        val cidr = "fd00::/8".toCIDR()

        assertTrue(cidr.address is Inet6Address)
        assertEquals(8, cidr.prefixLength)
    }

    @Test
    fun `accepts the boundary prefix lengths`() {
        assertEquals(0, "0.0.0.0/0".toCIDR().prefixLength)
        assertEquals(32, "10.0.0.1/32".toCIDR().prefixLength)
        assertEquals(0, "::/0".toCIDR().prefixLength)
        assertEquals(128, "fd00::1/128".toCIDR().prefixLength)
    }

    @Test
    fun `rejects an address without a prefix`() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0".toCIDR()
        }
        assertTrue(error.message!!.contains("Invalid CIDR format"))
    }

    @Test
    fun `rejects an address with too many segments`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/24/8".toCIDR()
        }
    }

    @Test
    fun `rejects a non-numeric prefix`() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/abc".toCIDR()
        }
        assertTrue(error.message!!.contains("Invalid prefix length"))
    }

    @Test
    fun `rejects an IPv4 prefix above 32`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/33".toCIDR()
        }
    }

    @Test
    fun `rejects an IPv6 prefix above 128`() {
        assertThrows(IllegalArgumentException::class.java) {
            "fd00::/129".toCIDR()
        }
    }

    @Test
    fun `rejects a negative prefix`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/-1".toCIDR()
        }
    }
}

class RouteAddressTest {
    @Test
    fun `splits a mixed route list by address family`() {
        val options = optionsWithRoutes(
            listOf("192.168.1.0/24", "fd00::/8", "10.0.0.0/8", "2000::/3"),
        )

        val ipv4 = options.getIpv4RouteAddress()
        val ipv6 = options.getIpv6RouteAddress()

        assertEquals(2, ipv4.size)
        assertEquals(2, ipv6.size)
        assertTrue(ipv4.all { it.address is Inet4Address })
        assertTrue(ipv6.all { it.address is Inet6Address })
    }

    @Test
    fun `returns empty lists for an empty route list`() {
        val options = optionsWithRoutes(emptyList())

        assertTrue(options.getIpv4RouteAddress().isEmpty())
        assertTrue(options.getIpv6RouteAddress().isEmpty())
    }

    @Test
    fun `preserves the configured order within a family`() {
        val options = optionsWithRoutes(
            listOf("10.0.0.0/8", "fd00::/8", "192.168.0.0/16"),
        )

        assertEquals(
            listOf(8, 16),
            options.getIpv4RouteAddress().map { it.prefixLength },
        )
    }

    @Test
    fun `propagates a malformed entry instead of silently dropping it`() {
        val options = optionsWithRoutes(listOf("192.168.1.0/24", "not-a-cidr"))

        assertThrows(IllegalArgumentException::class.java) {
            options.getIpv4RouteAddress()
        }
    }
}

private fun optionsFor(core: String?, accessControl: AccessControlProps) =
    optionsWithRoutes(emptyList()).copy(core = core, accessControlProps = accessControl)

private fun accessControl(enable: Boolean, mode: AccessControlMode) = AccessControlProps(
    enable = enable,
    mode = mode,
    acceptList = listOf("a.b"),
    rejectList = listOf("c.d"),
)

class AppRulesTest {
    private val self = "com.shikoonet.app"

    @Test
    fun `mihomo and an owner core both keep this app in their VPN, as FlClash does`() {
        for (core in listOf(null, "", "wireguard", "openvpn")) {
            assertEquals(
                AppRules(emptyList(), emptyList()),
                optionsFor(core, accessControl(false, AccessControlMode.ACCEPT_SELECTED)).appRules(self),
            )
            assertEquals(
                AppRules(emptyList(), listOf("c.d")),
                optionsFor(core, accessControl(true, AccessControlMode.REJECT_SELECTED)).appRules(self),
            )
            assertEquals(
                AppRules(listOf("a.b", self), emptyList()),
                optionsFor(core, accessControl(true, AccessControlMode.ACCEPT_SELECTED)).appRules(self),
            )
        }
    }
}

// The Builder needs Android itself, so the service's source is read: a bypassable VPN builds a new network on a switch.
class VpnShapeTest {
    private val service = File("src/main/java/com/follow/clash/service/VpnService.kt").readText()

    @Test
    fun `no VPN the service builds is bypassable`() {
        assertFalse(Regex("""\ballowBypass\s*\(""").containsMatchIn(service))
    }

    @Test
    fun `a revoke drops the owner core's protect, which a switch's stop keeps and Android now denies`() {
        val onRevoke = Regex("""override fun onRevoke\(\) \{(.*?)\n    \}""", RegexOption.DOT_MATCHES_ALL)
            .find(service)?.groupValues?.get(1).orEmpty()
        assertTrue(onRevoke.contains("Core.setOwnerProtector(null)"))
    }

    // A full stop clears the pin through the protector; only a switch's stop may keep both (core/shikoo_owner_protect.go).
    @Test
    fun `a full stop drops the owner core's protect and only a switch keeps it`() {
        val cleanup = Regex("""private fun cleanup\(keepHeld: Boolean = false\) \{(.*?)\n    \}""", RegexOption.DOT_MATCHES_ALL)
            .find(service)?.groupValues?.get(1).orEmpty()
        assertTrue(cleanup.substringAfter("} else {").contains("Core.setOwnerProtector(null)"))
        val stop = Regex("""override fun stop\(\) \{(.*?)\n    \}""", RegexOption.DOT_MATCHES_ALL)
            .find(service)?.groupValues?.get(1).orEmpty()
        assertTrue(stop.contains("cleanup(keepHeld = switching)"))
    }
}

class OwnerArgumentsTest {
    // The json tag Go reads (PrepareOwnerParams, TestPrepareOwnerReadsTheKeysKotlinSends).
    @Test
    fun iranDirectGoesUnderTheKeyGoReads() = assertEquals("iran-direct", OWNER_IRAN_DIRECT)

    @Test
    fun heldGoesUnderTheKeyGoReads() = assertEquals("held", OWNER_HELD)

    // Whether a switch held the VPN is the one fact Go cannot see: its DNS decides on it (core/shikoo_dns.go).
    private val service = File("src/main/java/com/follow/clash/service/VpnService.kt").readText()

    @Test
    fun `a start reads whether a switch held the VPN before it holds a blocking one`() {
        val start = service.substringAfter("private fun handleStart(options: VpnOptions) {")
        val take = start.indexOf("val held = heldTun.take()")
        assertTrue(take >= 0 && start.indexOf("holdBlocked(options)") > take)
    }

    @Test
    fun `a start hands the answer itself to prepareOwner`() {
        assertTrue(Regex("""Core\.prepareOwner\(.*,\s*held\)""").containsMatchIn(service))
    }

    @Test
    fun `prepareOwner puts the answer itself in the call`() {
        val core = File("../core/src/main/java/com/follow/clash/core/Core.kt").readText()
        assertTrue(core.contains(".put(OWNER_HELD, held)"))
    }
}
