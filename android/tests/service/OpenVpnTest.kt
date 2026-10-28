package com.follow.clash.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnTest {
    // The key Go writes the profile under (core/shikoo_ovpn.go, TestPrepareOwnerGivesOpenvpnItsProfile).
    @Test
    fun `the profile is read under the key Go writes`() = assertEquals("ovpn", OPENVPN_PROFILE)

    // VpnService then hands the server to mihomo (Sam, 2026-10-23); a JVM test has no libovpn3.so.
    @Test
    fun `an engine missing from the build refuses the server`() {
        val failure = OpenVpn("ov", { true }, { -1 }).start("client", "u", "p")
        assertTrue(failure?.refused == true)
    }
}
