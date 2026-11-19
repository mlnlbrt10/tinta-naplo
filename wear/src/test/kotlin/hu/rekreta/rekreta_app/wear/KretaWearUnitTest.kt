package hu.rekreta.rekreta_app.wear

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import hu.rekreta.rekreta_app.shared.KretaSharedConfig
import hu.rekreta.rekreta_app.wear.auth.AuthSessionSynchronizer
import hu.rekreta.rekreta_app.wear.data.AuthSessionPayload
import hu.rekreta.rekreta_app.wear.data.CachedWearData
import hu.rekreta.rekreta_app.wear.data.Grade
import hu.rekreta.rekreta_app.wear.data.GradeAnalytics
import hu.rekreta.rekreta_app.wear.data.Homework
import hu.rekreta.rekreta_app.wear.data.JwtPayloadDecoder
import hu.rekreta.rekreta_app.wear.data.KretaWearApiClient
import hu.rekreta.rekreta_app.wear.data.Lesson
import hu.rekreta.rekreta_app.wear.data.SecureTokenStorage
import hu.rekreta.rekreta_app.wear.data.StoredSession
import hu.rekreta.rekreta_app.wear.data.TimetablePhase
import hu.rekreta.rekreta_app.wear.data.TimetableStatusEvaluator
import hu.rekreta.rekreta_app.wear.data.WearTokenStore
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Base64

private class InMemoryWearTokenStore : WearTokenStore {
    var session: StoredSession? = null
    var pendingRequestAtMs: Long? = null
    var lastConsumedPhoneSyncMs: Long = 0L
    val caches = mutableMapOf<String, CachedWearData>()

    override fun loadSession(): StoredSession? = session
    override fun saveSession(session: StoredSession) {
        this.session = session
    }

    override fun clearSession() {
        session = null
        pendingRequestAtMs = null
    }

    override fun savePendingAuthRequestAtMs(epochMs: Long) {
        pendingRequestAtMs = epochMs
    }

    override fun loadPendingAuthRequestAtMs(): Long? = pendingRequestAtMs
    override fun clearPendingAuthRequest() {
        pendingRequestAtMs = null
    }

    override fun saveLastConsumedPhoneSyncMs(epochMs: Long) {
        lastConsumedPhoneSyncMs = epochMs
    }

    override fun loadLastConsumedPhoneSyncMs(): Long = lastConsumedPhoneSyncMs

    override fun saveWearDataCache(
        accountKey: String,
        dateKey: String,
        lessons: List<Lesson>,
        homeworks: List<Homework>,
        grades: List<Grade>,
        syncedAtEpochMs: Long,
    ) {
        caches[accountKey] = CachedWearData(dateKey, syncedAtEpochMs, lessons, homeworks, grades)
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
        caches[accountKey] = CachedWearData(
            dateKey = dateKey,
            syncedAtEpochMs = syncedAtEpochMs,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            studentName = studentName,
            studentUid = studentUid,
            instituteName = instituteName,
            instituteCode = instituteCode,
            schoolYearUid = schoolYearUid,
            userName = userName,
        )
    }

    override fun loadWearDataCache(accountKey: String, dateKey: String): CachedWearData? = caches[accountKey]
    override fun clearWearDataCache(accountKey: String) {
        caches.remove(accountKey)
    }
}

private class InMemorySharedPreferences : SharedPreferences {
    private val data = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = data.toMutableMap()
    override fun getString(key: String?, defValue: String?): String? =
        (data[key] as? String) ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        (data[key] as? Set<String>)?.toMutableSet() ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = (data[key] as? Int) ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = (data[key] as? Long) ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = (data[key] as? Float) ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = (data[key] as? Boolean) ?: defValue
    override fun contains(key: String?): Boolean = data.containsKey(key)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private var clearAll = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = values?.toSet()
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = value
        }

        override fun remove(key: String?): SharedPreferences.Editor = apply {
            if (key != null) pending[key] = null
        }

        override fun clear(): SharedPreferences.Editor = apply {
            clearAll = true
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearAll) data.clear()
            for ((k, v) in pending) {
                if (v == null) data.remove(k) else data[k] = v
            }
        }
    }
}

private class FakeWearContext(private val tempFilesDir: File) : ContextWrapper(null) {
    private val prefsByName = mutableMapOf<String, InMemorySharedPreferences>()

    override fun getApplicationContext(): Context = this
    override fun getFilesDir(): File = tempFilesDir
    override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences {
        val key = name ?: "default"
        return prefsByName.getOrPut(key) { InMemorySharedPreferences() }
    }
}

class KretaWearUnitTest {

    private fun fakeJwt(claims: Map<String, Any>): String {
        val header = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("""{"alg":"none"}""".toByteArray(StandardCharsets.UTF_8))
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(JSONObject(claims).toString().toByteArray(StandardCharsets.UTF_8))
        return "$header.$payload.sig"
    }

    @Test
    fun `generated KretaSharedConfig matches shared kreta_config json`() {
        val candidates = listOf(
            File("../shared/kreta_config.json"),
            File("shared/kreta_config.json"),
        )
        val configFile = candidates.firstOrNull { it.exists() }
        assertNotNull("shared/kreta_config.json must exist", configFile)
        val json = JSONObject(configFile!!.readText(StandardCharsets.UTF_8))
        val wearRelay = json.getJSONObject("wearRelay")

        assertEquals(json.getString("idpBaseUrl"), KretaSharedConfig.IDP_BASE_URL)
        assertEquals(json.getString("tokenEndpoint"), KretaSharedConfig.TOKEN_ENDPOINT)
        assertEquals(json.getString("redirectUri"), KretaSharedConfig.REDIRECT_URI)
        assertEquals(json.getString("scopes"), KretaSharedConfig.SCOPES)
        assertEquals(json.getString("apiKey"), KretaSharedConfig.API_KEY)
        assertEquals(json.getString("userAgent"), KretaSharedConfig.USER_AGENT)
        assertEquals("/tinta/request_auth", KretaSharedConfig.WEAR_MSG_REQUEST_AUTH)
        assertEquals("/tinta/auth_session", KretaSharedConfig.WEAR_DATA_AUTH_SESSION)
        assertEquals("tintanaplo://wear-auth", KretaSharedConfig.WEAR_DEEP_LINK_URI)
        assertEquals(wearRelay.getString("messagePathRequestAuth"), KretaSharedConfig.WEAR_MSG_REQUEST_AUTH)
        assertEquals(wearRelay.getString("dataPathAuthSession"), KretaSharedConfig.WEAR_DATA_AUTH_SESSION)
        assertEquals(wearRelay.getString("deepLinkUri"), KretaSharedConfig.WEAR_DEEP_LINK_URI)
    }

    @Test
    fun `JwtPayloadDecoder extracts claims safely`() {
        val jwt = fakeJwt(
            mapOf(
                "kreta:institute_code" to "klik035277001",
                "kreta:user_name" to "71234567890",
            ),
        )
        val decoded = JwtPayloadDecoder.decodeJwtPayload(jwt)
        assertEquals("klik035277001", decoded.getString("kreta:institute_code"))
        assertEquals("71234567890", decoded.getString("kreta:user_name"))
    }

    @Test
    fun `AuthSessionSynchronizer persists phone session and prevents stale auto-relogin after logout`() {
        val store = InMemoryWearTokenStore()
        val sync = AuthSessionSynchronizer(store)
        val expFuture = System.currentTimeMillis() + 1_800_000L

        val initialPayload = AuthSessionPayload.fromMap(
            mapOf(
                "access_token" to fakeJwt(
                    mapOf(
                        "kreta:institute_code" to "klik035277001",
                        "kreta:user_name" to "71234567890",
                        "exp" to (expFuture / 1000L),
                    ),
                ),
                "refresh_token" to "rt_phone_1",
                "institute_code" to "klik035277001",
                "user_name" to "71234567890",
                "expires_at_ms" to expFuture,
                "student_name" to "Kovács Milán",
                "institute_name" to "Fazekas Mihály Gimnázium",
                "synced_at_ms" to 1_000L,
                "force_sync" to true,
            ),
        )
        assertNotNull(initialPayload)

        val saved = sync.processIncomingSession(initialPayload!!, fromLiveChange = true)
        assertNotNull(saved)
        assertEquals("rt_phone_1", store.loadSession()?.refreshToken)
        assertEquals("klik035277001", store.loadSession()?.instituteCode)
        assertEquals("Kovács Milán", store.loadSession()?.studentName)
        assertEquals("Fazekas Mihály Gimnázium", store.loadSession()?.instituteName)
        assertEquals(1_000L, store.loadLastConsumedPhoneSyncMs())

        // User logs out on the watch; stale DataItem from synced_at_ms=1000 must not re-login passively.
        store.clearSession()
        assertNull(sync.processIncomingSession(initialPayload, fromLiveChange = false))
        assertNull(store.loadSession())

        // Phone pushes a fresh sync with newer synced_at_ms -> watch signs back in.
        val freshPayload = initialPayload.copy(refreshToken = "rt_phone_2", syncedAtEpochMs = 2_000L)
        val resynced = sync.processIncomingSession(freshPayload, fromLiveChange = true)
        assertNotNull(resynced)
        assertEquals("rt_phone_2", store.loadSession()?.refreshToken)
        assertEquals(2_000L, store.loadLastConsumedPhoneSyncMs())
    }

    @Test
    fun `AuthSessionPayload mergeInto keeps newer watch refresh token on non-forced metadata update`() {
        val now = System.currentTimeMillis()
        val existingWatchSession = StoredSession(
            accessToken = "watch_access_newer",
            refreshToken = "watch_rt_newer",
            idToken = "",
            instituteCode = "klik035277001",
            userName = "71234567890",
            expiresAtEpochMs = now + 3_600_000L,
            studentName = null,
            instituteName = null,
        )
        val metadataUpdate = AuthSessionPayload(
            accessToken = "phone_access_older",
            refreshToken = "phone_rt_older",
            idToken = "",
            instituteCode = "klik035277001",
            userName = "71234567890",
            expiresAtEpochMs = now + 600_000L,
            studentName = "Nagy Anna",
            studentUid = "st_1",
            instituteName = "Radnóti Gimnázium",
            schoolYearUid = "2026",
            syncedAtEpochMs = 5_000L,
            forceSync = false,
        )

        val merged = metadataUpdate.mergeInto(existingWatchSession)
        assertEquals("watch_rt_newer", merged.refreshToken)
        assertEquals("watch_access_newer", merged.accessToken)
        assertEquals("Nagy Anna", merged.studentName)
        assertEquals("Radnóti Gimnázium", merged.instituteName)
    }

    @Test
    fun `Lesson parses cancelled substituted and homework flags`() {
        val cancelled = Lesson.fromJson(
            JSONObject(
                """
                {
                  "Uid": "l1",
                  "Datum": "2026-11-17T00:00:00Z",
                  "KezdetIdopont": "2026-11-17T08:00:00Z",
                  "VegIdopont": "2026-11-17T08:45:00Z",
                  "Nev": "Fizika",
                  "Oraszam": 1,
                  "TeremNeve": "B-204",
                  "Tantargy": {"Uid": "sub_phy", "Nev": "Fizika"},
                  "Allapot": {"Nev": "Elmaradt", "Leiras": "Elmaradt"}
                }
                """.trimIndent(),
            ),
        )
        assertTrue(cancelled.isCancelled)
        assertFalse(cancelled.isSubstituted)
        assertEquals("1. Fizika • B-204", cancelled.periodSubjectRoomBadge())

        val substituted = Lesson.fromJson(
            JSONObject(
                """
                {
                  "Uid": "l2",
                  "Datum": "2026-11-17T00:00:00Z",
                  "KezdetIdopont": "2026-11-17T09:00:00Z",
                  "VegIdopont": "2026-11-17T09:45:00Z",
                  "Nev": "Matematika",
                  "Oraszam": 3,
                  "TeremNeve": "B-204",
                  "HelyettesTanarNeve": "Kiss Anna",
                  "HaziFeladatUid": "987654,TanarHaziFeladat",
                  "IsHaziFeladatMegoldva": false,
                  "Tantargy": {"Uid": "sub_math", "Nev": "Matematika"},
                  "Allapot": {"Nev": "Megtartott", "Leiras": "Megtartott"}
                }
                """.trimIndent(),
            ),
        )
        assertFalse(substituted.isCancelled)
        assertTrue(substituted.isSubstituted)
        assertTrue(substituted.hasActiveHomework(emptyList()))
    }

    @Test
    fun `GradeAnalytics computes weighted averages and newest-first summaries`() {
        val g1 = Grade.fromJson(
            JSONObject(
                """
                {
                  "Uid": "g1",
                  "KeszitesDatuma": "2026-11-15T10:00:00Z",
                  "Tantargy": {"Uid": "math", "Nev": "Matematika"},
                  "SzamErtek": 5,
                  "SzovegesErtek": "Jeles(5)",
                  "SulySzazalekErteke": 200
                }
                """.trimIndent(),
            ),
        )
        val g2 = Grade.fromJson(
            JSONObject(
                """
                {
                  "Uid": "g2",
                  "KeszitesDatuma": "2026-11-10T10:00:00Z",
                  "Tantargy": {"Uid": "math", "Nev": "Matematika"},
                  "SzamErtek": 2,
                  "SzovegesErtek": "Elégséges(2)",
                  "SulySzazalekErteke": 100
                }
                """.trimIndent(),
            ),
        )
        val summaries = GradeAnalytics.summarizeBySubject(listOf(g2, g1))
        assertEquals(1, summaries.size)
        // (5*200 + 2*100) / 300 = 4.0
        assertEquals(4.0, summaries.first().weightedAverage!!, 0.001)
    }

    @Test
    fun `TimetableStatusEvaluator calculates active lesson countdown and next 2 pills`() {
        val zone = ZoneId.of("Europe/Budapest")
        val day = LocalDate.of(2026, 11, 17)
        fun at(h: Int, m: Int): Long =
            ZonedDateTime.of(day.year, day.monthValue, day.dayOfMonth, h, m, 0, 0, zone)
                .toInstant()
                .toEpochMilli()

        val lessons = listOf(
            Lesson("3", "2026-11-17", at(9, 50), at(10, 35), "Matematika", 3, "m", "Matematika", "B-204", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("4", "2026-11-17", at(10, 45), at(11, 30), "Történelem", 4, "h", "Történelem", "A-102", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("5", "2026-11-17", at(11, 40), at(12, 25), "Angol", 5, "e", "Angol", "C-12", null, null, null, "Megtartott", "Megtartott", null, false),
        )

        // 14 minutes before 10:35 -> 10:21:00
        val status = TimetableStatusEvaluator.evaluate(lessons, at(10, 21))
        assertEquals(TimetablePhase.ACTIVE_LESSON, status.phase)
        assertEquals("MOST • 3. óra", status.badgeLabel)
        assertEquals("Matematika", status.titleLabel)
        assertEquals(2, status.upcomingLessons.size)
        assertEquals("4. Történelem • A-102", status.upcomingLessons[0].periodSubjectRoomBadge())
        assertEquals("5. Angol • C-12", status.upcomingLessons[1].periodSubjectRoomBadge())
        assertEquals("14:00", TimetableStatusEvaluator.formatTabularCountdown(status.remainingMillis!!))
        assertEquals("14 perc hátra", TimetableStatusEvaluator.formatRemainingMinutesBadge(status.remainingMillis))

        val afterSchool = TimetableStatusEvaluator.evaluate(lessons, at(13, 0))
        assertEquals(TimetablePhase.AFTER_SCHOOL, afterSchool.phase)
        assertEquals("Nincs több óra ma", afterSchool.titleLabel)
        assertTrue(afterSchool.upcomingLessons.isEmpty())

        // Break between lesson 3 (ends 10:35) and lesson 4 (starts 10:45)
        val duringBreak = TimetableStatusEvaluator.evaluate(lessons, at(10, 40))
        assertEquals(TimetablePhase.BREAK, duringBreak.phase)
        assertNull(duringBreak.currentLesson)
        assertEquals("4. Történelem • A-102", duringBreak.nextLesson?.periodSubjectRoomBadge())
        assertEquals(0.5f, duringBreak.remainingFraction, 0.001f)
        assertEquals("5 perc hátra", TimetableStatusEvaluator.formatRemainingMinutesBadge(duringBreak.remainingMillis!!))

        // Final lesson of the day (lesson 5) has no next lesson
        val lastLesson = TimetableStatusEvaluator.evaluate(lessons, at(12, 0))
        assertEquals(TimetablePhase.ACTIVE_LESSON, lastLesson.phase)
        assertEquals("Angol", lastLesson.currentLesson?.displaySubject)
        assertNull(lastLesson.nextLesson)
    }

    @Test
    fun `KretaWearApiClient refreshes standalone from phone-synced refresh token and on 401`() = runTest {
        val server = MockWebServer()
        val expFuture = (System.currentTimeMillis() / 1000L) + 3600L
        val freshAccessJwt = fakeJwt(
            mapOf(
                "kreta:institute_code" to "klik035277001",
                "kreta:user_name" to "71234567890",
                "exp" to expFuture,
            ),
        )

        var tokenCalls = 0
        var timetableCalls = 0

        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    path.startsWith("/connect/token") -> {
                        tokenCalls++
                        val body = request.body.readUtf8()
                        assertTrue(body.contains("grant_type=refresh_token"))
                        assertTrue(body.contains("institute_code=klik035277001"))
                        val rt = if (tokenCalls == 1) "rt_watch_1" else "rt_watch_2"
                        val at = if (tokenCalls == 1) "stale_after_first_refresh" else freshAccessJwt
                        MockResponse()
                            .setResponseCode(200)
                            .setBody(
                                JSONObject(
                                    mapOf(
                                        "access_token" to at,
                                        "refresh_token" to rt,
                                        "id_token" to freshAccessJwt,
                                        "expires_in" to 3600,
                                        "token_type" to "Bearer",
                                    ),
                                ).toString(),
                            )
                    }

                    path.startsWith("/ellenorzo/v3/sajat/OrarendElemek") -> {
                        timetableCalls++
                        val auth = request.getHeader("Authorization")
                        if (auth == "Bearer stale_after_first_refresh") {
                            MockResponse().setResponseCode(401)
                        } else {
                            MockResponse()
                                .setResponseCode(200)
                                .setBody(JSONArray().toString())
                        }
                    }

                    path.startsWith("/ellenorzo/v3/sajat/Ertekelesek") ->
                        MockResponse().setResponseCode(200).setBody("[]")

                    path.startsWith("/ellenorzo/v3/sajat/HaziFeladatok") ->
                        MockResponse().setResponseCode(200).setBody("[]")

                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        server.start()

        try {
            val baseUrl = server.url("/").toString().trimEnd('/')
            val store = InMemoryWearTokenStore()
            val synchronizer = AuthSessionSynchronizer(store)
            val client = KretaWearApiClient(
                tokenStore = store,
                idpBaseUrlOverride = baseUrl,
                tenantBaseUrlOverride = baseUrl,
            )

            // Seed watch with a phone-pushed payload containing refresh_token + institute_code (empty access_token)
            val phonePayload = AuthSessionPayload.fromMap(
                mapOf(
                    "access_token" to "",
                    "refresh_token" to "rt_from_phone",
                    "institute_code" to "klik035277001",
                    "user_name" to "71234567890",
                    "student_name" to "Kovács Milán",
                    "institute_name" to "Fazekas Gimnázium",
                    "synced_at_ms" to 100L,
                    "force_sync" to true,
                ),
            )!!
            val seeded = synchronizer.processIncomingSession(phonePayload, fromLiveChange = true)!!
            assertTrue(seeded.isExpired())
            assertEquals("rt_from_phone", store.loadSession()?.refreshToken)

            // syncAll refreshes independently (call #1), gets 401 on timetable, refreshes again (call #2), and replays!
            val synced = client.syncAll(seeded, targetDate = LocalDate.now())
            assertTrue(synced.lessons.isEmpty())
            assertEquals(2, tokenCalls)
            assertEquals(2, timetableCalls)
            assertEquals("rt_watch_2", store.loadSession()?.refreshToken)
            assertEquals(freshAccessJwt, store.loadSession()?.accessToken)
            assertEquals("Kovács Milán", store.loadSession()?.studentName)
            assertEquals("Fazekas Gimnázium", store.loadSession()?.instituteName)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `TimetableStatusEvaluator evaluateWithRollover auto-advances after classes end and across weekend`() {
        val zone = ZoneId.of("Europe/Budapest")
        fun at(date: LocalDate, h: Int, m: Int): Long =
            ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, h, m, 0, 0, zone)
                .toInstant()
                .toEpochMilli()

        val tuesday = LocalDate.of(2026, 11, 17)
        val wednesday = LocalDate.of(2026, 11, 18)
        val friday = LocalDate.of(2026, 11, 20)
        val monday = LocalDate.of(2026, 11, 23)

        val multiDayLessons = listOf(
            Lesson("t1", tuesday.toString(), at(tuesday, 8, 0), at(tuesday, 8, 45), "Matematika", 1, "m", "Matematika", "B-204", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("t2", tuesday.toString(), at(tuesday, 8, 55), at(tuesday, 9, 40), "Történelem", 2, "h", "Történelem", "A-102", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("t3", tuesday.toString(), at(tuesday, 9, 50), at(tuesday, 10, 35), "Fizika", 3, "p", "Fizika", "B-101", null, null, null, "Elmaradt", "Elmaradt", null, false),
            Lesson("w1", wednesday.toString(), at(wednesday, 8, 0), at(wednesday, 8, 45), "Ének", 1, "e", "Ének", "Z-1", null, null, null, "Elmaradt", "Elmaradt", null, false),
            Lesson("w2", wednesday.toString(), at(wednesday, 8, 55), at(wednesday, 9, 40), "Irodalom", 2, "i", "Irodalom", "C-12", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("w3", wednesday.toString(), at(wednesday, 9, 50), at(wednesday, 10, 35), "Angol", 3, "a", "Angol", "C-14", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("f1", friday.toString(), at(friday, 8, 0), at(friday, 8, 45), "Kémia", 1, "k", "Kémia", "L-2", null, null, null, "Megtartott", "Megtartott", null, false),
            Lesson("m1", monday.toString(), at(monday, 8, 0), at(monday, 8, 45), "Informatika", 1, "inf", "Informatika", "Inf-1", null, null, null, "Megtartott", "Megtartott", null, false),
        )

        // While Tuesday lesson 2 is still active -> stays on Tuesday
        val duringTuesday = TimetableStatusEvaluator.evaluateWithRollover(multiDayLessons, at(tuesday, 9, 10), zone)
        assertFalse(duringTuesday.isRolledOverToNextDay)
        assertEquals(TimetablePhase.ACTIVE_LESSON, duringTuesday.todayStatus.phase)
        assertEquals("Ma • Kedd", duringTuesday.displayDayPillLabel)
        assertEquals(3, duringTuesday.displayLessons.size)
        assertNull(duringTuesday.page1DayBadgeLabel)

        // Right after Tuesday's last non-cancelled lesson ends (09:41) -> auto-advances to Wednesday
        val afterTuesday = TimetableStatusEvaluator.evaluateWithRollover(multiDayLessons, at(tuesday, 9, 41), zone)
        assertTrue(afterTuesday.isRolledOverToNextDay)
        assertEquals(TimetablePhase.AFTER_SCHOOL, afterTuesday.todayStatus.phase)
        assertEquals("Holnap", afterTuesday.page1DayBadgeLabel)
        assertEquals("Holnap • Szerda", afterTuesday.displayDayPillLabel)
        assertEquals("w2", afterTuesday.previewFirstLesson?.uid)
        assertEquals("w3", afterTuesday.previewSecondLesson?.uid)
        assertEquals(listOf("w1", "w2", "w3"), afterTuesday.displayLessons.map { it.uid })

        // After Friday's classes -> rolls over across weekend to Monday
        val afterFriday = TimetableStatusEvaluator.evaluateWithRollover(multiDayLessons, at(friday, 10, 0), zone)
        assertTrue(afterFriday.isRolledOverToNextDay)
        assertEquals("Hétfő", afterFriday.page1DayBadgeLabel)
        assertEquals("Hétfő • 11. 23.", afterFriday.displayDayPillLabel)
        assertEquals("m1", afterFriday.previewFirstLesson?.uid)

        // On Sunday (no classes today) -> rolls over to Monday ("Holnap • Hétfő")
        val sunday = LocalDate.of(2026, 11, 22)
        val onSunday = TimetableStatusEvaluator.evaluateWithRollover(multiDayLessons, at(sunday, 14, 0), zone)
        assertTrue(onSunday.isRolledOverToNextDay)
        assertEquals(TimetablePhase.NO_CLASSES_TODAY, onSunday.todayStatus.phase)
        assertEquals("Holnap", onSunday.page1DayBadgeLabel)
        assertEquals("Holnap • Hétfő", onSunday.displayDayPillLabel)
        assertEquals("m1", onSunday.previewFirstLesson?.uid)
    }

    @Test
    fun `KretaWearApiClient refreshSession uses freshest persisted token and syncAll caches multi-day timetable`() = runTest {
        val server = MockWebServer()
        val expFuture = (System.currentTimeMillis() / 1000L) + 3600L
        val freshJwt = fakeJwt(
            mapOf(
                "kreta:institute_code" to "klik035277001",
                "kreta:user_name" to "71234567890",
                "exp" to expFuture,
            ),
        )
        val today = LocalDate.now()
        val tomorrow = today.plusDays(1)
        var observedRefreshToken: String? = null
        var observedFrom: String? = null
        var observedTo: String? = null

        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    path.startsWith("/connect/token") -> {
                        val body = request.body.readUtf8()
                        observedRefreshToken = body.split("&")
                            .firstOrNull { it.startsWith("refresh_token=") }
                            ?.substringAfter("refresh_token=")
                        MockResponse()
                            .setResponseCode(200)
                            .setBody(
                                JSONObject(
                                    mapOf(
                                        "access_token" to freshJwt,
                                        "refresh_token" to "rt_rotated_next",
                                        "id_token" to freshJwt,
                                        "expires_in" to 3600,
                                        "token_type" to "Bearer",
                                    ),
                                ).toString(),
                            )
                    }

                    path.startsWith("/ellenorzo/v3/sajat/OrarendElemek") -> {
                        observedFrom = request.requestUrl?.queryParameter("datumTol")
                        observedTo = request.requestUrl?.queryParameter("datumIg")
                        val array = JSONArray().apply {
                            put(
                                JSONObject(
                                    mapOf(
                                        "Uid" to "today_1",
                                        "Datum" to "${today}T00:00:00Z",
                                        "KezdetIdopont" to "${today}T08:00:00Z",
                                        "VegIdopont" to "${today}T08:45:00Z",
                                        "Nev" to "Matematika",
                                        "Oraszam" to 1,
                                        "Tantargy" to mapOf("Uid" to "m", "Nev" to "Matematika"),
                                        "Allapot" to mapOf("Nev" to "Megtartott", "Leiras" to "Megtartott"),
                                    ),
                                ),
                            )
                            put(
                                JSONObject(
                                    mapOf(
                                        "Uid" to "tomorrow_1",
                                        "Datum" to "${tomorrow}T00:00:00Z",
                                        "KezdetIdopont" to "${tomorrow}T08:00:00Z",
                                        "VegIdopont" to "${tomorrow}T08:45:00Z",
                                        "Nev" to "Biológia",
                                        "Oraszam" to 1,
                                        "Tantargy" to mapOf("Uid" to "b", "Nev" to "Biológia"),
                                        "Allapot" to mapOf("Nev" to "Megtartott", "Leiras" to "Megtartott"),
                                    ),
                                ),
                            )
                        }
                        MockResponse().setResponseCode(200).setBody(array.toString())
                    }

                    path.startsWith("/ellenorzo/v3/sajat/Ertekelesek") ->
                        MockResponse().setResponseCode(200).setBody("[]")

                    path.startsWith("/ellenorzo/v3/sajat/HaziFeladatok") ->
                        MockResponse().setResponseCode(200).setBody("[]")

                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        server.start()

        try {
            val baseUrl = server.url("/").toString().trimEnd('/')
            val store = InMemoryWearTokenStore()
            val staleSession = StoredSession(
                accessToken = "old_access",
                refreshToken = "rt_stale_in_memory",
                idToken = "",
                instituteCode = "klik035277001",
                userName = "71234567890",
                expiresAtEpochMs = 0L,
                studentName = "Kovács Milán",
                instituteName = "Fazekas Gimnázium",
            )
            val newerDiskSession = staleSession.copy(refreshToken = "rt_fresh_on_disk")
            store.saveSession(newerDiskSession)

            val client = KretaWearApiClient(
                tokenStore = store,
                idpBaseUrlOverride = baseUrl,
                tenantBaseUrlOverride = baseUrl,
            )

            val refreshed = client.refreshSession(staleSession)
            assertEquals("rt_fresh_on_disk", observedRefreshToken)
            assertEquals("rt_rotated_next", refreshed.refreshToken)
            assertEquals("Kovács Milán", refreshed.studentName)
            assertEquals("Fazekas Gimnázium", refreshed.instituteName)

            val synced = client.syncAll(refreshed, targetDate = today, zoneId = ZoneId.of("UTC"))
            assertEquals(today.toString(), observedFrom)
            assertEquals(today.plusDays(10).toString(), observedTo)
            assertEquals(listOf("today_1", "tomorrow_1"), synced.lessons.map { it.uid })
            assertEquals("Kovács Milán", synced.studentName)
            assertTrue(synced.syncedAtEpochMs > 0L)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `SecureTokenStorage persists multi-day cache and metadata across dates and accountKey normalization`() {
        val tempDir = Files.createTempDirectory("tinta_wear_cache_test").toFile()
        try {
            val context = FakeWearContext(tempDir)
            val storage = SecureTokenStorage(context)
            val session = StoredSession(
                accessToken = "acc_1",
                refreshToken = "rt_1",
                idToken = "id_1",
                instituteCode = "KLIK035277001",
                userName = null,
                expiresAtEpochMs = System.currentTimeMillis() + 3_600_000L,
                studentName = "Nagy Anna",
                studentUid = "stu_9",
                instituteName = "Radnóti Gimnázium",
                schoolYearUid = "2026",
            )
            storage.saveSession(session)

            val zone = ZoneId.of("Europe/Budapest")
            val day1 = LocalDate.of(2026, 11, 17)
            val day2 = LocalDate.of(2026, 11, 18)
            val lessons = listOf(
                Lesson(
                    "d1_1",
                    day1.toString(),
                    ZonedDateTime.of(2026, 11, 17, 8, 0, 0, 0, zone).toInstant().toEpochMilli(),
                    ZonedDateTime.of(2026, 11, 17, 8, 45, 0, 0, zone).toInstant().toEpochMilli(),
                    "Matematika",
                    1,
                    "m",
                    "Matematika",
                    "101",
                    null,
                    null,
                    null,
                    "Megtartott",
                    "Megtartott",
                    null,
                    false,
                ),
                Lesson(
                    "d2_1",
                    day2.toString(),
                    ZonedDateTime.of(2026, 11, 18, 8, 0, 0, 0, zone).toInstant().toEpochMilli(),
                    ZonedDateTime.of(2026, 11, 18, 8, 45, 0, 0, zone).toInstant().toEpochMilli(),
                    "Fizika",
                    1,
                    "f",
                    "Fizika",
                    "202",
                    null,
                    null,
                    null,
                    "Megtartott",
                    "Megtartott",
                    null,
                    false,
                ),
            )

            val initialKey = SecureTokenStorage.accountKeyFor(session)
            assertEquals("klik035277001|default", initialKey)

            storage.saveWearDataCache(
                accountKey = initialKey,
                dateKey = day1.toString(),
                lessons = lessons,
                homeworks = emptyList(),
                grades = emptyList(),
                syncedAtEpochMs = 123_456L,
            )

            // Cache file written on disk
            assertTrue(File(tempDir, "wear_timetable_cache_v2.json").exists())

            // Next day lookup still returns multi-day cached lessons + student metadata
            val reloadedSameUser = storage.loadWearDataCache(initialKey, day2.toString())
            assertNotNull(reloadedSameUser)
            assertEquals(2, reloadedSameUser!!.lessons.size)
            assertEquals(123_456L, reloadedSameUser.syncedAtEpochMs)
            assertEquals("Nagy Anna", reloadedSameUser.studentName)
            assertEquals("Radnóti Gimnázium", reloadedSameUser.instituteName)

            // Even after userName resolves from JWT refresh, fallback recovers the cache
            val updatedKey = SecureTokenStorage.accountKeyFor(session.copy(userName = "71234567890"))
            val recoveredAfterUserResolved = storage.loadWearDataCache(updatedKey, day2.toString())
            assertNotNull(recoveredAfterUserResolved)
            assertEquals(listOf("d1_1", "d2_1"), recoveredAfterUserResolved!!.lessons.map { it.uid })

            // Explicit logout clears session and cache
            storage.clearWearDataCache(initialKey)
            storage.clearSession()
            assertNull(storage.loadSession())
            assertNull(storage.loadWearDataCache(initialKey, day2.toString()))
            assertFalse(File(tempDir, "wear_timetable_cache_v2.json").exists())
        } finally {
            tempDir.deleteRecursively()
        }
    }
}
