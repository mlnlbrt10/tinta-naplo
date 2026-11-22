package hu.mlnlbrt.tintanaplo

import android.content.Intent
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import org.json.JSONObject
import java.nio.charset.StandardCharsets

/**
 * Background WearableListenerService handling:
 * 1. `/tinta/request_auth` messages from the paired Wear OS watch.
 * 2. `/tinta/watch_token_sync` messages & DataItems carrying a rotated KRÉTA
 *    `refresh_token` refreshed on the watch back into phone storage so the
 *    phone never reuses a consumed refresh token.
 */
class PhoneWearAuthListenerService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == WearSessionBridge.WEAR_PATH_WATCH_TOKEN_SYNC) {
            runCatching {
                val raw = String(messageEvent.data, StandardCharsets.UTF_8)
                val snapshot = PhoneWearSessionSnapshot.fromJson(JSONObject(raw))
                if (snapshot != null) {
                    WearSessionBridge.ingestRotatedSessionFromWatch(applicationContext, snapshot)
                }
            }
            return
        }

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
            runCatching { startActivity(intent) }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        runCatching {
            for (event in dataEvents) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val path = event.dataItem.uri.path ?: continue
                if (path != WearSessionBridge.WEAR_PATH_WATCH_TOKEN_SYNC) continue
                val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                    ?: continue
                val snapshot = PhoneWearSessionSnapshot(
                    accessToken = dataMap.getString("access_token").orEmpty().trim(),
                    refreshToken = dataMap.getString("refresh_token").orEmpty().trim(),
                    idToken = dataMap.getString("id_token").orEmpty(),
                    instituteCode = dataMap.getString("institute_code").orEmpty().trim(),
                    userName = dataMap.getString("user_name").orEmpty().trim(),
                    expiresAtMs = dataMap.getLong("expires_at_ms", 0L),
                    studentName = "",
                    studentUid = "",
                    instituteName = "",
                    schoolYearUid = "",
                )
                WearSessionBridge.ingestRotatedSessionFromWatch(applicationContext, snapshot)
            }
        }
    }
}
