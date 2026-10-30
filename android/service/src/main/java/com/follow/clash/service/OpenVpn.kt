package com.follow.clash.service

import androidx.annotation.Keep
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

const val OPENVPN_PROFILE = "ovpn"

/** Dart's `ShikooCore.openvpn.name`, the owner core VpnOptions names. */
const val OPENVPN_CORE = "openvpn"

/** OpenVPN 3's event, and so the start's error, when the server refused the username and password. */
const val OPENVPN_AUTH_FAILED = "AUTH_FAILED"

/** OpenVPN 3 (shikoo_ovpn3.cpp) owning the tunnel for one server; [build] makes the VPN once the server pushed it. */
@Keep
internal class OpenVpn(
    private val server: String,
    private val protector: (Int) -> Boolean,
    private val build: (String) -> Int,
) {
    data class Failure(val reason: String)

    private val session = sessions.incrementAndGet()
    private val settled = CountDownLatch(1)

    @Volatile
    private var connected = false

    @Volatile
    private var stopping = false

    @Volatile
    private var abandoned = false

    @Volatile
    private var ended: String? = null

    // A refused login ends run() without an error of its own: the event said why.
    @Volatile
    private var lastError = ""
    private var thread: Thread? = null

    fun start(profile: String, username: String, password: String, seconds: Long = CONNECT_SECONDS): Failure? {
        if (loaded.isFailure) return Failure("no engine: ${loaded.exceptionOrNull()}")
        // First, so mihomo's own client of this server is shut before ours dials (core/shikoo_owner.go).
        report(server, false)
        thread = Thread({
            ended = runCatching { run(profile, username, password) }.getOrElse { "$it" }.ifEmpty { lastError }
            report("", false)
            GlobalState.log("OpenVPN ended: ${ended?.ifEmpty { "stopped" }}")
            settled.countDown()
        }, "OpenVPN").apply { start() }
        if (!settled.await(seconds, TimeUnit.SECONDS)) return Failure("no connection in $seconds s")
        if (connected) return null
        if (abandoned) return Failure("a stop came first")
        return Failure(ended.orEmpty())
    }

    fun abandon() {
        abandoned = true
        settled.countDown()
    }

    // halt() is lost until the session takes calls from another thread, so it is repeated.
    fun stop() {
        stopping = true
        val running = thread ?: return
        repeat(STOP_TRIES) {
            if (!running.isAlive) return
            halt()
            running.join(STOP_STEP_MILLIS)
        }
        GlobalState.log("OpenVPN did not stop in time")
    }

    private fun report(server: String, up: Boolean) {
        runCatching { Core.openvpnState(session, server, up) }
            .onFailure { GlobalState.log("OpenVPN state not told to the core: $it") }
    }

    fun protect(fd: Int): Boolean = protector(fd)

    fun establish(spec: String): Int = if (stopping) -1 else runCatching { build(spec) }.getOrElse {
        GlobalState.log("OpenVPN's VPN not built: $it")
        -1
    }

    fun event(name: String, info: String, error: Boolean) {
        when (name) {
            "CONNECTED" -> {
                connected = true
                report(server, true)
                settled.countDown()
            }

            "RECONNECTING", "PAUSE", "DISCONNECTED" -> report(server, false)
        }
        if (error) lastError = "$name: $info"
        GlobalState.log(if (error) "OpenVPN $lastError" else "OpenVPN $name") // CONNECTED's info names the account
    }

    private external fun run(profile: String, username: String, password: String): String

    private external fun halt()

    companion object {
        private const val CONNECT_SECONDS = 20L
        private const val STOP_TRIES = 50
        private const val STOP_STEP_MILLIS = 200L
        private val sessions = AtomicInteger()
        private val loaded by lazy { runCatching { System.loadLibrary("ovpn3") } }
    }
}
