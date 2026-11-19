package hu.mlnlbrt.tintanaplo.wear.auth

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig

/**
 * Background WearableListenerService receiving KRÉTA session and dashboard
 * sync items pushed by the paired phone app over `/tinta/auth_session` and
 * `/tinta/dashboard_sync`.
 */
class WearAuthListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        try {
            val manager = WearRemoteAuthManager.getInstance(applicationContext)
            for (event in dataEvents) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val path = event.dataItem.uri.path ?: continue
                if (path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    manager.handleIncomingAuthSessionDataMapAsync(dataMap, fromLiveChange = true)
                } else if (path == KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    manager.handleIncomingDashboardDataMapAsync(dataMap)
                }
            }
        } catch (_: Throwable) {
        }
    }
}
