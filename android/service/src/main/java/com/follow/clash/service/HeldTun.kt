package com.follow.clash.service

import java.io.Closeable

internal class HeldTun<T : Closeable>(
    private val post: (Runnable, Long) -> Unit,
    private val cancel: (Runnable) -> Unit,
) {
    private var held: T? = null
    private var taken = false
    // A countdown already running on the main thread when a start takes the VPN must not close it.
    private val release = Runnable { synchronized(this) { if (taken) null else held.also { held = null } }?.close() }

    fun holds() = synchronized(this) { held != null }

    fun hold(tun: T?) {
        cancel(release)
        val previous = synchronized(this) { held.also { held = tun } }
        previous?.close()
    }

    fun releaseIn(millis: Long) {
        synchronized(this) { taken = false }
        post(release, millis)
    }

    /** A start keeps one held however long its engine takes: the engine's own VPN or the start's failure ends it. */
    fun take(): Boolean {
        cancel(release)
        return synchronized(this) { taken = true; held != null }
    }
}
