package com.chere3.nexo

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the Sí/No buttons of the confirm notification. On Android 12+ the
 * "Sí" action is authentication-required, so by the time this runs for a
 * confirm the user has already passed the fingerprint/credential prompt. The
 * decision is just recorded; the app turns a "confirm" into a real transaction
 * the next time it runs. The app is never opened.
 */
class ConfirmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val ctx = context ?: return
        val i = intent ?: return
        val id = i.getStringExtra(ConfirmNotifier.EXTRA_ID) ?: return
        val notifId = i.getIntExtra(ConfirmNotifier.EXTRA_NOTIF_ID, -1)

        when (i.action) {
            ConfirmNotifier.ACTION_CONFIRM -> CaptureStore.recordDecision(ctx, id, "confirm")
            ConfirmNotifier.ACTION_DISMISS -> CaptureStore.recordDecision(ctx, id, "dismiss")
            else -> return
        }

        if (notifId != -1) {
            ctx.getSystemService(NotificationManager::class.java)?.cancel(notifId)
        }
    }
}
