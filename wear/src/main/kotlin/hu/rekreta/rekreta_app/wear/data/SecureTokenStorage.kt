package hu.rekreta.rekreta_app.wear.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

data class CachedWearData(
    val dateKey: String,
    val syncedAtEpochMs: Long,
    val lessons: List<Lesson>,
    val homeworks: List<Homework>,
    val grades: List<Grade>,
)

interface WearTokenStore {
    fun loadSession(): StoredSession?
    fun saveSession(session: StoredSession)
    fun clearSession()

    fun savePendingAuthRequestAtMs(epochMs: Long)
    fun loadPendingAuthRequestAtMs(): Long?
    fun clearPendingAuthRequest()

    fun saveLastConsumedPhoneSyncMs(epochMs: Long)
    fun loadLastConsumedPhoneSyncMs(): Long

    fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long = System.currentTimeMillis(),
    )

    fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData?
    fun clearWearDataCache(accountKey: String)
}

class SecureTokenStorage(context: Context) : WearTokenStore {
    private val appContext = context.applicationContext

    @Suppress("DEPRECATION")
    private val encryptedPrefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            appContext,
            PREFS_FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override fun loadSession(): StoredSession? {
        val raw = encryptedPrefs.getString(KEY_SESSION, null) ?: return null
        return runCatching {
            StoredSession.fromJson(JSONObject(raw))
        }.getOrNull()
    }

    override fun saveSession(session: StoredSession) {
        encryptedPrefs.edit()
            .putString(KEY_SESSION, session.toJson().toString())
            .apply()
    }

    override fun clearSession() {
        encryptedPrefs.edit()
            .remove(KEY_SESSION)
            .remove(KEY_PENDING_AUTH_REQ_AT)
            .apply()
    }

    override fun savePendingAuthRequestAtMs(epochMs: Long) {
        encryptedPrefs.edit()
            .putLong(KEY_PENDING_AUTH_REQ_AT, epochMs)
            .apply()
    }

    override fun loadPendingAuthRequestAtMs(): Long? {
        if (!encryptedPrefs.contains(KEY_PENDING_AUTH_REQ_AT)) return null
        return encryptedPrefs.getLong(KEY_PENDING_AUTH_REQ_AT, 0L).takeIf { it > 0L }
    }

    override fun clearPendingAuthRequest() {
        encryptedPrefs.edit().remove(KEY_PENDING_AUTH_REQ_AT).apply()
    }

    override fun saveLastConsumedPhoneSyncMs(epochMs: Long) {
        encryptedPrefs.edit()
            .putLong(KEY_LAST_PHONE_SYNC_MS, epochMs)
            .apply()
    }

    override fun loadLastConsumedPhoneSyncMs(): Long =
        encryptedPrefs.getLong(KEY_LAST_PHONE_SYNC_MS, 0L)

    override fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long,
    ) {
        val payload = JSONObject().apply {
            put("dateKey", dateKey)
            put("syncedAtEpochMs", syncedAtEpochMs)
            put("lessons", JSONArray().apply { lessons.forEach { put(it.toJson()) } })
            put("homeworks", JSONArray().apply { homeworks.forEach { put(it.toJson()) } })
            put("grades", JSONArray().apply { grades.forEach { put(it.toJson()) } })
        }
        encryptedPrefs.edit()
            .putString("$KEY_CACHE_PREFIX$accountKey", payload.toString())
            .apply()
    }

    override fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData? {
        val raw = encryptedPrefs.getString("$KEY_CACHE_PREFIX$accountKey", null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            val cachedDate = json.optString("dateKey", "")
            val lessons = if (cachedDate == dateKey) {
                (json.optJSONArray("lessons")?.toJsonObjectList() ?: emptyList())
                    .map { Lesson.fromJson(it) }
                    .sortedBy { it.startEpochMs }
            } else {
                emptyList()
            }
            val homeworks = (json.optJSONArray("homeworks")?.toJsonObjectList() ?: emptyList())
                .map { Homework.fromJson(it) }
            val grades = (json.optJSONArray("grades")?.toJsonObjectList() ?: emptyList())
                .map { Grade.fromJson(it) }
                .sortedByDescending { it.recordedAtEpochMs }

            CachedWearData(
                dateKey = cachedDate,
                syncedAtEpochMs = json.optLong("syncedAtEpochMs", 0L),
                lessons = lessons,
                homeworks = homeworks,
                grades = grades,
            )
        }.getOrNull()
    }

    override fun clearWearDataCache(accountKey: String) {
        encryptedPrefs.edit().remove("$KEY_CACHE_PREFIX$accountKey").apply()
    }

    companion object {
        private const val PREFS_FILE_NAME = "tinta_wear_secure_prefs_v1"
        private const val KEY_SESSION = "session_v1"
        private const val KEY_PENDING_AUTH_REQ_AT = "pending_auth_req_at_v1"
        private const val KEY_LAST_PHONE_SYNC_MS = "last_phone_sync_ms_v1"
        private const val KEY_CACHE_PREFIX = "wear_cache_v1_"

        fun accountKeyFor(session: StoredSession?): String {
            if (session == null) return "default"
            val inst = session.instituteCode.trim().ifEmpty { "default" }
            val user = (session.userName ?: "default").trim().ifEmpty { "default" }
            return "$inst|$user"
        }
    }
}
