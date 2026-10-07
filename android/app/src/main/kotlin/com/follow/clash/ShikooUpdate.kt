package com.follow.clash

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** The in-app update's install step (docs/app-update.md), for `lib/shikoo/engine/update.dart`. */
object ShikooUpdate {
    fun attach(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "shikoo/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Below Android 8 one Unknown sources switch covers every app.
                    "canInstall" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            activity.packageManager.canRequestPackageInstalls()
                        } else {
                            @Suppress("DEPRECATION")
                            Settings.Secure.getInt(
                                activity.contentResolver,
                                Settings.Secure.INSTALL_NON_MARKET_APPS,
                                0,
                            ) == 1
                        }
                    )

                    "openInstallSettings" -> result.success(
                        start(activity) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    "package:${activity.packageName}".toUri(),
                                )
                            } else {
                                Intent(Settings.ACTION_SECURITY_SETTINGS)
                            }
                        }
                    )

                    "install" -> result.success(
                        start(activity) {
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    FileProvider.getUriForFile(
                                        activity,
                                        "${activity.packageName}.update",
                                        File(call.arguments as String),
                                    ),
                                    "application/vnd.android.package-archive",
                                )
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            }
                        }
                    )

                    else -> result.notImplemented()
                }
            }
    }

    /** False when nothing handles it (some TV builds) or the file is outside `update_paths.xml`. */
    private fun start(activity: Activity, intent: () -> Intent): Boolean = try {
        activity.startActivity(intent())
        true
    } catch (_: Exception) {
        false
    }
}
