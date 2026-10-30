package com.follow.clash.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnTest {
    // The key Go writes the profile under (core/shikoo_ovpn.go, TestPrepareOwnerGivesOpenvpnItsProfile).
    @Test
    fun `the profile is read under the key Go writes`() = assertEquals("ovpn", OPENVPN_PROFILE)

    // A JVM test has no libovpn3.so; VpnService fails the start, never handing the server to mihomo (Sam, 2026-10-30).
    @Test
    fun `an engine missing from the build fails the start`() {
        val failure = OpenVpn("ov", { true }, { -1 }).start("client", "u", "p")
        assertTrue(failure?.reason.orEmpty().startsWith("no engine"))
    }

    @Test
    fun `VpnService has no mihomo after the official engine`() {
        val source = java.io.File("src/main/java/com/follow/clash/service/VpnService.kt").readText()
        val failed = source.substringAfter("engine.start(").substringBefore("private fun ")
        assertTrue(failed.contains("error(\"OpenVPN did not connect"))
        assertTrue(!failed.contains("handleStart("))
    }
}
