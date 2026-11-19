package hu.rekreta.rekreta_app.wear.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets

data class CachedWearData(
    val dateKey: String,
    val syncedAtEpochMs: Long,
    val lessons: List<Lesson>,
    val homeworks: List<Homework>,
    val grades: List<Grade>,
    val studentName: String? = null,
    val studentUid: String? = null,
    val instituteName: String? = null,
    val instituteCode: String? = null,
    val schoolYearUid: String? = null,
    val userName: String? = null,
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

    fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long = System.currentTimeMillis(),
        studentName: String? = null,
        studentUid: String? = null,
        instituteName: String? = null,
        instituteCode: String? = null,
        schoolYearUid: String? = null,
        userName: String? = null,
    ) {
        saveWearDataCache(accountKey, dateKey, lessons, homeworks, grades, syncedAtEpochMs)
    }

    fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData?
    fun clearWearDataCache(accountKey: String)
}

class SecureTokenStorage(context: Context) : WearTokenStore {
    private val appContext = context.applicationContext
    private val cacheFileLock = Any()

    private val fastPrefs: SharedPreferences by lazy {
        appContext.getSharedPreferences(FAST_PREFS_FILE_NAME, Context.MODE_PRIVATE)
    }

    @Suppress("DEPRECATION")
    private val encryptedPrefs: SharedPreferences by lazy {
        runCatching {
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
        }.getOrElse {
            fastPrefs
        }
    }

    private fun cacheFile(): File? = runCatching {
        File(appContext.filesDir, CACHE_FILE_NAME)
    }.getOrNull()

    override fun loadSession(): StoredSession? {
        val raw = runCatching { encryptedPrefs.getString(KEY_SESSION, null) }.getOrNull()
            ?: fastPrefs.getString(KEY_SESSION, null)
            ?: return null
        return runCatching {
            StoredSession.fromJson(JSONObject(raw))
        }.getOrNull() ?: run {
            val fallbackRaw = fastPrefs.getString(KEY_SESSION, null) ?: return null
            runCatching { StoredSession.fromJson(JSONObject(fallbackRaw)) }.getOrNull()
        }
    }

    override fun saveSession(session: StoredSession) {
        val encoded = session.toJson().toString()
        fastPrefs.edit()
            .putString(KEY_SESSION, encoded)
            .apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .putString(KEY_SESSION, encoded)
                    .apply()
            }
        }
    }

    override fun clearSession() {
        fastPrefs.edit()
            .remove(KEY_SESSION)
            .remove(KEY_PENDING_AUTH_REQ_AT)
            .apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .remove(KEY_SESSION)
                    .remove(KEY_PENDING_AUTH_REQ_AT)
                    .apply()
            }
        }
    }

    override fun savePendingAuthRequestAtMs(epochMs: Long) {
        fastPrefs.edit()
            .putLong(KEY_PENDING_AUTH_REQ_AT, epochMs)
            .apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .putLong(KEY_PENDING_AUTH_REQ_AT, epochMs)
                    .apply()
            }
        }
    }

    override fun loadPendingAuthRequestAtMs(): Long? {
        val encryptedVal = runCatching {
            if (encryptedPrefs.contains(KEY_PENDING_AUTH_REQ_AT)) {
                encryptedPrefs.getLong(KEY_PENDING_AUTH_REQ_AT, 0L).takeIf { it > 0L }
            } else {
                null
            }
        }.getOrNull()
        if (encryptedVal != null) return encryptedVal
        if (!fastPrefs.contains(KEY_PENDING_AUTH_REQ_AT)) return null
        return fastPrefs.getLong(KEY_PENDING_AUTH_REQ_AT, 0L).takeIf { it > 0L }
    }

    override fun clearPendingAuthRequest() {
        fastPrefs.edit().remove(KEY_PENDING_AUTH_REQ_AT).apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit().remove(KEY_PENDING_AUTH_REQ_AT).apply()
            }
        }
    }

    override fun saveLastConsumedPhoneSyncMs(epochMs: Long) {
        fastPrefs.edit()
            .putLong(KEY_LAST_PHONE_SYNC_MS, epochMs)
            .apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .putLong(KEY_LAST_PHONE_SYNC_MS, epochMs)
                    .apply()
            }
        }
    }

    override fun loadLastConsumedPhoneSyncMs(): Long {
        val encryptedVal = runCatching {
            encryptedPrefs.getLong(KEY_LAST_PHONE_SYNC_MS, 0L)
        }.getOrDefault(0L)
        return if (encryptedVal > 0L) encryptedVal else fastPrefs.getLong(KEY_LAST_PHONE_SYNC_MS, 0L)
    }

    override fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long,
    ) {
        val session = loadSession()
        saveWearDataCache(
            accountKey = accountKey,
            dateKey = dateKey,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            syncedAtEpochMs = syncedAtEpochMs,
            studentName = session?.studentName,
            studentUid = session?.studentUid,
            instituteName = session?.instituteName,
            instituteCode = session?.instituteCode,
            schoolYearUid = session?.schoolYearUid,
            userName = session?.userName,
        )
    }

    override fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long,
        studentName: String?,
        studentUid: String?,
        instituteName: String?,
        instituteCode: String?,
        schoolYearUid: String?,
        userName: String?,
    ) {
        val session = loadSession()
        val payload = JSONObject().apply {
            put("accountKey", accountKey)
            put("dateKey", dateKey)
            put("syncedAtEpochMs", syncedAtEpochMs)
            put("lessons", JSONArray().apply { lessons.forEach { put(it.toJson()) } })
            put("homeworks", JSONArray().apply { homeworks.forEach { put(it.toJson()) } })
            put("grades", JSONArray().apply { grades.forEach { put(it.toJson()) } })
            put("studentName", (studentName ?: session?.studentName).orEmpty())
            put("studentUid", (studentUid ?: session?.studentUid).orEmpty())
            put("instituteName", (instituteName ?: session?.instituteName).orEmpty())
            put("instituteCode", (instituteCode ?: session?.instituteCode).orEmpty())
            put("schoolYearUid", (schoolYearUid ?: session?.schoolYearUid).orEmpty())
            put("userName", (userName ?: session?.userName).orEmpty())
        }
        val raw = payload.toString()

        fastPrefs.edit()
            .putString("$KEY_CACHE_PREFIX$accountKey", raw)
            .putString(KEY_LATEST_CACHE, raw)
            .apply()

        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .putString("$KEY_CACHE_PREFIX$accountKey", raw)
                    .putString(KEY_LATEST_CACHE, raw)
                    .apply()
            }
        }

        synchronized(cacheFileLock) {
            runCatching {
                val target = cacheFile() ?: return@runCatching
                val parent = target.parentFile
                if (parent != null && !parent.exists()) {
                    parent.mkdirs()
                }
                val temp = File(parent, "$CACHE_FILE_NAME.tmp")
                temp.writeText(raw, StandardCharsets.UTF_8)
                if (!temp.renameTo(target)) {
                    target.writeText(raw, StandardCharsets.UTF_8)
                    temp.delete()
                }
            }
        }
    }

    override fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData? {
        val directCandidates = sequenceOf(
            { fastPrefs.getString("$KEY_CACHE_PREFIX$accountKey", null) },
            { runCatching { encryptedPrefs.getString("$KEY_CACHE_PREFIX$accountKey", null) }.getOrNull() },
        )
        for (provider in directCandidates) {
            val raw = provider() ?: continue
            parseCachedWearData(raw)?.let { return it }
        }

        val fallbackCandidates = sequenceOf(
            { fastPrefs.getString(KEY_LATEST_CACHE, null) },
            { runCatching { encryptedPrefs.getString(KEY_LATEST_CACHE, null) }.getOrNull() },
            { readCacheFileText() },
        )
        for (provider in fallbackCandidates) {
            val raw = provider() ?: continue
            val json = runCatching { JSONObject(raw) }.getOrNull() ?: continue
            if (matchesAccountScope(json, accountKey)) {
                parseCachedWearDataJson(json)?.let { return it }
            }
        }
        return null
    }

    override fun clearWearDataCache(accountKey: String) {
        fastPrefs.edit()
            .remove("$KEY_CACHE_PREFIX$accountKey")
            .remove(KEY_LATEST_CACHE)
            .apply()
        runCatching {
            if (encryptedPrefs !== fastPrefs) {
                encryptedPrefs.edit()
                    .remove("$KEY_CACHE_PREFIX$accountKey")
                    .remove(KEY_LATEST_CACHE)
                    .apply()
            }
        }
        synchronized(cacheFileLock) {
            runCatching {
                cacheFile()?.delete()
            }
        }
    }

    private fun readCacheFileText(): String? = synchronized(cacheFileLock) {
        runCatching {
            val file = cacheFile() ?: return@runCatching null
            if (!file.exists()) return@runCatching null
            file.readText(StandardCharsets.UTF_8)
        }.getOrNull()
    }

    private fun matchesAccountScope(json: JSONObject, requestedKey: String): Boolean {
        if (requestedKey == "default") return true
        val storedKey = json.optString("accountKey", "").trim()
        if (storedKey.isEmpty() || storedKey == requestedKey) return true
        val requestedInst = requestedKey.substringBefore('|').trim()
        val storedInst = storedKey.substringBefore('|').trim()
        if (requestedInst.isNotEmpty() && requestedInst != "default" &&
            storedInst.equals(requestedInst, ignoreCase = true)
        ) {
            val requestedUser = requestedKey.substringAfter('|', "default").trim()
            val storedUser = storedKey.substringAfter('|', "default").trim()
            return requestedUser == "default" || storedUser == "default" || requestedUser == storedUser
        }
        return false
    }

    private fun parseCachedWearData(raw: String): CachedWearData? = runCatching {
        parseCachedWearDataJson(JSONObject(raw))
    }.getOrNull()

    private fun parseCachedWearDataJson(json: JSONObject): CachedWearData? = runCatching {
        val cachedDate = json.optString("dateKey", "")
        val lessons = (json.optJSONArray("lessons")?.toJsonObjectList() ?: emptyList())
            .map { Lesson.fromJson(it) }
            .sortedBy { it.startEpochMs }
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
            studentName = json.optString("studentName", "").trim().ifEmpty { null },
            studentUid = json.optString("studentUid", "").trim().ifEmpty { null },
            instituteName = json.optString("instituteName", "").trim().ifEmpty { null },
            instituteCode = json.optString("instituteCode", "").trim().ifEmpty { null },
            schoolYearUid = json.optString("schoolYearUid", "").trim().ifEmpty { null },
            userName = json.optString("userName", "").trim().ifEmpty { null },
        )
    }.getOrNull()

    companion object {
        private const val PREFS_FILE_NAME = "tinta_wear_secure_prefs_v1"
        private const val FAST_PREFS_FILE_NAME = "tinta_wear_fast_cache_v2"
        private const val CACHE_FILE_NAME = "wear_timetable_cache_v2.json"
        private const val KEY_SESSION = "session_v1"
        private const val KEY_PENDING_AUTH_REQ_AT = "pending_auth_req_at_v1"
        private const val KEY_LAST_PHONE_SYNC_MS = "last_phone_sync_ms_v1"
        private const val KEY_CACHE_PREFIX = "wear_cache_v1_"
        private const val KEY_LATEST_CACHE = "wear_latest_cache_v2"

        fun accountKeyFor(session: StoredSession?): String {
            if (session == null) return "default"
            val inst = session.instituteCode.trim().lowercase().ifEmpty { "default" }
            val user = (session.userName ?: "default").trim().ifEmpty { "default" }
            return "$inst|$user"
        }
    }
}
