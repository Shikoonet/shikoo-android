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
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            activity.packageManager.canRequestPackageInstalls()
                    )

                    "openInstallSettings" -> result.success(
                        start(activity) {
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                "package:${activity.packageName}".toUri(),
                            )
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
