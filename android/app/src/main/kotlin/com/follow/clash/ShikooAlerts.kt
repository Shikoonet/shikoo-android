package com.follow.clash

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.net.toUri
import androidx.core.os.bundleOf
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.QuickAction
import com.follow.clash.common.quickIntent
import com.follow.clash.common.toPendingIntent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import com.follow.clash.service.R as ServiceR

internal const val ALERT_KIND = "kind"
internal const val ALERT_DROPPED = "dropped"
internal const val QUIET_MILLIS = 10 * 60_000L

// shortcut: a VPN app that comes up after 10 s is not seen, give the window longer if reports show it.
internal const val TAKEOVER_MILLIS = 10_000L

/** A drop this soon after the last one updates the alert without sound or heads-up. */
internal fun quiet(lastDropAt: Long, now: Long) = now - lastDropAt in 0 until QUIET_MILLIS

/** Only a drop is ever quiet: the other kinds are news the customer has to see. */
internal fun quietKind(kind: String, lastDropAt: Long, now: Long) =
    kind == ALERT_DROPPED && quiet(lastDropAt, now)

/** Where Dart's own switch for [kind] lives (`flutter.` is the prefix the shared_preferences plugin adds). */
internal fun muteKey(kind: String) = "flutter.shikoo.alerts.$kind"

internal fun anotherVpn(owners: List<Int>, own: Int) = owners.any { it != own }

internal fun takeoverSeen(sdk: Int, owners: () -> List<Int>, me: Int, anyVpn: () -> Boolean) =
    if (sdk >= Build.VERSION_CODES.Q) anotherVpn(owners(), me) else anyVpn()

internal fun alertOn(kind: String, read: (String, Boolean) -> Boolean) = read(muteKey(kind), true)

internal fun postOffScreen(foreground: Boolean, post: () -> Boolean) = !foreground && post()

internal suspend fun appears(within: Long, check: () -> Boolean) =
    withTimeoutOrNull(within) {
        while (!check()) delay(500)
        true
    } ?: false

/** Connection alerts for `lib/shikoo/app/alerts.dart`, one shared id; a revoke is decided here, as no Dart may run. */
class ShikooAlerts : FlutterPlugin, ActivityAware, PluginRegistry.NewIntentListener {
    private var activity: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        live = MethodChannel(binding.binaryMessenger, "shikoo/alerts").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "post" -> result.success(post(context, call.arguments as Map<*, *>))
                    "cancel" -> result.success(cancel(context, call.arguments as String))
                    "revokedAlert" -> result.success(
                        own(context).edit()
                            .putString(REVOKED, JSONObject(call.arguments as Map<*, *>).toString())
                            .commit(),
                    )

                    "target" -> result.success(pending.also { pending = null })
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        live?.setMethodCallHandler(null)
        live = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.apply { addOnNewIntentListener(this@ShikooAlerts) }
        // Dart is not listening yet: it asks for the target once it starts.
        pending = binding.activity.intent?.getStringExtra(TARGET) ?: pending
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val target = intent.getStringExtra(TARGET) ?: return false
        live?.invokeMethod("open", target)
        return true
    }

    override fun onDetachedFromActivity() {
        activity?.removeOnNewIntentListener(this)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    companion object {
        private const val CHANNEL = "shikoo_alerts"
        private const val ID = 0x5A1E
        private const val TARGET = "shikoo.alert"
        private const val REVOKED = "revoked"

        @Volatile
        internal var live: MethodChannel? = null

        @Volatile
        private var pending: String? = null

        @Volatile
        private var lastDropAt = Long.MIN_VALUE / 2
        private var reconnect: Job? = null

        /** A takeover only once another app's VPN is up: Android's own Disconnect revokes too, and is the customer's. */
        fun revoked(context: Context) {
            val alert = own(context).getString(REVOKED, null) ?: return
            if (!alertOn(ALERT_DROPPED, flutter(context)::getBoolean)) return
            reconnect?.cancel()
            val seen = takeover(context)
            reconnect = GlobalState.launch {
                if (!appears(TAKEOVER_MILLIS, seen)) return@launch
                val said = postOffScreen(inForeground()) { post(context, JSONObject(alert).plain() as Map<*, *>) }
                if (!said) return@launch
                ServiceState.runState.first { it == RunState.STOPPED }
                ServiceState.runState.first { it == RunState.STARTED }
                cancel(context, ALERT_DROPPED)
            }
        }

        @SuppressLint("MissingPermission")
        internal fun post(context: Context, alert: Map<*, *>): Boolean {
            val manager = NotificationManagerCompat.from(context)
            if (!manager.areNotificationsEnabled()) return false
            manager.createNotificationChannel(
                NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_HIGH)
                    .setName(alert["channel"] as String)
                    .build(),
            )
            val kind = alert[ALERT_KIND] as String
            val now = System.currentTimeMillis()
            val silent = quietKind(kind, lastDropAt, now)
            if (kind == ALERT_DROPPED) lastDropAt = now
            val body = alert["body"] as String
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(ServiceR.drawable.ic_service)
                .setContentTitle(alert["title"] as String)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                // Heads-up below Android 8, which has no channel importance.
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setAutoCancel(true)
                // Its own group, or Android bundles it with the VPN notification and hides its buttons.
                .setGroup(CHANNEL)
                .setSilent(silent)
                .setContentIntent(open(context, alert["tap"] as String, 0))
                .addExtras(bundleOf(ALERT_KIND to kind))
            (alert["actions"] as List<*>).forEachIndexed { i, action ->
                val (label, op) = action as List<*>
                builder.addAction(0, label as String, intentFor(context, op as String, kind, i + 1))
            }
            manager.notify(ID, builder.build())
            return true
        }

        /** Only while the alert showing is [kind]: a newer one about something else stays. */
        internal fun cancel(context: Context, kind: String): Boolean {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return false
            val shown = manager.activeNotifications.firstOrNull { it.id == ID } ?: return false
            if (shown.notification.extras.getString(ALERT_KIND) != kind) return false
            manager.cancel(ID)
            return true
        }

        private fun intentFor(context: Context, op: String, kind: String, slot: Int): PendingIntent = when {
            op == "mute" -> PendingIntent.getBroadcast(
                context,
                slot,
                Intent(context, ShikooAlertMute::class.java).putExtra(ALERT_KIND, kind),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            op == "start" -> QuickAction.START.quickIntent.toPendingIntent
            op.startsWith("url:") -> PendingIntent.getActivity(
                context,
                slot,
                Intent(Intent.ACTION_VIEW, op.removePrefix("url:").toUri())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            else -> open(context, op.removePrefix("open:"), slot)
        }

        private fun open(context: Context, target: String, slot: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                slot,
                Intent("${context.packageName}.alert")
                    .setComponent(Components.mainActivity)
                    .putExtra(TARGET, target)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    ),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        // Before Android 10 no VPN names its app (extraInfo is empty until 15); ours is gone by the revoke, so one up is another's.
        @SuppressLint("NewApi")
        private fun takeover(context: Context): () -> Boolean =
            { takeoverSeen(Build.VERSION.SDK_INT, { vpnOwners(context) }, Process.myUid()) { vpnUp(context) } }

        @RequiresApi(Build.VERSION_CODES.Q)
        private fun vpnOwners(context: Context): List<Int> {
            val manager = context.getSystemService(ConnectivityManager::class.java) ?: return emptyList()
            return manager.allNetworks.mapNotNull { vpnCaps(manager, it)?.ownerUid }
        }

        private fun vpnUp(context: Context): Boolean {
            val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
            return manager.allNetworks.any { vpnCaps(manager, it) != null }
        }

        private fun vpnCaps(manager: ConnectivityManager, network: Network) =
            manager.getNetworkCapabilities(network)?.takeIf { it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }

        private fun inForeground() = ActivityManager.RunningAppProcessInfo()
            .also(ActivityManager::getMyMemoryState)
            .importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND

        private fun own(context: Context): SharedPreferences =
            context.getSharedPreferences("shikoo_alerts", Context.MODE_PRIVATE)

        internal fun flutter(context: Context): SharedPreferences =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        private fun Any?.plain(): Any? = when (this) {
            is JSONObject -> keys().asSequence().associateWith { get(it).plain() }
            is JSONArray -> (0 until length()).map { get(it).plain() }
            else -> this
        }
    }
}

/** «دیگر نشان نده»: Dart's own switch, written here too since no Dart may be running. */
class ShikooAlertMute : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val kind = intent.getStringExtra(ALERT_KIND) ?: return
        ShikooAlerts.flutter(context).edit().putBoolean(muteKey(kind), false).apply()
        ShikooAlerts.cancel(context, kind)
        ShikooAlerts.live?.invokeMethod("muted", kind)
    }
}
