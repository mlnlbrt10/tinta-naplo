package hu.mlnlbrt.tintanaplo.wear.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import hu.mlnlbrt.tintanaplo.wear.data.AuthSessionPayload
import hu.mlnlbrt.tintanaplo.wear.data.Exam
import hu.mlnlbrt.tintanaplo.wear.data.Grade
import hu.mlnlbrt.tintanaplo.wear.data.SecureTokenStorage
import hu.mlnlbrt.tintanaplo.wear.data.StoredSession
import hu.mlnlbrt.tintanaplo.wear.data.WearTokenStore
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncScheduler
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncWorker
import kotlinx.coroutines.CancellationException
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
    private val remoteActivityHelper: RemoteActivityHelper? by lazy {
        runCatching {
            RemoteActivityHelper(appContext, Executors.newSingleThreadExecutor())
        }.getOrNull()
    }
    private val callbackMutex = Mutex()

    private val _status = MutableStateFlow<RemoteAuthStatus>(RemoteAuthStatus.Idle)
    val status: StateFlow<RemoteAuthStatus> = _status.asStateFlow()

    private val _dashboardSyncEpoch = MutableStateFlow(0L)
    val dashboardSyncEpoch: StateFlow<Long> = _dashboardSyncEpoch.asStateFlow()

    fun startForegroundListening() {
        try {
            Wearable.getDataClient(appContext).addListener(this)
        } catch (_: Throwable) {
            // Play Services Wearable unavailable or initializing on this watch boot.
        }
        scope.launch {
            try {
                checkPendingDataItems()
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Throwable) {
            }
        }
    }

    fun stopForegroundListening() {
        try {
            Wearable.getDataClient(appContext).removeListener(this)
        } catch (_: Throwable) {
        }
    }

    suspend fun startPhoneLogin() {
        val nowMs = System.currentTimeMillis()
        runCatching { tokenStore.savePendingAuthRequestAtMs(nowMs) }
        _status.value = RemoteAuthStatus.WaitingOnPhone(
            message = "Csatlakozás a telefonhoz...",
        )

        val nodes = try {
            Wearable.getNodeClient(appContext).connectedNodes.await()
        } catch (ce: CancellationException) {
            throw ce
        } catch (_: Throwable) {
            emptyList()
        }

        val requestBytes = JSONObject().apply {
            put("requestedAtMs", nowMs)
        }.toString().toByteArray(StandardCharsets.UTF_8)

        var sentMessage = false
        val orderedNodes = nodes.sortedByDescending { it.isNearby }
        val messageClient = try {
            Wearable.getMessageClient(appContext)
        } catch (_: Throwable) {
            null
        }
        if (messageClient != null) {
            for (node in orderedNodes) {
                val sent = try {
                    messageClient.sendMessage(
                        node.id,
                        KretaSharedConfig.WEAR_MSG_REQUEST_AUTH,
                        requestBytes,
                    ).await()
                    true
                } catch (ce: CancellationException) {
                    throw ce
                } catch (_: Throwable) {
                    false
                }
                if (sent) {
                    sentMessage = true
                }
            }
        }

        val deepLinkIntent = Intent(Intent.ACTION_VIEW).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            data = Uri.parse(KretaSharedConfig.WEAR_DEEP_LINK_URI)
        }
        val targetNode = orderedNodes.firstOrNull()
        val helper = remoteActivityHelper
        val launchedPhone = if (helper != null) {
            try {
                if (targetNode != null) {
                    helper.startRemoteActivity(deepLinkIntent, targetNode.id).await()
                } else {
                    helper.startRemoteActivity(deepLinkIntent).await()
                }
                true
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Throwable) {
                false
            }
        } else {
            false
        }

        // If the phone already responded with /tinta/auth_session while the calls were in flight,
        // keep the succeeded session state intact.
        if (tokenStore.loadSession() != null || _status.value is RemoteAuthStatus.Succeeded) {
            return
        }

        checkPendingDataItems()
        if (tokenStore.loadSession() != null || _status.value is RemoteAuthStatus.Succeeded) {
            return
        }

        if (!sentMessage && !launchedPhone) {
            runCatching { tokenStore.clearPendingAuthRequest() }
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

    /**
     * Pushes a rotated KRÉTA session refreshed on the watch back to the paired
     * phone immediately via Wearable DataClient & MessageClient so the phone
     * never attempts to reuse an already-rotated single-use refresh_token.
     */
    fun pushRefreshedSessionToPhone(session: StoredSession) {
        if (session.refreshToken.isBlank() || session.instituteCode.isBlank()) return
        scope.launch {
            val nowMs = System.currentTimeMillis()
            runCatching {
                val request = PutDataMapRequest.create(WEAR_PATH_WATCH_TOKEN_SYNC).apply {
                    dataMap.putString("access_token", session.accessToken)
                    dataMap.putString("refresh_token", session.refreshToken)
                    dataMap.putString("id_token", session.idToken)
                    dataMap.putString("institute_code", session.instituteCode)
                    dataMap.putString("user_name", session.userName.orEmpty())
                    dataMap.putLong("expires_at_ms", session.expiresAtEpochMs)
                    dataMap.putLong("synced_at_ms", nowMs)
                }.asPutDataRequest().setUrgent()
                Wearable.getDataClient(appContext).putDataItem(request).await()
            }
            runCatching {
                val payload = JSONObject().apply {
                    put("accessToken", session.accessToken)
                    put("refreshToken", session.refreshToken)
                    put("idToken", session.idToken)
                    put("instituteCode", session.instituteCode)
                    put("userName", session.userName.orEmpty())
                    put("expiresAtMs", session.expiresAtEpochMs)
                    put("syncedAtMs", nowMs)
                }.toString().toByteArray(StandardCharsets.UTF_8)
                val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
                val msgClient = Wearable.getMessageClient(appContext)
                for (node in nodes) {
                    runCatching {
                        msgClient.sendMessage(node.id, WEAR_PATH_WATCH_TOKEN_SYNC, payload).await()
                    }
                }
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        try {
            for (event in dataEvents) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val path = event.dataItem.uri.path ?: continue
                if (path == KretaSharedConfig.WEAR_DATA_AUTH_SESSION) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    handleIncomingAuthSessionDataMapAsync(dataMap, fromLiveChange = true)
                } else if (path == KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC) {
                    val dataMap = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull()
                        ?: continue
                    handleIncomingDashboardDataMapAsync(dataMap)
                }
            }
        } catch (_: Throwable) {
        }
    }

    private suspend fun checkPendingDataItems() {
        checkPendingItemsAtPath(KretaSharedConfig.WEAR_DATA_AUTH_SESSION) { dataMap ->
            handleIncomingAuthSessionDataMap(dataMap, fromLiveChange = false)
        }
        checkPendingItemsAtPath(KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC) { dataMap ->
            handleIncomingDashboardMap(dashboardDataMapToMap(dataMap))
        }
    }

    private suspend fun checkPendingItemsAtPath(
        path: String,
        handler: suspend (DataMap) -> Unit,
    ) {
        val items = try {
            Wearable.getDataClient(appContext).getDataItems(
                Uri.parse("wear://*$path"),
            ).await()
        } catch (ce: CancellationException) {
            throw ce
        } catch (_: Throwable) {
            return
        }

        try {
            for (item in items) {
                val dataMap = runCatching { DataMapItem.fromDataItem(item).dataMap }.getOrNull() ?: continue
                runCatching { handler(dataMap) }
            }
        } finally {
            runCatching { items.release() }
        }
    }

    fun handleIncomingAuthSessionDataMapAsync(
        dataMap: DataMap,
        fromLiveChange: Boolean = true,
    ) {
        val values = runCatching { dataMapToMap(dataMap) }.getOrNull() ?: return
        scope.launch {
            try {
                handleIncomingAuthSessionMap(values, fromLiveChange = fromLiveChange)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Throwable) {
            }
        }
    }

    fun handleIncomingDashboardDataMapAsync(dataMap: DataMap) {
        val values = runCatching { dashboardDataMapToMap(dataMap) }.getOrNull() ?: return
        scope.launch {
            try {
                handleIncomingDashboardMap(values)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Throwable) {
            }
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

        val parsedGrades = payload.recentGradesJson?.let { Grade.fromJsonArrayString(it) }
        val parsedExams = payload.upcomingExamsJson?.let { Exam.fromJsonArrayString(it) }

        val savedSession = synchronizer.processIncomingSession(
            payload = payload,
            fromLiveChange = fromLiveChange,
        )

        val effectiveSession = savedSession ?: existingSession
        if (effectiveSession != null && (parsedGrades != null || parsedExams != null)) {
            val mergedCache = tokenStore.mergePhoneSyncedSnapshot(
                session = effectiveSession,
                grades = parsedGrades,
                exams = parsedExams,
                syncedAtEpochMs = payload.syncedAtEpochMs.takeIf { it > 0L } ?: System.currentTimeMillis(),
            )
            if (mergedCache) {
                _dashboardSyncEpoch.value = _dashboardSyncEpoch.value + 1L
            }
        }

        if (savedSession == null) {
            return@withLock
        }

        if (!fromLiveChange && existingSession == savedSession) {
            return@withLock
        }

        runCatching { KretaSyncScheduler.ensurePeriodicSync(appContext) }
        runCatching { KretaSyncScheduler.triggerImmediateSync(appContext) }
        KretaSyncWorker.requestTileUpdate(appContext)
        _status.value = RemoteAuthStatus.Succeeded(savedSession)
    }

    private suspend fun handleIncomingDashboardMap(values: Map<String, Any?>) = callbackMutex.withLock {
        val session = tokenStore.loadSession() ?: return@withLock
        val rawInst = values["institute_code"]?.toString()?.trim().orEmpty()
        if (rawInst.isNotEmpty() && !rawInst.equals(session.instituteCode, ignoreCase = true)) {
            return@withLock
        }
        val gradesRaw = values["recent_grades_json"]?.toString()
        val examsRaw = values["upcoming_exams_json"]?.toString()
        val parsedGrades = gradesRaw?.takeIf { it.isNotBlank() }?.let { Grade.fromJsonArrayString(it) }
        val parsedExams = examsRaw?.takeIf { it.isNotBlank() }?.let { Exam.fromJsonArrayString(it) }
        val syncedAt = (values["synced_at_ms"] as? Number)?.toLong()?.takeIf { it > 0L }
            ?: System.currentTimeMillis()
        if (tokenStore.mergePhoneSyncedSnapshot(
                session = session,
                grades = parsedGrades,
                exams = parsedExams,
                syncedAtEpochMs = syncedAt,
            )
        ) {
            _dashboardSyncEpoch.value = _dashboardSyncEpoch.value + 1L
        }
    }

    companion object {
        const val WEAR_PATH_WATCH_TOKEN_SYNC = "/tinta/watch_token_sync"

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
            "recent_grades_json" to dataMap.getString("recent_grades_json"),
            "upcoming_exams_json" to dataMap.getString("upcoming_exams_json"),
        )

        private fun dashboardDataMapToMap(dataMap: DataMap): Map<String, Any?> = mapOf(
            "institute_code" to dataMap.getString("institute_code"),
            "user_name" to dataMap.getString("user_name"),
            "recent_grades_json" to dataMap.getString("recent_grades_json"),
            "upcoming_exams_json" to dataMap.getString("upcoming_exams_json"),
            "synced_at_ms" to dataMap.getLong("synced_at_ms", 0L),
        )
    }
}
