package hu.mlnlbrt.tintanaplo

import android.content.Intent
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig

/**
 * Background WearableListenerService handling `/tinta/request_auth` messages from
 * the paired Wear OS watch:
 * - If the phone app already has a cached KRÉTA session, immediately pushes it
 *   over Wearable DataClient (`/tinta/auth_session`).
 * - If the phone app is not logged in (or is active in foreground), triggers
 *   MainActivity / Flutter so the phone opens its normal KRÉTA login screen and
 *   forwards the session as soon as login completes.
 */
class PhoneWearAuthListenerService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != KretaSharedConfig.WEAR_MSG_REQUEST_AUTH) {
            super.onMessageReceived(messageEvent)
            return
        }

        val pushedFromCache = WearSessionBridge.pushCachedSessionIfAvailable(applicationContext)

        if (WearSessionBridge.hasActiveListener()) {
            WearSessionBridge.markPendingWatchAuthRequest()
            WearSessionBridge.notifyActiveFlutterAuthRequest()
            return
        }

        if (!pushedFromCache) {
            WearSessionBridge.markPendingWatchAuthRequest()
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                )
                putExtra(MainActivity.EXTRA_WEAR_AUTH_REQUEST, true)
            }
            startActivity(intent)
        }
    }
}
