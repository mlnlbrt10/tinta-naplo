package hu.rekreta.rekreta_app.wear.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import hu.rekreta.rekreta_app.shared.KretaSharedConfig
import hu.rekreta.rekreta_app.wear.data.AuthSessionPayload
import hu.rekreta.rekreta_app.wear.data.SecureTokenStorage
import hu.rekreta.rekreta_app.wear.data.StoredSession
import hu.rekreta.rekreta_app.wear.data.WearTokenStore
import hu.rekreta.rekreta_app.wear.sync.KretaSyncScheduler
import hu.rekreta.rekreta_app.wear.sync.KretaSyncWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

sealed interface RemoteAuthStatus {
    data object Idle : RemoteAuthStatus
    data class WaitingOnPhone(
        val message: String = "Nyisd meg a telefonod a csatlakozáshoz",
    ) : RemoteAuthStatus

    data object SavingSession : RemoteAuthStatus
    data class Succeeded(val session: StoredSession) : RemoteAuthStatus
    data class Error(val message: String) : RemoteAuthStatus
}

class AuthSessionSynchronizer(private val tokenStore: WearTokenStore) {
    fun processIncomingSession(
        payload: AuthSessionPayload,
        fromLiveChange: Boolean,
    ): StoredSession? {
        val lastConsumedSyncMs = tokenStore.loadLastConsumedPhoneSyncMs()
        if (!fromLiveChange &&
            payload.syncedAtEpochMs > 0L &&
            payload.syncedAtEpochMs <= lastConsumedSyncMs
        ) {
            return null
        }

        val existing = tokenStore.loadSession()
        val merged = payload.mergeInto(existing)
        tokenStore.saveSession(merged)
        if (payload.syncedAtEpochMs > 0L) {
            tokenStore.saveLastConsumedPhoneSyncMs(
                maxOf(lastConsumedSyncMs, payload.syncedAtEpochMs),
            )
        }
        tokenStore.clearPendingAuthRequest()
        return merged
    }
}

class WearRemoteAuthManager private constructor(context: Context) :
    DataClient.OnDataChangedListener {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val tokenStore = SecureTokenStorage(appContext)
    private val synchronizer = AuthSessionSynchronizer(tokenStore)
    private val remoteActivityHelper = RemoteActivityHelper(
        appContext,
        Executors.newSingleThreadExecutor(),
    )
    private val callbackMutex = Mutex()

    private val _status = MutableStateFlow<RemoteAuthStatus>(RemoteAuthStatus.Idle)
    val status: StateFlow<RemoteAuthStatus> = _status.asStateFlow()

    fun startForegroundListening() {
        Wearable.getDataClient(appContext).addListener(this)
        scope.launch {
            checkPendingAuthSessionDataItem()
        }
    }

    fun stopForegroundListening() {
        Wearable.getDataClient(appContext).removeListener(this)
    }

    suspend fun startPhoneLogin() {
        val nowMs = System.currentTimeMillis()
        tokenStore.savePendingAuthRequestAtMs(nowMs)
        _status.value = RemoteAuthStatus.WaitingOnPhone(
            message = "Csatlakozás a telefonhoz...",
        )

        val nodes = runCatching {
            Wearable.getNodeClient(appContext).connectedNodes.await()
        }.getOrDefault(emptyList())

        val requestBytes = JSONObject().apply {
            put("requestedAtMs", nowMs)
        }.toString().toByteArray(StandardCharsets.UTF_8)

        var sentMessage = false
        val orderedNodes = nodes.sortedByDescending { it.isNearby }
        val messageClient = Wearable.getMessageClient(appContext)
        for (node in orderedNodes) {
            val sent = runCatching {
                messageClient.sendMessage(
                    node.id,
                    KretaSharedConfig.WEAR_MSG_REQUEST_AUTH,
                    requestBytes,
                ).await()
            }.isSuccess
            if (sent) {
                sentMessage = true
            }
        }

        val deepLinkIntent = Intent(Intent.ACTION_VIEW).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            data = Uri.parse(KretaSharedConfig.WEAR_DEEP_LINK_URI)
        }
        val targetNode = orderedNodes.firstOrNull()
        val launchedPhone = runCatching {
            if (targetNode != null) {
                remoteActivityHelper.startRemoteActivity(deepLinkIntent, targetNode.id).await()
            } else {
                remoteActivityHelper.startRemoteActivity(deepLinkIntent).await()
            }
        }.isSuccess

        // If the phone already responded with /tinta/auth_session while the calls were in flight,
        // keep the succeeded session state intact.
        if (tokenStore.loadSession() != null || _status.value is RemoteAuthStatus.Succeeded) {
            return
        }

        checkPendingAuthSessionDataItem()
        if (tokenStore.loadSession() != null || _status.value is RemoteAuthStatus.Succeeded) {
            return
        }

        if (!sentMessage && !launchedPhone) {
            tokenStore.clearPendingAuthRequest()
            _status.value = RemoteAuthStatus.Error(
                if (nodes.isEmpty()) {
                    "Nincs csatlakoztatott telefon."
                } else {
                    "Nem sikerült megnyitni a telefont."
                },
            )
        } else {
            _status.value = RemoteAuthStatus.WaitingOnPhone(
                message = "Nyisd meg a telefonod a csatlakozáshoz",
            )
        }
    }

    fun resetStatusToIdle() {
        _status.value = RemoteAuthStatus.Idle
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION
            ) {
                val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                handleIncomingAuthSessionDataMapAsync(dataMap, fromLiveChange = true)
            }
        }
    }

    private suspend fun checkPendingAuthSessionDataItem() {
        val items = runCatching {
            Wearable.getDataClient(appContext).getDataItems(
                Uri.parse("wear://*${KretaSharedConfig.WEAR_DATA_AUTH_SESSION}"),
            ).await()
        }.getOrNull() ?: return

        try {
            for (item in items) {
                val dataMap = DataMapItem.fromDataItem(item).dataMap
                handleIncomingAuthSessionDataMap(dataMap, fromLiveChange = false)
            }
        } finally {
            items.release()
        }
    }

    fun handleIncomingAuthSessionDataMapAsync(
        dataMap: DataMap,
        fromLiveChange: Boolean = true,
    ) {
        val values = dataMapToMap(dataMap)
        scope.launch {
            handleIncomingAuthSessionMap(values, fromLiveChange = fromLiveChange)
        }
    }

    private suspend fun handleIncomingAuthSessionDataMap(
        dataMap: DataMap,
        fromLiveChange: Boolean,
    ) {
        handleIncomingAuthSessionMap(dataMapToMap(dataMap), fromLiveChange = fromLiveChange)
    }

    suspend fun handleIncomingAuthSessionMap(
        values: Map<String, Any?>,
        fromLiveChange: Boolean,
    ) = callbackMutex.withLock {
        val payload = AuthSessionPayload.fromMap(values) ?: return@withLock
        val existingSession = tokenStore.loadSession()
        val hadSession = existingSession != null
        if (!hadSession && fromLiveChange) {
            _status.value = RemoteAuthStatus.SavingSession
        }

        val savedSession = synchronizer.processIncomingSession(
            payload = payload,
            fromLiveChange = fromLiveChange,
        ) ?: return@withLock

        if (!fromLiveChange && existingSession == savedSession) {
            return@withLock
        }

        KretaSyncScheduler.ensurePeriodicSync(appContext)
        KretaSyncScheduler.triggerImmediateSync(appContext)
        KretaSyncWorker.requestTileUpdate(appContext)
        _status.value = RemoteAuthStatus.Succeeded(savedSession)
    }

    companion object {
        @Volatile
        private var instance: WearRemoteAuthManager? = null

        fun getInstance(context: Context): WearRemoteAuthManager {
            return instance ?: synchronized(this) {
                instance ?: WearRemoteAuthManager(context).also { instance = it }
            }
        }

        private fun dataMapToMap(dataMap: DataMap): Map<String, Any?> = mapOf(
            "access_token" to dataMap.getString("access_token"),
            "refresh_token" to dataMap.getString("refresh_token"),
            "id_token" to dataMap.getString("id_token"),
            "institute_code" to dataMap.getString("institute_code"),
            "user_name" to dataMap.getString("user_name"),
            "expires_at_ms" to dataMap.getLong("expires_at_ms", 0L),
            "student_name" to dataMap.getString("student_name"),
            "student_uid" to dataMap.getString("student_uid"),
            "institute_name" to dataMap.getString("institute_name"),
            "school_year_uid" to dataMap.getString("school_year_uid"),
            "synced_at_ms" to dataMap.getLong("synced_at_ms", 0L),
            "force_sync" to dataMap.getBoolean("force_sync", false),
        )
    }
}
