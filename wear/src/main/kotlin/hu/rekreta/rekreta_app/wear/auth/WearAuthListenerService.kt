package hu.rekreta.rekreta_app.wear.auth

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import hu.rekreta.rekreta_app.shared.KretaSharedConfig

/**
 * Background WearableListenerService receiving KRÉTA session handoff items
 * pushed by the paired phone app over `/tinta/auth_session`.
 */
class WearAuthListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val manager = WearRemoteAuthManager.getInstance(applicationContext)
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION
            ) {
                val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                manager.handleIncomingAuthSessionDataMapAsync(dataMap, fromLiveChange = true)
            }
        }
    }
}
