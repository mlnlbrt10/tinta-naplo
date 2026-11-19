package hu.mlnlbrt.tintanaplo.wear.data

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
    val exams: List<Exam> = emptyList(),
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
        saveWearDataCache(
            accountKey = accountKey,
            dateKey = dateKey,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            exams = emptyList(),
            syncedAtEpochMs = syncedAtEpochMs,
            studentName = studentName,
            studentUid = studentUid,
            instituteName = instituteName,
            instituteCode = instituteCode,
            schoolYearUid = schoolYearUid,
            userName = userName,
        )
    }

    fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        exams: List<Exam>,
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

    private val fastPrefs: SharedPreferences? by lazy {
        runCatching {
            appContext.getSharedPreferences(FAST_PREFS_FILE_NAME, Context.MODE_PRIVATE)
        }.getOrNull()
    }

    @Suppress("DEPRECATION")
    private val encryptedPrefs: SharedPreferences? by lazy {
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
        // Read plain SharedPreferences first so cold launch never blocks or crashes
        // on Samsung Knox / Android Keystore binder IPC on the main thread.
        val fastRaw = runCatching { fastPrefs?.getString(KEY_SESSION, null) }.getOrNull()
        if (!fastRaw.isNullOrBlank()) {
            runCatching { StoredSession.fromJson(JSONObject(fastRaw)) }.getOrNull()?.let { return it }
        }

        val encRaw = runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) enc.getString(KEY_SESSION, null) else null
        }.getOrNull() ?: return null

        return runCatching {
            StoredSession.fromJson(JSONObject(encRaw))
        }.getOrNull()
    }

    override fun saveSession(session: StoredSession) {
        val encoded = runCatching { session.toJson().toString() }.getOrNull() ?: return
        runCatching {
            fastPrefs?.edit()?.putString(KEY_SESSION, encoded)?.apply()
        }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit().putString(KEY_SESSION, encoded).apply()
            }
        }
    }

    override fun clearSession() {
        runCatching {
            fastPrefs?.edit()
                ?.remove(KEY_SESSION)
                ?.remove(KEY_PENDING_AUTH_REQ_AT)
                ?.apply()
        }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit()
                    .remove(KEY_SESSION)
                    .remove(KEY_PENDING_AUTH_REQ_AT)
                    .apply()
            }
        }
    }

    override fun savePendingAuthRequestAtMs(epochMs: Long) {
        runCatching {
            fastPrefs?.edit()?.putLong(KEY_PENDING_AUTH_REQ_AT, epochMs)?.apply()
        }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit().putLong(KEY_PENDING_AUTH_REQ_AT, epochMs).apply()
            }
        }
    }

    override fun loadPendingAuthRequestAtMs(): Long? {
        val fastVal = runCatching {
            val fp = fastPrefs ?: return@runCatching null
            if (fp.contains(KEY_PENDING_AUTH_REQ_AT)) {
                fp.getLong(KEY_PENDING_AUTH_REQ_AT, 0L).takeIf { it > 0L }
            } else {
                null
            }
        }.getOrNull()
        if (fastVal != null) return fastVal

        return runCatching {
            val enc = encryptedPrefs ?: return@runCatching null
            if (enc !== fastPrefs && enc.contains(KEY_PENDING_AUTH_REQ_AT)) {
                enc.getLong(KEY_PENDING_AUTH_REQ_AT, 0L).takeIf { it > 0L }
            } else {
                null
            }
        }.getOrNull()
    }

    override fun clearPendingAuthRequest() {
        runCatching { fastPrefs?.edit()?.remove(KEY_PENDING_AUTH_REQ_AT)?.apply() }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit().remove(KEY_PENDING_AUTH_REQ_AT).apply()
            }
        }
    }

    override fun saveLastConsumedPhoneSyncMs(epochMs: Long) {
        runCatching {
            fastPrefs?.edit()?.putLong(KEY_LAST_PHONE_SYNC_MS, epochMs)?.apply()
        }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit().putLong(KEY_LAST_PHONE_SYNC_MS, epochMs).apply()
            }
        }
    }

    override fun loadLastConsumedPhoneSyncMs(): Long {
        val fastVal = runCatching { fastPrefs?.getLong(KEY_LAST_PHONE_SYNC_MS, 0L) ?: 0L }.getOrDefault(0L)
        if (fastVal > 0L) return fastVal
        return runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) enc.getLong(KEY_LAST_PHONE_SYNC_MS, 0L) else 0L
        }.getOrDefault(0L)
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
        val existing = loadWearDataCache(accountKey, dateKey)
        saveWearDataCache(
            accountKey = accountKey,
            dateKey = dateKey,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            exams = existing?.exams ?: emptyList(),
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
        exams: List<Exam>,
        syncedAtEpochMs: Long,
        studentName: String?,
        studentUid: String?,
        instituteName: String?,
        instituteCode: String?,
        schoolYearUid: String?,
        userName: String?,
    ) {
        val session = loadSession()
        val raw = runCatching {
            JSONObject().apply {
                put("accountKey", accountKey)
                put("dateKey", dateKey)
                put("syncedAtEpochMs", syncedAtEpochMs)
                put("lessons", JSONArray().apply { lessons.forEach { put(it.toJson()) } })
                put("homeworks", JSONArray().apply { homeworks.forEach { put(it.toJson()) } })
                put("grades", JSONArray().apply { grades.forEach { put(it.toJson()) } })
                put("exams", JSONArray().apply { exams.forEach { put(it.toJson()) } })
                put("studentName", (studentName ?: session?.studentName).orEmpty())
                put("studentUid", (studentUid ?: session?.studentUid).orEmpty())
                put("instituteName", (instituteName ?: session?.instituteName).orEmpty())
                put("instituteCode", (instituteCode ?: session?.instituteCode).orEmpty())
                put("schoolYearUid", (schoolYearUid ?: session?.schoolYearUid).orEmpty())
                put("userName", (userName ?: session?.userName).orEmpty())
            }.toString()
        }.getOrNull() ?: return

        runCatching {
            fastPrefs?.edit()
                ?.putString("$KEY_CACHE_PREFIX$accountKey", raw)
                ?.putString(KEY_LATEST_CACHE, raw)
                ?.apply()
        }

        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit()
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

    /**
     * Persists grades and upcoming exams pushed from the phone over Wearable DataLayer
     * into the watch's offline cache while preserving already-cached timetable lessons.
     */
    fun mergePhoneSyncedSnapshot(
        session: StoredSession,
        grades: List<Grade>?,
        exams: List<Exam>?,
        syncedAtEpochMs: Long = System.currentTimeMillis(),
    ): Boolean {
        if (grades == null && exams == null) return false
        val accountKey = accountKeyFor(session)
        val dateKey = KretaDateParser.dateKeyFor(syncedAtEpochMs)
        val existing = loadWearDataCache(accountKey, dateKey)
        val nextGrades = grades ?: existing?.grades ?: emptyList()
        val nextExams = exams ?: existing?.exams ?: emptyList()
        saveWearDataCache(
            accountKey = accountKey,
            dateKey = dateKey,
            lessons = existing?.lessons ?: emptyList(),
            homeworks = existing?.homeworks ?: emptyList(),
            grades = nextGrades,
            exams = nextExams,
            syncedAtEpochMs = maxOf(existing?.syncedAtEpochMs ?: 0L, syncedAtEpochMs),
            studentName = session.studentName ?: existing?.studentName,
            studentUid = session.studentUid ?: existing?.studentUid,
            instituteName = session.instituteName ?: existing?.instituteName,
            instituteCode = session.instituteCode,
            schoolYearUid = session.schoolYearUid ?: existing?.schoolYearUid,
            userName = session.userName ?: existing?.userName,
        )
        return true
    }

    override fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData? {
        val directCandidates = sequenceOf(
            { runCatching { fastPrefs?.getString("$KEY_CACHE_PREFIX$accountKey", null) }.getOrNull() },
            {
                runCatching {
                    val enc = encryptedPrefs
                    if (enc != null && enc !== fastPrefs) enc.getString("$KEY_CACHE_PREFIX$accountKey", null) else null
                }.getOrNull()
            },
        )
        for (provider in directCandidates) {
            val raw = provider() ?: continue
            parseCachedWearData(raw)?.let { return it }
        }

        val fallbackCandidates = sequenceOf(
            { runCatching { fastPrefs?.getString(KEY_LATEST_CACHE, null) }.getOrNull() },
            {
                runCatching {
                    val enc = encryptedPrefs
                    if (enc != null && enc !== fastPrefs) enc.getString(KEY_LATEST_CACHE, null) else null
                }.getOrNull()
            },
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
        runCatching {
            fastPrefs?.edit()
                ?.remove("$KEY_CACHE_PREFIX$accountKey")
                ?.remove(KEY_LATEST_CACHE)
                ?.apply()
        }
        runCatching {
            val enc = encryptedPrefs
            if (enc != null && enc !== fastPrefs) {
                enc.edit()
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
            .mapNotNull { runCatching { Lesson.fromJson(it) }.getOrNull() }
            .sortedBy { it.startEpochMs }
        val homeworks = (json.optJSONArray("homeworks")?.toJsonObjectList() ?: emptyList())
            .mapNotNull { runCatching { Homework.fromJson(it) }.getOrNull() }
        val grades = (json.optJSONArray("grades")?.toJsonObjectList() ?: emptyList())
            .mapNotNull { runCatching { Grade.fromJson(it) }.getOrNull() }
            .sortedByDescending { it.recordedAtEpochMs }
        val exams = (json.optJSONArray("exams")?.toJsonObjectList() ?: emptyList())
            .mapNotNull { runCatching { Exam.fromJson(it) }.getOrNull() }
            .sortedWith(compareBy<Exam>({ it.dateEpochMs }, { it.lessonNumber ?: Int.MAX_VALUE }))

        CachedWearData(
            dateKey = cachedDate,
            syncedAtEpochMs = json.optLong("syncedAtEpochMs", 0L),
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            exams = exams,
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
