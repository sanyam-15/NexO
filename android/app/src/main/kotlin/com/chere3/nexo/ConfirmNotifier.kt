package com.chere3.nexo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build

/**
 * Posts the interactive "¿Registrar movimiento?" notification with Sí/No
 * actions. "Sí" launches [ConfirmBiometricActivity] — a transparent host that
 * shows only the fingerprint prompt over the shade (the app never opens); on
 * success the decision is recorded and the app materializes the transaction on
 * its next run. "No" just dismisses via [ConfirmActionReceiver].
 *
 * Styled to stand out: high-importance heads-up channel, accent color, the app
 * logo as the large icon, and the amount up front.
 */
object ConfirmNotifier {
    // Bumped id so the richer channel settings (heads-up + vibration) apply even
    // over an install that created the previous channel.
    const val CHANNEL_ID = "nexo_capture_confirm_v2"
    const val ACTION_CONFIRM = "com.chere3.nexo.CAPTURE_CONFIRM"
    const val ACTION_DISMISS = "com.chere3.nexo.CAPTURE_DISMISS"
    const val EXTRA_ID = "capture_id"
    const val EXTRA_NOTIF_ID = "notif_id"
    const val EXTRA_SUBTITLE = "subtitle"

    private val ACCENT = 0xFF10B981.toInt() // emerald

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Confirmar movimientos",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Confirma con tu huella los movimientos detectados en notificaciones"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 200, 120, 200)
            enableLights(true)
            lightColor = ACCENT
            setShowBadge(true)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun notifId(captureId: String): Int = (captureId.hashCode() and 0x7FFFFFFF)

    private fun money(amount: Double?): String? = amount?.let { "$%,.2f".format(it) }

    fun post(ctx: Context, captureId: String, appName: String, amount: Double?, last4: String?) {
        ensureChannel(ctx)
        val mgr = ctx.getSystemService(NotificationManager::class.java) ?: return
        val nId = notifId(captureId)

        val amountStr = money(amount)
        val card = if (last4 != null) " · ••$last4" else ""
        val title = if (amountStr != null) "💳 ¿Registrar $amountStr?" else "💳 ¿Registrar movimiento?"
        val line = "$appName$card"
        val big = "$line\nToca \"Sí\" y confirma con tu huella."
        val subtitle = if (amountStr != null) "$amountStr · $appName" else appName

        val confirmPi = confirmActivityIntent(ctx, captureId, nId, subtitle)
        val dismissPi = dismissBroadcast(ctx, captureId, nId)

        val statIcon = Icon.createWithResource(ctx, R.drawable.ic_stat_nexo)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_nexo)
            .setLargeIcon(Icon.createWithResource(ctx, ctx.applicationInfo.icon))
            .setColor(ACCENT)
            .setContentTitle(title)
            .setContentText(line)
            .setSubText("Nexo · AutoCaptura")
            .setStyle(Notification.BigTextStyle().bigText(big))
            .setCategory(Notification.CATEGORY_RECOMMENDATION)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setShowWhen(true)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(statIcon, "Sí, registrar", confirmPi).build())
            .addAction(Notification.Action.Builder(statIcon, "No", dismissPi).build())
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    @Suppress("DEPRECATION")
                    setPriority(Notification.PRIORITY_HIGH)
                }
            }
            .build()

        mgr.notify(nId, notification)
    }

    private fun confirmActivityIntent(ctx: Context, captureId: String, nId: Int, subtitle: String): PendingIntent {
        val intent = Intent(ctx, ConfirmBiometricActivity::class.java).apply {
            action = ACTION_CONFIRM
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            putExtra(EXTRA_ID, captureId)
            putExtra(EXTRA_NOTIF_ID, nId)
            putExtra(EXTRA_SUBTITLE, subtitle)
        }
        return PendingIntent.getActivity(ctx, nId, intent, immutableFlags())
    }

    private fun dismissBroadcast(ctx: Context, captureId: String, nId: Int): PendingIntent {
        val intent = Intent(ctx, ConfirmActionReceiver::class.java).apply {
            action = ACTION_DISMISS
            putExtra(EXTRA_ID, captureId)
            putExtra(EXTRA_NOTIF_ID, nId)
        }
        return PendingIntent.getBroadcast(ctx, nId + 1, intent, immutableFlags())
    }

    private fun immutableFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return flags
    }
}
