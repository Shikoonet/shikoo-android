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
    fun `no traffic, a refusal, a removal and an ending head up even right after a drop`() {
        val kinds = listOf("noTraffic", "refused", "removed", "ended")
        kinds.forEach { assertFalse(it, quietKind(it, at, at)) }
        assertTrue(quietKind(ALERT_DROPPED, at, at))
    }

    @Test
    fun `Don't show again writes the switch Dart reads, under the plugin's prefix`() {
        assertEquals("flutter.shikoo.alerts.noTraffic", muteKey("noTraffic"))
        assertEquals("flutter.shikoo.alerts.$ALERT_DROPPED", muteKey(ALERT_DROPPED))
    }

    @Test
    fun `no VPN, or only ours going down, is the customer's own stop, and another app's VPN a takeover`() {
        assertFalse(anotherVpn(emptyList(), us))
        assertFalse(anotherVpn(listOf(us), us))
        assertTrue(anotherVpn(listOf(us, -1), us))
        assertTrue(anotherVpn(listOf(-1), us))
    }

    private val unread: () -> List<Int> = { error("owners are read from Android 10 only") }
    private val blind: () -> Boolean = { error("a bare VPN check is for below Android 10") }

    @Test
    fun `below Android 10, up to API 28, any VPN up is a takeover and no owner is read`() {
        for (sdk in listOf(25, 28)) {
            assertTrue("$sdk", takeoverSeen(sdk, unread, us) { true })
            assertFalse("$sdk", takeoverSeen(sdk, unread, us) { false })
        }
    }

    @Test
    fun `from Android 10, API 29, only another app's owner is a takeover and no bare check is made`() {
        for (sdk in listOf(29, 30)) {
            assertTrue("$sdk", takeoverSeen(sdk, { listOf(us, -1) }, us, blind))
            assertFalse("$sdk", takeoverSeen(sdk, { listOf(us) }, us, blind))
            assertFalse("$sdk", takeoverSeen(sdk, { emptyList() }, us, blind))
        }
    }

    @Test
    fun `the revoke alert is on until Dart's own switch for it is turned off, and no other switch turns it off`() {
        val stored = mutableMapOf<String, Boolean>()
        val read = { key: String, default: Boolean -> stored[key] ?: default }
        assertTrue(alertOn(ALERT_DROPPED, read))
        stored[muteKey("noTraffic")] = false
        assertTrue(alertOn(ALERT_DROPPED, read))
        stored[muteKey(ALERT_DROPPED)] = false
        assertFalse(alertOn(ALERT_DROPPED, read))
        assertFalse(alertOn("noTraffic", read))
    }

    @Test
    fun `nothing is posted while the app is on screen, and what the post says is what comes back`() {
        var posts = 0
        assertFalse(postOffScreen(true) { posts++; true })
        assertEquals(0, posts)
        assertTrue(postOffScreen(false) { posts++; true })
        assertFalse(postOffScreen(false) { posts++; false })
        assertEquals(2, posts)
    }

    @Test
    fun `a takeover is waited for ten seconds, then given up`() = runTest {
        assertEquals(10_000L, TAKEOVER_MILLIS)
        var checks = 0
        assertTrue(appears(TAKEOVER_MILLIS) { ++checks == 3 })
        assertEquals(1_000L, currentTime)

        assertFalse(appears(TAKEOVER_MILLIS) { false })
        assertEquals(11_000L, currentTime)
    }
}
