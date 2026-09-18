package com.chere3.nexo

import android.app.NotificationManager
import android.os.Bundle
import android.widget.Toast
import androidx.biometric.BiometricManager.Authenticators
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Invisible (transparent-themed) host that shows ONLY the fingerprint/credential
 * prompt over the notification shade when the user taps "Sí, registrar". On
 * success it records the confirm decision and cancels the notification, then
 * finishes immediately — the full app never opens.
 *
 * This is launched by the confirm notification's "Sí" PendingIntent. We use an
 * explicit BiometricPrompt (not Action.setAuthenticationRequired) because the
 * latter only requires the device to be *unlocked* and shows no prompt when it
 * already is — the user wants a fingerprint on every confirmation.
 */
class ConfirmBiometricActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val id = intent.getStringExtra(ConfirmNotifier.EXTRA_ID)
        val notifId = intent.getIntExtra(ConfirmNotifier.EXTRA_NOTIF_ID, -1)
        val subtitle = intent.getStringExtra(ConfirmNotifier.EXTRA_SUBTITLE) ?: ""
        if (id == null) {
            finish()
            return
        }

        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    CaptureStore.recordDecision(applicationContext, id, "confirm")
                    if (notifId != -1) {
                        getSystemService(NotificationManager::class.java)?.cancel(notifId)
                    }
                    finish()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    // Cancellations are silent; surface hard errors (no/changed
                    // biometrics, hardware unavailable) so the capture isn't lost
                    // silently — it stays pending in the in-app inbox.
                    val cancelled = errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_CANCELED
                    if (!cancelled) {
                        Toast.makeText(
                            applicationContext,
                            "No se pudo verificar tu huella. Confírmalo en Nexo.",
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                    finish()
                }
            },
        )

        // Fingerprint-only (strong biometric). No PIN/credential fallback: the
        // notification promises "huella", and the gated decision is reversible
        // in-app, so we keep the bar at a real biometric.
        val builder = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Confirmar movimiento")
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(Authenticators.BIOMETRIC_STRONG)
            .setNegativeButtonText("Cancelar")

        try {
            prompt.authenticate(builder.build())
        } catch (e: Exception) {
            finish()
        }
    }
}
