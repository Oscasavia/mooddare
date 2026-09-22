package com.example.mooddare

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SettingsPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "welcomeSeen" -> result.success(
                    activity.getSharedPreferences("mooddare_entry", Activity.MODE_PRIVATE)
                        .getBoolean("welcome_seen", false)
                )
                "setWelcomeSeen" -> {
                    val value = call.arguments as? Boolean
                    if (value == null) {
                        result.error("invalid-preference", "Expected a boolean", null)
                        return
                    }
                    val saved = activity.getSharedPreferences("mooddare_entry", Activity.MODE_PRIVATE)
                        .edit().putBoolean("welcome_seen", value).commit()
                    if (saved) result.success(null)
                    else result.error("preference-write", "Could not save entry preference", null)
                }
                "version" -> {
                    @Suppress("DEPRECATION")
                    val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                    @Suppress("DEPRECATION")
                    val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success("${info.versionName} ($build)")
                }
                "notifications" -> {
                    val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                    } else details
                    try { activity.startActivity(intent) }
                    catch (_: ActivityNotFoundException) { activity.startActivity(details) }
                    result.success(null)
                }
                "openUrl" -> {
                    val uri = Uri.parse(call.arguments as? String ?: "")
                    if (uri.scheme != "https" && uri.scheme != "mailto") {
                        result.error("invalid-url", "Unsupported link", null)
                        return
                    }
                    val action = if (uri.scheme == "mailto") Intent.ACTION_SENDTO else Intent.ACTION_VIEW
                    activity.startActivity(Intent(action, uri))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("unavailable", "No app is available for this action", null)
        }
    }
}
