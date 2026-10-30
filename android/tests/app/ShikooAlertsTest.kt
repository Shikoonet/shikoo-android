package com.follow.clash

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShikooAlertsTest {
    private val at = 1_793_000_000_000L

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
}
