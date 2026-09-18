package com.chere3.nexo

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "nexo/notification_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGranted" -> result.success(isNotificationAccessGranted())
                    "openSettings" -> {
                        openNotificationAccessSettings()
                        result.success(null)
                    }
                    "setAllowlist" -> {
                        val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                        CaptureStore.setAllowlist(applicationContext, pkgs)
                        result.success(null)
                    }
                    "setFlags" -> {
                        val discovery = call.argument<Boolean>("discovery") ?: false
                        val confirmNotify = call.argument<Boolean>("confirmNotify") ?: false
                        CaptureStore.setFlags(applicationContext, discovery, confirmNotify)
                        result.success(null)
                    }
                    "drain" -> result.success(CaptureStore.drain(applicationContext))
                    "requestRebind" -> {
                        try {
                            NotificationListenerService.requestRebind(
                                ComponentName(this, NexoNotificationListenerService::class.java)
                            )
                        } catch (e: Exception) {
                            // best-effort
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Whether the user granted notification-listener access to Nexo's service. */
    private fun isNotificationAccessGranted(): Boolean {
        val flat = ComponentName(this, NexoNotificationListenerService::class.java)
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        if (enabled.isBlank()) return false
        return enabled.split(":").any { entry ->
            val cn = ComponentName.unflattenFromString(entry)
            cn != null &&
                cn.packageName == flat.packageName &&
                cn.className == flat.className
        }
    }

    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Fall back to the general settings if the listener screen is absent.
            startActivity(
                Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }
}
