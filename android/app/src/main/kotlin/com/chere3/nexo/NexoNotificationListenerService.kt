package com.chere3.nexo

import android.app.Notification
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads notifications from bank/fintech apps and records them into
 * [CaptureStore]. Money is NOT turned into a transaction here — that happens
 * deterministically in Dart when the app next runs.
 *
 * Two sources, gated by the user's settings:
 *  - Allowlisted apps (always observed when enabled). These can trigger the
 *    one-tap confirm notification because they map to a known account.
 *  - Discovery: when on, apps NOT in the allowlist whose text strongly looks
 *    financial (currency-anchored amount + a movement verb, excluding common
 *    messaging/social apps) are buffered for IN-APP review only — never
 *    auto-confirmed, since their account/category aren't known yet.
 */
class NexoNotificationListenerService : NotificationListenerService() {

    // Common non-financial apps to never inspect in discovery mode (chat/SMS/
    // mail/social) — avoids surfacing OTPs or personal messages.
    private val discoveryDenylist = setOf(
        "com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger", "com.facebook.orca",
        "com.facebook.katana", "com.instagram.android", "com.google.android.gm",
        "com.google.android.apps.messaging", "com.android.mms", "com.samsung.android.messaging",
        "com.android.dialer", "com.google.android.dialer", "com.discord", "com.snapchat.android",
        "com.twitter.android", "com.linkedin.android", "com.slack",
    )

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Defensive rebind reconcile — bindings can be torn down by OEM battery
        // managers / app updates without auto-rebinding.
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, NexoNotificationListenerService::class.java)
            )
        } catch (e: Exception) {
            // best-effort
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, NexoNotificationListenerService::class.java)
            )
        } catch (e: Exception) {
            // best-effort
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val pkg = notification.packageName ?: return
        val ctx = applicationContext
        if (pkg == ctx.packageName) return // never capture our own

        val allowlisted = CaptureStore.allowlist(ctx).contains(pkg)
        val discovery = CaptureStore.discoveryEnabled(ctx)
        if (!allowlisted && !discovery) return // unknown app, discovery off → ignore
        if (!allowlisted && pkg in discoveryDenylist) return // never inspect chat/SMS/mail

        // Skip group summaries (duplicate child text) and ongoing/persistent ones.
        val flags = notification.notification?.flags ?: 0
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = notification.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        val raw = listOf(title, text).filter { !it.isNullOrBlank() }.joinToString(". ")

        // Discovery (unknown app): only act on strongly financial-looking text.
        if (!allowlisted && !CaptureParser.looksFinancial(raw)) return

        val amount = CaptureParser.parseAmount(raw)
        val last4 = CaptureParser.parseCardLast4(raw)
        val direction = CaptureParser.parseDirection(raw)
        val appName = appLabel(ctx, pkg)
        val id = CaptureStore.stableId(pkg, notification.key, notification.postTime, title, text)

        CaptureStore.add(ctx, id, pkg, appName, title, text, notification.postTime, notification.key, amount, last4, direction)

        // Interactive confirm notification: ONLY for allowlisted apps with an
        // unrecognized format, and ONLY on Android 12+ where the action can be
        // gated behind system authentication (fingerprint). Discovered apps stay
        // review-only (their account isn't known); older Android stays review-only
        // (we won't write money from a one-tap with no auth).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        if (!CaptureStore.confirmNotifyEnabled(ctx)) return
        if (!allowlisted) return
        if (amount == null) return
        if (CaptureParser.isRecognized(raw)) return // recognized format → silent inbox
        if (CaptureStore.wasNotified(ctx, id)) return

        CaptureStore.markNotified(ctx, id)
        ConfirmNotifier.post(ctx, id, appName, amount, last4)
    }

    private fun appLabel(ctx: android.content.Context, pkg: String): String {
        return try {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            pkg
        } catch (e: Exception) {
            pkg
        }
    }
}
