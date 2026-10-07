package com.follow.clash

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import com.follow.clash.common.GlobalState
import com.follow.clash.plugins.MainThreadResult
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

/**
 * What `lib/shikoo/engine/diag.dart` cannot see from Dart (docs/app-diagnostics.md): crashes and
 * events while no Dart runs, exit records, SIMs, power, own logcat and the Flutter surface's pixels.
 * The files here are written raw and cleaned by Dart when read.
 */
object ShikooDiag {
    private const val ALIVE_MILLIS = 5 * 60_000L
    private val main = Handler(Looper.getMainLooper())
    private lateinit var dir: File

    fun install(app: Application) {
        dir = File(app.filesDir, "shikoo").apply { mkdirs() }
        Thread.setDefaultUncaughtExceptionHandler(
            crashHandler(File(dir, "java-crash.txt"), Thread.getDefaultUncaughtExceptionHandler()),
        )
        // attachBaseContext runs before the Application is fully made; receivers wait for it.
        main.post { listen(app) }
    }

    @Synchronized
    fun event(text: String) {
        runCatching { appendCapped(File(dir, "events.txt"), "${System.currentTimeMillis()} $text\n") }
    }

    private fun listen(app: Application) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = event(
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> "screen on"
                    Intent.ACTION_SCREEN_OFF -> "screen off"
                    else -> if (intent.getBooleanExtra("state", false)) "airplane on" else "airplane off"
                },
            )
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED)
        }
        ContextCompat.registerReceiver(app, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) alive()
    }

    /** No exit records below API 30: the last «alive» bounds when the process died. */
    private fun alive() {
        if (ServiceController.getRunTimeMillis() != 0L) event("alive")
        main.postDelayed(::alive, ALIVE_MILLIS)
    }

    fun attach(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "shikoo/diag")
            .setMethodCallHandler { call, raw ->
                val result = MainThreadResult(raw)
                when (call.method) {
                    "screen" -> screen(activity, result)
                    "state" -> result.success(runCatching { state(activity) }.getOrNull())
                    "exits", "renderer", "logTail" -> GlobalState.launch(Dispatchers.IO) {
                        result.success(
                            runCatching {
                                when (call.method) {
                                    "exits" -> exits(activity, (call.arguments as Number).toLong())
                                    "renderer" -> logcat("--pid=${Process.myPid()}", "-s", "flutter:I")
                                        .lastOrNull { "rendering backend" in it }

                                    else -> logcat("-s", "FlClash:V").takeLast(100).joinToString("\n")
                                }
                            }.getOrNull(),
                        )
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun logcat(vararg filter: String): List<String> =
        ProcessBuilder(listOf("logcat", "-d", *filter)).start().inputStream.bufferedReader().readLines()

    private fun exits(context: Context, since: Long): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(ActivityManager::class.java)
        return manager.getHistoricalProcessExitReasons(context.packageName, 0, 0)
            .filter { it.timestamp > since && it.processName == context.packageName }
            .map {
                mapOf(
                    "reason" to it.reason,
                    "status" to it.status,
                    "time" to it.timestamp,
                    "description" to it.description,
                    "pss" to it.pss,
                    "rss" to it.rss,
                    "trace" to if (it.reason == ApplicationExitInfo.REASON_ANR) {
                        runCatching {
                            it.traceInputStream?.bufferedReader()?.useLines(::mainThreadBlock)
                        }.getOrNull()
                    } else {
                        null
                    },
                )
            }
    }

    private fun state(context: Context): Map<String, Any?> {
        val resolver = context.contentResolver
        val net = context.getSystemService(ConnectivityManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        @Suppress("DEPRECATION")
        val dns = net.allNetworks
            .filter { net.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == false }
            .firstNotNullOfOrNull(net::getLinkProperties)
        return mapOf(
            "airplane" to (Settings.Global.getInt(resolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1),
            "simSlots" to runCatching { slotCount(context) }.getOrNull(),
            "sims" to runCatching { sims(context) }.getOrNull(),
            "privateDns" to when {
                Build.VERSION.SDK_INT < Build.VERSION_CODES.P || dns == null -> null
                !dns.isPrivateDnsActive -> "off"
                dns.privateDnsServerName != null -> "strict"
                else -> "on"
            },
            "dataSaver" to net.restrictBackgroundStatus,
            "batterySaver" to power.isPowerSaveMode,
            "idle" to power.isDeviceIdleMode,
            "ignoresOptimizations" to power.isIgnoringBatteryOptimizations(context.packageName),
            "backgroundRestricted" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.getSystemService(ActivityManager::class.java).isBackgroundRestricted
            } else {
                null
            },
            "standbyBucket" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.getSystemService(UsageStatsManager::class.java).appStandbyBucket
            } else {
                null
            },
            // Hidden setting: readable on some builds only.
            "navigation" to runCatching { Settings.Secure.getInt(resolver, "navigation_mode") }.getOrNull(),
        )
    }

    @Suppress("DEPRECATION")
    private fun slotCount(context: Context): Int? {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) return 0
        val phone = context.getSystemService(TelephonyManager::class.java) ?: return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) phone.activeModemCount else phone.phoneCount
    }

    /** Below API 29 no call maps a slot to its SIM: only the data SIM and the default voice SIM. */
    private fun sims(context: Context): List<Map<String, Any?>> {
        val count = slotCount(context) ?: return emptyList()
        if (count == 0) return emptyList()
        val phone = context.getSystemService(TelephonyManager::class.java)
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            SubscriptionManager.getActiveDataSubscriptionId()
        } else {
            SubscriptionManager.getDefaultDataSubscriptionId()
        }
        val ids: List<Pair<Int?, Int>> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            (0 until count).mapNotNull { slot -> subscriptionOf(context, slot)?.let { slot to it } }
        } else {
            listOf(data, SubscriptionManager.getDefaultVoiceSubscriptionId())
                .filter { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID }
                .distinct()
                .map { null to it }
        }
        return ids.map { (slot, id) ->
            val sim = phone.createForSubscriptionId(id)
            mapOf(
                "slot" to slot,
                "network" to sim.networkOperatorName,
                "networkCode" to sim.networkOperator,
                "sim" to sim.simOperatorName,
                "simCode" to sim.simOperator,
                "data" to (id == data),
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun subscriptionOf(context: Context, slot: Int): Int? {
        val id = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            SubscriptionManager.getSubscriptionId(slot)
        } else {
            context.getSystemService(SubscriptionManager::class.java)?.getSubscriptionIds(slot)?.firstOrNull()
        }
        return id?.takeIf { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID }
    }

    /** What Flutter actually put on the window, at one pixel per dp as the Dart `app` image. */
    private fun screen(activity: Activity, result: MethodChannel.Result) {
        val view = surfaceOf(activity.window.decorView)
        if (view == null || view.width == 0 || view.height == 0) return result.success(null)
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        val density = activity.resources.displayMetrics.density
        PixelCopy.request(view, bitmap, { code ->
            if (code != PixelCopy.SUCCESS) return@request result.success(null)
            GlobalState.launch(Dispatchers.Default) {
                val png = runCatching {
                    val scaled = Bitmap.createScaledBitmap(
                        bitmap,
                        (bitmap.width / density).roundToInt().coerceAtLeast(1),
                        (bitmap.height / density).roundToInt().coerceAtLeast(1),
                        true,
                    )
                    ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        .toByteArray()
                }.getOrNull()
                result.success(png)
            }
        }, main)
    }

    private fun surfaceOf(view: View): FlutterSurfaceView? = when (view) {
        is FlutterSurfaceView -> view
        is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { surfaceOf(view.getChildAt(it)) }
        else -> null
    }
}

internal fun crashHandler(file: File, previous: Thread.UncaughtExceptionHandler?) =
    Thread.UncaughtExceptionHandler { thread, error ->
        runCatching {
            appendCapped(file, "--- ${System.currentTimeMillis()} ${thread.name}\n${error.stackTraceToString()}")
        }
        // Android's own handler records REASON_CRASH and kills the process.
        previous?.uncaughtException(thread, error)
    }

/** Keeps the newest half once [cap] is passed, cut at a line. */
internal fun appendCapped(file: File, text: String, cap: Int = 64 * 1024) {
    file.appendText(text)
    if (file.length() > cap) file.writeText(file.readText().takeLast(cap / 2).substringAfter('\n'))
}

/** The `"main"` thread's stack in an ANR trace, which is all a report keeps of it. */
internal fun mainThreadBlock(lines: Sequence<String>): String? = lines
    .dropWhile { !it.startsWith("\"main\"") }
    .takeWhile { it.isNotBlank() }
    .joinToString("\n")
    .take(8192)
    .ifEmpty { null }
