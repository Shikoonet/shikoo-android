package com.follow.clash.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.Closeable

class HeldTunTest {
    private class Tun : Closeable {
        var closed = false

        override fun close() {
            closed = true
        }
    }

    private val pending = mutableListOf<Runnable>()
    private val held = HeldTun<Tun>({ task, _ -> pending += task }, { task -> pending.remove(task) })

    private fun timePasses() = pending.toList().also { pending.clear() }.forEach(Runnable::run)

    // The verifier's switch to a dead OpenVPN server: its engine was still trying when the switch's 5 s ran out.
    @Test
    fun `a start after a switch keeps the VPN however long its engine takes`() {
        val tun = Tun()
        held.hold(tun)
        held.releaseIn(5_000)
        assertTrue(held.take())
        timePasses()
        assertFalse(tun.closed)
        assertTrue(held.holds())
    }

    @Test
    fun `a switch no start follows lets the VPN go`() {
        val tun = Tun()
        held.hold(tun)
        held.releaseIn(5_000)
        timePasses()
        assertTrue(tun.closed)
        assertFalse(held.holds())
    }

    @Test
    fun `the engine's own VPN replaces the held one`() {
        val blocking = Tun()
        held.hold(blocking)
        held.take()
        held.hold(Tun())
        assertTrue(blocking.closed)
    }
}
