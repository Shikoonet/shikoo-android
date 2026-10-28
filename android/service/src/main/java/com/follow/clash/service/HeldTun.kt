package com.follow.clash.service

import java.io.Closeable

internal class HeldTun<T : Closeable>(
    private val post: (Runnable, Long) -> Unit,
    private val cancel: (Runnable) -> Unit,
) {
    private var held: T? = null
    private val release = Runnable { hold(null) }

    fun holds() = synchronized(this) { held != null }

    fun hold(tun: T?) {
        cancel(release)
        val previous = synchronized(this) { held.also { held = tun } }
        previous?.close()
    }

    fun releaseIn(millis: Long) = post(release, millis)

    /** A start keeps one held however long its engine takes: the engine's own VPN or the start's failure ends it. */
    fun take(): Boolean {
        cancel(release)
        return holds()
    }
}
