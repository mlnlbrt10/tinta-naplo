package hu.mlnlbrt.tintanaplo.wear.data

import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.ZoneId

class TokenExpiredException(
    message: String = "A munkamenet lejárt, jelentkezz be újra.",
) : Exception(message)

class InvalidGrantException(
    message: String = "Érvénytelen vagy visszavont token.",
) : Exception(message)

class KretaApiException(
    val statusCode: Int,
    message: String,
) : Exception(message)

class KretaWearApiClient(
    private val tokenStore: WearTokenStore,
    private val clientId: String = KretaSharedConfig.CLIENT_ID_IOS,
    private val idpBaseUrlOverride: String? = null,
    private val tenantBaseUrlOverride: String? = null,
) {
    @Volatile
    private var latestSession: StoredSession? = null

    private val idpBaseUrl: String
        get() = (idpBaseUrlOverride ?: KretaSharedConfig.IDP_BASE_URL).trimEnd('/')

    private fun tokenEndpoint(): String =
        if (idpBaseUrlOverride != null) "$idpBaseUrl/connect/token"
        else KretaSharedConfig.TOKEN_ENDPOINT

    private fun instituteBaseUrl(instituteCode: String): String {
        if (tenantBaseUrlOverride != null) {
            return tenantBaseUrlOverride.trimEnd('/')
        }
        return if (instituteCode == "firka-test") {
            "https://${KretaSharedConfig.KRETA_BASE_DOMAIN}"
        } else {
            "https://$instituteCode.${KretaSharedConfig.KRETA_BASE_DOMAIN}"
        }
    }

    suspend fun refreshSession(current: StoredSession): StoredSession = globalRefreshMutex.withLock {
        val stored = tokenStore.loadSession()
        val candidate = stored?.takeIf { !it.isExpired() } ?: latestSession?.takeIf { !it.isExpired() }
        if (candidate != null && candidate.accessToken != current.accessToken) {
            latestSession = candidate
            return@withLock candidate
        }

        val active = stored?.takeIf { it.refreshToken.isNotBlank() }
            ?: latestSession?.takeIf { it.refreshToken.isNotBlank() }
            ?: current
        if (active.refreshToken.isBlank()) {
            throw TokenExpiredException()
        }

        val refreshed = withContext(Dispatchers.IO) {
            val form = encodeForm(
                mapOf(
                    "institute_code" to active.instituteCode,
                    "refresh_token" to active.refreshToken,
                    "grant_type" to "refresh_token",
                    "client_id" to clientId,
                ),
            )
            val resp = executeRequest(
                method = "POST",
                urlString = tokenEndpoint(),
                headers = mapOf(
                    "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
                    "Accept" to "*/*",
                    "User-Agent" to KretaSharedConfig.USER_AGENT,
                ),
                body = form,
            )
            when (resp.statusCode) {
                400 -> throw TokenExpiredException()
                401 -> throw InvalidGrantException()
                200 -> {
                    val json = JSONObject(resp.body)
                    StoredSession.fromTokenGrantJson(
                        json = json,
                        fallbackInstituteCode = active.instituteCode,
                        fallbackRefreshToken = active.refreshToken,
                        fallbackUserName = active.userName,
                        studentName = active.studentName,
                        studentUid = active.studentUid,
                        instituteName = active.instituteName,
                        schoolYearUid = active.schoolYearUid,
                    )
                }
                else -> throw KretaApiException(
                    resp.statusCode,
                    "Token frissítés sikertelen (HTTP ${resp.statusCode})",
                )
            }
        }

        latestSession = refreshed
        tokenStore.saveSession(refreshed)
        refreshed
    }

    suspend fun ensureValidSession(session: StoredSession): StoredSession {
        val stored = tokenStore.loadSession()
        val active = stored?.takeIf { !it.isExpired() }
            ?: latestSession?.takeIf { !it.isExpired() }
            ?: stored
            ?: latestSession
            ?: session
        if (!active.isExpired()) {
            latestSession = active
            return active
        }
        return refreshSession(active)
    }

    suspend fun fetchTodaysTimetable(
        session: StoredSession,
        targetDate: LocalDate = LocalDate.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<Lesson> {
        val base = instituteBaseUrl(session.instituteCode)
        val fromStr = targetDate.toString()
        val toStr = targetDate.plusDays(1).toString()
        val url = "$base${KretaSharedConfig.ENDPOINT_TIMETABLE}?datumTol=$fromStr&datumIg=$toStr"
        val body = getAuthenticatedBody(session, url)
        if (body.isBlank()) return emptyList()

        val array = JSONArray(body)
        return array.toJsonObjectList()
            .map { Lesson.fromJson(it) }
            .filter { KretaDateParser.isSameLocalDay(it.startEpochMs, targetDate, zoneId) }
            .sortedBy { it.startEpochMs }
    }

    suspend fun fetchUpcomingTimetable(
        session: StoredSession,
        startDate: LocalDate = LocalDate.now(),
        daysAhead: Int = DEFAULT_UPCOMING_DAYS,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<Lesson> {
        val base = instituteBaseUrl(session.instituteCode)
        val endDate = startDate.plusDays(daysAhead.toLong().coerceAtLeast(1L))
        val fromStr = startDate.toString()
        val toStr = endDate.toString()
        val url = "$base${KretaSharedConfig.ENDPOINT_TIMETABLE}?datumTol=$fromStr&datumIg=$toStr"
        val body = getAuthenticatedBody(session, url)
        if (body.isBlank()) return emptyList()

        val array = JSONArray(body)
        return array.toJsonObjectList()
            .map { Lesson.fromJson(it) }
            .filter {
                val lessonDay = KretaDateParser.localDateFor(it.startEpochMs, zoneId)
                !lessonDay.isBefore(startDate) && !lessonDay.isAfter(endDate)
            }
            .sortedBy { it.startEpochMs }
    }

    suspend fun fetchHomeworks(
        session: StoredSession,
        referenceDate: LocalDate = LocalDate.now(),
    ): List<Homework> {
        val firstDay = firstSchoolDay(referenceDate)
        val base = instituteBaseUrl(session.instituteCode)
        val url = "$base${KretaSharedConfig.ENDPOINT_HOMEWORKS}?datumTol=$firstDay"
        val body = getAuthenticatedBody(session, url)
        if (body.isBlank()) return emptyList()

        val array = JSONArray(body)
        return array.toJsonObjectList()
            .map { Homework.fromJson(it) }
            .sortedByDescending { it.creationDateEpochMs }
    }

    suspend fun fetchAllGrades(session: StoredSession): List<Grade> {
        val base = instituteBaseUrl(session.instituteCode)
        val url = "$base${KretaSharedConfig.ENDPOINT_GRADES}"
        val body = getAuthenticatedBody(session, url)
        if (body.isBlank()) return emptyList()

        val array = JSONArray(body)
        return array.toJsonObjectList()
            .map { Grade.fromJson(it) }
            .sortedByDescending { it.recordedAtEpochMs }
    }

    suspend fun fetchUpcomingExams(
        session: StoredSession,
        startDate: LocalDate = LocalDate.now(),
        daysAhead: Int = DEFAULT_EXAMS_DAYS_AHEAD,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<Exam> {
        val base = instituteBaseUrl(session.instituteCode)
        val endDate = startDate.plusDays(daysAhead.toLong().coerceAtLeast(1L))
        val url = "$base${KretaSharedConfig.ENDPOINT_TESTS}?datumTol=$startDate&datumIg=$endDate"
        val body = getAuthenticatedBody(session, url)
        if (body.isBlank()) return emptyList()

        val array = JSONArray(body)
        return array.toJsonObjectList()
            .map { Exam.fromJson(it, zoneId) }
            .filter { !KretaDateParser.localDateFor(it.dateEpochMs, zoneId).isBefore(startDate) }
            .sortedWith(compareBy<Exam>({ it.dateEpochMs }, { it.lessonNumber ?: Int.MAX_VALUE }))
    }

    suspend fun syncAll(
        session: StoredSession,
        targetDate: LocalDate = LocalDate.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): CachedWearData = coroutineScope {
        val validSession = ensureValidSession(session)
        val dateKey = targetDate.toString()
        val initialAccountKey = SecureTokenStorage.accountKeyFor(latestSession ?: validSession)
        val existingCache = tokenStore.loadWearDataCache(initialAccountKey, dateKey)

        val lessonsDeferred = async {
            fetchUpcomingTimetable(validSession, targetDate, daysAhead = DEFAULT_UPCOMING_DAYS, zoneId = zoneId)
        }
        val gradesDeferred = async {
            try {
                fetchAllGrades(validSession)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Exception) {
                existingCache?.grades ?: emptyList()
            }
        }
        val homeworksDeferred = async {
            try {
                fetchHomeworks(validSession, targetDate)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Exception) {
                existingCache?.homeworks ?: emptyList()
            }
        }
        val examsDeferred = async {
            try {
                fetchUpcomingExams(validSession, targetDate, zoneId = zoneId)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: Exception) {
                existingCache?.exams ?: emptyList()
            }
        }

        val lessons = lessonsDeferred.await()
        val grades = gradesDeferred.await()
        val homeworks = homeworksDeferred.await()
        val exams = examsDeferred.await()

        val syncedAt = System.currentTimeMillis()
        val effectiveSession = latestSession ?: tokenStore.loadSession() ?: validSession
        val accountKey = SecureTokenStorage.accountKeyFor(effectiveSession)
        tokenStore.saveWearDataCache(
            accountKey = accountKey,
            dateKey = dateKey,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            exams = exams,
            syncedAtEpochMs = syncedAt,
            studentName = effectiveSession.studentName,
            studentUid = effectiveSession.studentUid,
            instituteName = effectiveSession.instituteName,
            instituteCode = effectiveSession.instituteCode,
            schoolYearUid = effectiveSession.schoolYearUid,
            userName = effectiveSession.userName,
        )

        CachedWearData(
            dateKey = dateKey,
            syncedAtEpochMs = syncedAt,
            lessons = lessons,
            homeworks = homeworks,
            grades = grades,
            exams = exams,
            studentName = effectiveSession.studentName,
            studentUid = effectiveSession.studentUid,
            instituteName = effectiveSession.instituteName,
            instituteCode = effectiveSession.instituteCode,
            schoolYearUid = effectiveSession.schoolYearUid,
            userName = effectiveSession.userName,
        )
    }

    fun resetMemoryCache() {
        latestSession = null
    }

    private suspend fun getAuthenticatedBody(session: StoredSession, url: String): String {
        var active = ensureValidSession(session)
        var resp = withContext(Dispatchers.IO) {
            executeRequest(
                method = "GET",
                urlString = url,
                headers = apiHeaders(active.accessToken),
            )
        }
        if (resp.statusCode == 401) {
            active = refreshSession(active)
            resp = withContext(Dispatchers.IO) {
                executeRequest(
                    method = "GET",
                    urlString = url,
                    headers = apiHeaders(active.accessToken),
                )
            }
            if (resp.statusCode == 401) {
                throw InvalidGrantException()
            }
        }
        if (resp.statusCode != 200) {
            throw KretaApiException(resp.statusCode, "GET $url sikertelen (HTTP ${resp.statusCode})")
        }
        return resp.body.trim()
    }

    private fun apiHeaders(accessToken: String): Map<String, String> = mapOf(
        "Accept" to "application/json, */*",
        "User-Agent" to KretaSharedConfig.USER_AGENT,
        "Authorization" to "Bearer $accessToken",
        "apiKey" to KretaSharedConfig.API_KEY,
    )

    private data class HttpResponse(val statusCode: Int, val body: String)

    private fun executeRequest(
        method: String,
        urlString: String,
        headers: Map<String, String>,
        body: String? = null,
    ): HttpResponse {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 12_000
            readTimeout = 15_000
            instanceFollowRedirects = false
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            if (body != null) {
                doOutput = true
            }
        }
        return try {
            if (body != null) {
                conn.outputStream.use { os ->
                    os.write(body.toByteArray(StandardCharsets.UTF_8))
                }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
            HttpResponse(code, text)
        } catch (e: IOException) {
            throw e
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val DEFAULT_UPCOMING_DAYS = 10
        private const val DEFAULT_EXAMS_DAYS_AHEAD = 30
        private val globalRefreshMutex = Mutex()

        fun firstSchoolDay(reference: LocalDate = LocalDate.now()): LocalDate {
            val sept1 = LocalDate.of(reference.year, 9, 1)
            return if (reference.isBefore(sept1)) {
                LocalDate.of(reference.year - 1, 9, 1)
            } else {
                sept1
            }
        }

        private fun encodeForm(fields: Map<String, String>): String =
            fields.entries.joinToString("&") { (k, v) ->
                "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
            }
    }
}
