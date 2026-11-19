package hu.mlnlbrt.tintanaplo

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class PhoneWearSessionSnapshot(
    val accessToken: String,
    val refreshToken: String,
    val idToken: String,
    val instituteCode: String,
    val userName: String,
    val expiresAtMs: Long,
    val studentName: String,
    val studentUid: String,
    val instituteName: String,
    val schoolYearUid: String,
    val forceSync: Boolean = false,
    val recentGradesJson: String? = null,
    val upcomingExamsJson: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("accessToken", accessToken)
        put("refreshToken", refreshToken)
        put("idToken", idToken)
        put("instituteCode", instituteCode)
        put("userName", userName)
        put("expiresAtMs", expiresAtMs)
        put("studentName", studentName)
        put("studentUid", studentUid)
        put("instituteName", instituteName)
        put("schoolYearUid", schoolYearUid)
        if (recentGradesJson != null) put("recentGradesJson", recentGradesJson)
        if (upcomingExamsJson != null) put("upcomingExamsJson", upcomingExamsJson)
    }

    companion object {
        fun fromJson(json: JSONObject): PhoneWearSessionSnapshot? {
            val refreshToken = json.optString("refreshToken", "").trim()
            val instituteCode = json.optString("instituteCode", "").trim()
            if (refreshToken.isEmpty() || instituteCode.isEmpty()) return null
            val grades = if (json.has("recentGradesJson") && !json.isNull("recentGradesJson")) {
                json.optString("recentGradesJson", "").takeIf { it.isNotBlank() }
            } else {
                null
            }
            val exams = if (json.has("upcomingExamsJson") && !json.isNull("upcomingExamsJson")) {
                json.optString("upcomingExamsJson", "").takeIf { it.isNotBlank() }
            } else {
                null
            }
            return PhoneWearSessionSnapshot(
                accessToken = json.optString("accessToken", "").trim(),
                refreshToken = refreshToken,
                idToken = json.optString("idToken", ""),
                instituteCode = instituteCode,
                userName = json.optString("userName", "").trim(),
                expiresAtMs = json.optLong("expiresAtMs", 0L),
                studentName = json.optString("studentName", "").trim(),
                studentUid = json.optString("studentUid", "").trim(),
                instituteName = json.optString("instituteName", "").trim(),
                schoolYearUid = json.optString("schoolYearUid", "").trim(),
                recentGradesJson = grades,
                upcomingExamsJson = exams,
            )
        }

        fun fromMethodArgs(args: Map<*, *>): PhoneWearSessionSnapshot? {
            val refreshToken = args["refreshToken"]?.toString()?.trim().orEmpty()
            val instituteCode = args["instituteCode"]?.toString()?.trim().orEmpty()
            if (refreshToken.isEmpty() || instituteCode.isEmpty()) return null
            val gradesJson = args["recentGradesJson"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            val examsJson = args["upcomingExamsJson"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            return PhoneWearSessionSnapshot(
                accessToken = args["accessToken"]?.toString()?.trim().orEmpty(),
                refreshToken = refreshToken,
                idToken = args["idToken"]?.toString().orEmpty(),
                instituteCode = instituteCode,
                userName = args["userName"]?.toString()?.trim().orEmpty(),
                expiresAtMs = (args["expiresAtMs"] as? Number)?.toLong() ?: 0L,
                studentName = args["studentName"]?.toString()?.trim().orEmpty(),
                studentUid = args["studentUid"]?.toString()?.trim().orEmpty(),
                instituteName = args["instituteName"]?.toString()?.trim().orEmpty(),
                schoolYearUid = args["schoolYearUid"]?.toString()?.trim().orEmpty(),
                forceSync = (args["forceSync"] as? Boolean) ?: false,
                recentGradesJson = gradesJson,
                upcomingExamsJson = examsJson,
            )
        }
    }
}

object WearSessionBridge {
    private const val PREFS_NAME = "tinta_phone_wear_bridge_v1"
    private const val KEY_CACHED_SESSION = "cached_wear_session_v1"
    private const val KEY_LAST_SYNCED_AT = "last_wear_synced_at_v1"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingWatchAuthRequest = AtomicBoolean(false)
    private val monotonicSyncCounter = AtomicLong(0L)

    @Volatile
    private var prefsInstance: SharedPreferences? = null

    @Volatile
    private var activeAuthRequestListener: (() -> Unit)? = null

    fun registerAuthRequestListener(listener: (() -> Unit)?) {
        activeAuthRequestListener = listener
    }

    fun hasActiveListener(): Boolean = activeAuthRequestListener != null

    fun markPendingWatchAuthRequest() {
        pendingWatchAuthRequest.set(true)
    }

    fun consumePendingWatchAuthRequest(): Boolean =
        pendingWatchAuthRequest.getAndSet(false)

    fun notifyActiveFlutterAuthRequest() {
        val listener = activeAuthRequestListener ?: return
        mainHandler.post {
            activeAuthRequestListener?.let { listener.invoke() }
        }
    }

    @Suppress("DEPRECATION")
    private fun getPrefs(context: Context): SharedPreferences? {
        prefsInstance?.let { return it }
        return synchronized(this) {
            prefsInstance?.let { return it }
            val appCtx = context.applicationContext
            val created = runCatching {
                val masterKey = MasterKey.Builder(appCtx)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    appCtx,
                    PREFS_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            }.getOrNull()
            prefsInstance = created
            created
        }
    }

    private fun mergeDashboardMetadataFromCache(
        context: Context,
        snapshot: PhoneWearSessionSnapshot,
    ): PhoneWearSessionSnapshot {
        val prev = loadCachedSession(context) ?: return snapshot
        val sameAccount = prev.instituteCode.equals(snapshot.instituteCode, ignoreCase = true) &&
            (prev.userName.isEmpty() || snapshot.userName.isEmpty() || prev.userName == snapshot.userName)
        if (!sameAccount) return snapshot
        return snapshot.copy(
            recentGradesJson = snapshot.recentGradesJson ?: prev.recentGradesJson,
            upcomingExamsJson = snapshot.upcomingExamsJson ?: prev.upcomingExamsJson,
        )
    }

    fun cacheSession(context: Context, snapshot: PhoneWearSessionSnapshot) {
        val merged = mergeDashboardMetadataFromCache(context, snapshot)
        runCatching {
            getPrefs(context)?.edit()
                ?.putString(KEY_CACHED_SESSION, merged.toJson().toString())
                ?.apply()
        }
    }

    fun loadCachedSession(context: Context): PhoneWearSessionSnapshot? {
        val raw = runCatching {
            getPrefs(context)?.getString(KEY_CACHED_SESSION, null)
        }.getOrNull() ?: return null
        return runCatching {
            PhoneWearSessionSnapshot.fromJson(JSONObject(raw))
        }.getOrNull()
    }

    fun clearSession(context: Context) {
        runCatching {
            getPrefs(context)?.edit()
                ?.remove(KEY_CACHED_SESSION)
                ?.apply()
        }
        runCatching {
            val client = Wearable.getDataClient(context.applicationContext)
            client.deleteDataItems(Uri.parse("wear://*${KretaSharedConfig.WEAR_DATA_AUTH_SESSION}"))
            client.deleteDataItems(Uri.parse("wear://*${KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC}"))
        }
    }

    fun pushSessionToWatch(
        context: Context,
        snapshot: PhoneWearSessionSnapshot,
        onComplete: ((Boolean) -> Unit)? = null,
    ) {
        val appCtx = context.applicationContext
        val merged = mergeDashboardMetadataFromCache(appCtx, snapshot)
        cacheSession(appCtx, merged)

        val nowMs = nextMonotonicTimestampMs()
        val request = PutDataMapRequest.create(KretaSharedConfig.WEAR_DATA_AUTH_SESSION).apply {
            dataMap.putString("access_token", merged.accessToken)
            dataMap.putString("refresh_token", merged.refreshToken)
            dataMap.putString("id_token", merged.idToken)
            dataMap.putString("institute_code", merged.instituteCode)
            dataMap.putString("user_name", merged.userName)
            dataMap.putLong("expires_at_ms", merged.expiresAtMs)
            dataMap.putString("student_name", merged.studentName)
            dataMap.putString("student_uid", merged.studentUid)
            dataMap.putString("institute_name", merged.instituteName)
            dataMap.putString("school_year_uid", merged.schoolYearUid)
            dataMap.putBoolean("force_sync", merged.forceSync)
            dataMap.putLong("synced_at_ms", nowMs)
            merged.recentGradesJson?.let { dataMap.putString("recent_grades_json", it) }
            merged.upcomingExamsJson?.let { dataMap.putString("upcoming_exams_json", it) }
        }.asPutDataRequest().setUrgent()

        runCatching {
            Wearable.getDataClient(appCtx)
                .putDataItem(request)
                .addOnSuccessListener {
                    runCatching {
                        getPrefs(appCtx)?.edit()?.putLong(KEY_LAST_SYNCED_AT, nowMs)?.apply()
                    }
                    onComplete?.invoke(true)
                }
                .addOnFailureListener {
                    onComplete?.invoke(false)
                }
        }.onFailure {
            onComplete?.invoke(false)
        }
    }

    fun pushDashboardToWatch(
        context: Context,
        snapshot: PhoneWearSessionSnapshot,
        onComplete: ((Boolean) -> Unit)? = null,
    ) {
        val appCtx = context.applicationContext
        val merged = mergeDashboardMetadataFromCache(appCtx, snapshot)
        cacheSession(appCtx, merged)

        val nowMs = nextMonotonicTimestampMs()
        val request = PutDataMapRequest.create(KretaSharedConfig.WEAR_DATA_DASHBOARD_SYNC).apply {
            dataMap.putString("institute_code", merged.instituteCode)
            dataMap.putString("user_name", merged.userName)
            dataMap.putLong("synced_at_ms", nowMs)
            dataMap.putString("recent_grades_json", merged.recentGradesJson ?: "[]")
            dataMap.putString("upcoming_exams_json", merged.upcomingExamsJson ?: "[]")
        }.asPutDataRequest().setUrgent()

        runCatching {
            Wearable.getDataClient(appCtx)
                .putDataItem(request)
                .addOnSuccessListener {
                    runCatching {
                        getPrefs(appCtx)?.edit()?.putLong(KEY_LAST_SYNCED_AT, nowMs)?.apply()
                    }
                    onComplete?.invoke(true)
                }
                .addOnFailureListener {
                    onComplete?.invoke(false)
                }
        }.onFailure {
            onComplete?.invoke(false)
        }
    }

    fun pushCachedSessionIfAvailable(context: Context): Boolean {
        val cached = loadCachedSession(context) ?: return false
        pushSessionToWatch(context, cached.copy(forceSync = true))
        return true
    }

    fun getConnectionStatus(
        context: Context,
        onResult: (Map<String, Any?>) -> Unit,
    ) {
        val appCtx = context.applicationContext
        val lastSynced = runCatching {
            getPrefs(appCtx)?.getLong(KEY_LAST_SYNCED_AT, 0L) ?: 0L
        }.getOrDefault(0L)
        val lastSyncedValue: Long? = lastSynced.takeIf { it > 0L }

        runCatching {
            Wearable.getNodeClient(appCtx).connectedNodes
                .addOnSuccessListener { nodes ->
                    val ordered = nodes.sortedByDescending { it.isNearby }
                    val nodeList = ordered.map { node ->
                        mapOf(
                            "id" to node.id,
                            "displayName" to node.displayName,
                            "isNearby" to node.isNearby,
                        )
                    }
                    onResult(
                        mapOf(
                            "isConnected" to ordered.isNotEmpty(),
                            "nodes" to nodeList,
                            "primaryNodeName" to ordered.firstOrNull()?.displayName,
                            "lastSyncedAtMs" to lastSyncedValue,
                        ),
                    )
                }
                .addOnFailureListener {
                    onResult(
                        mapOf(
                            "isConnected" to false,
                            "nodes" to emptyList<Map<String, Any?>>(),
                            "primaryNodeName" to null,
                            "lastSyncedAtMs" to lastSyncedValue,
                        ),
                    )
                }
        }.onFailure {
            onResult(
                mapOf(
                    "isConnected" to false,
                    "nodes" to emptyList<Map<String, Any?>>(),
                    "primaryNodeName" to null,
                    "lastSyncedAtMs" to lastSyncedValue,
                ),
            )
        }
    }

    private fun nextMonotonicTimestampMs(): Long {
        while (true) {
            val prev = monotonicSyncCounter.get()
            val candidate = maxOf(System.currentTimeMillis(), prev + 1L)
            if (monotonicSyncCounter.compareAndSet(prev, candidate)) {
                return candidate
            }
        }
    }
}
