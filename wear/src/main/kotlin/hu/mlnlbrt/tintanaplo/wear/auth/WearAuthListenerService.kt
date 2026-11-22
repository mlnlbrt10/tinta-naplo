package hu.mlnlbrt.tintanaplo.wear.auth

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Background WearableListenerService receiving KRÉTA session, dashboard sync,
 * and explicit phone logout events over `/tinta/auth_session`,
 * `/tinta/dashboard_sync`, and `/tinta/logout`.
 */
class WearAuthListenerService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path == WearRemoteAuthManager.WEAR_MSG_LOGOUT) {
            runCatching {
                val manager = WearRemoteAuthManager.getInstance(applicationContext)
                runBlocking {
                    withTimeoutOrNull(4_000L) {
                        manager.handlePhoneLogout()
                    }
                }
            }
            return
        }
        super.onMessageReceived(messageEvent)
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        try {
            val manager = WearRemoteAuthManager.getInstance(applicationContext)
            for (event in dataEvents) {
                val path = event.dataItem.uri.path ?: continue
                if (event.type == DataEvent.TYPE_DELETED) {
                    if (path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION) {
                        runBlocking {
                            withTimeoutOrNull(4_000L) {
                                manager.handlePhoneLogout()
                            }
                        }
                    }
                    continue
                }
                if (event.type != DataEvent.TYPE_CHANGED) continue
                if (path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    runBlocking {
                        withTimeoutOrNull(4_000L) {
                            manager.handleIncomingAuthSessionDataMapBlocking(dataMap, fromLiveChange = true)
                        }
                    }
                } else if (path == KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    runBlocking {
                        withTimeoutOrNull(4_000L) {
                            manager.handleIncomingDashboardDataMapBlocking(dataMap)
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        }
    }
}
