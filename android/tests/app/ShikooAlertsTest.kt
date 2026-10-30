package com.follow.clash

import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShikooAlertsTest {
    private val at = 1_793_000_000_000L
    private val us = 10251

    @Test
    fun `a drop within ten minutes of the last one updates the alert quietly`() {
        assertTrue(quiet(at, at))
        assertTrue(quiet(at, at + QUIET_MILLIS - 1))
    }

    @Test
    fun `the first drop, one ten minutes later, and one after the clock went back head up`() {
        assertFalse(quiet(Long.MIN_VALUE / 2, at))
        assertFalse(quiet(at, at + QUIET_MILLIS))
        assertFalse(quiet(at, at - 1))
    }

    @Test
    fun `no VPN, or only ours going down, is the customer's own stop; another app's VPN is a takeover`() {
        assertFalse(anotherVpn(emptyList(), us))
        assertFalse(anotherVpn(listOf(us), us))
        assertTrue(anotherVpn(listOf(us, -1), us))
        assertTrue(anotherVpn(listOf(-1), us))
        assertFalse(anotherVpn(listOf("VPN:com.shikoonet.app"), "VPN:com.shikoonet.app"))
        assertTrue(anotherVpn(listOf("VPN:com.follow.clash"), "VPN:com.shikoonet.app"))
    }

    @Test
    fun `a takeover is waited for a few seconds, then given up`() = runTest {
        var checks = 0
        assertTrue(appears(TAKEOVER_MILLIS) { ++checks == 3 })
        assertEquals(1_000L, currentTime)

        assertFalse(appears(TAKEOVER_MILLIS) { false })
        assertEquals(1_000L + TAKEOVER_MILLIS, currentTime)
    }
}
