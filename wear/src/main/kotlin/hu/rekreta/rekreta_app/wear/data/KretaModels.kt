package hu.rekreta.rekreta_app.wear.data

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Base64
import kotlin.math.ceil

object JwtPayloadDecoder {
    private val urlDecoder = Base64.getUrlDecoder()

    fun decodeJwtPayload(jwt: String): JSONObject {
        val parts = jwt.split('.')
        if (parts.size < 2) return JSONObject()
        return runCatching {
            val rawPayload = parts[1]
            val rem = rawPayload.length % 4
            val padded = if (rem == 0) rawPayload else rawPayload + "=".repeat(4 - rem)
            val payloadBytes = urlDecoder.decode(padded)
            JSONObject(String(payloadBytes, StandardCharsets.UTF_8))
        }.getOrDefault(JSONObject())
    }
}

data class StoredSession(
    val accessToken: String,
    val refreshToken: String,
    val idToken: String,
    val instituteCode: String,
    val userName: String?,
    val expiresAtEpochMs: Long,
    val studentName: String? = null,
    val studentUid: String? = null,
    val instituteName: String? = null,
    val schoolYearUid: String? = null,
) {
    fun isExpired(nowMs: Long = System.currentTimeMillis()): Boolean =
        accessToken.isBlank() || nowMs >= (expiresAtEpochMs - 60_000L)

    fun toJson(): JSONObject = JSONObject().apply {
        put("accessToken", accessToken)
        put("refreshToken", refreshToken)
        put("idToken", idToken)
        put("instituteCode", instituteCode)
        put("userName", userName ?: "")
        put("expiresAtEpochMs", expiresAtEpochMs)
        put("studentName", studentName ?: "")
        put("studentUid", studentUid ?: "")
        put("instituteName", instituteName ?: "")
        put("schoolYearUid", schoolYearUid ?: "")
    }

    companion object {
        fun fromJson(json: JSONObject): StoredSession? {
            val access = json.optString("accessToken", "").trim()
            val refresh = json.optString("refreshToken", "").trim()
            val inst = json.optString("instituteCode", "").trim()
            if (refresh.isEmpty() || inst.isEmpty()) return null
            val user = json.optString("userName", "").trim().ifEmpty { null }
            return StoredSession(
                accessToken = access,
                refreshToken = refresh,
                idToken = json.optString("idToken", ""),
                instituteCode = inst,
                userName = user,
                expiresAtEpochMs = json.optLong("expiresAtEpochMs", 0L),
                studentName = json.optNullableString("studentName"),
                studentUid = json.optNullableString("studentUid"),
                instituteName = json.optNullableString("instituteName"),
                schoolYearUid = json.optNullableString("schoolYearUid"),
            )
        }

        fun fromTokenGrantJson(
            json: JSONObject,
            fallbackInstituteCode: String? = null,
            fallbackRefreshToken: String? = null,
            fallbackUserName: String? = null,
            studentName: String? = null,
            studentUid: String? = null,
            instituteName: String? = null,
            schoolYearUid: String? = null,
            nowMs: Long = System.currentTimeMillis(),
        ): StoredSession {
            val accessToken = json.optString("access_token", "").trim()
            val refreshToken = json.optString("refresh_token", "").trim()
                .ifEmpty { fallbackRefreshToken?.trim().orEmpty() }
            val idToken = json.optString("id_token", "")
            val expiresInSec = json.optLong("expires_in", 1800L)

            val idClaims = JwtPayloadDecoder.decodeJwtPayload(idToken)
            val accessClaims = JwtPayloadDecoder.decodeJwtPayload(accessToken)

            fun claim(key: String): String? {
                val fromAccess = accessClaims.optString(key, "").trim()
                if (fromAccess.isNotEmpty()) return fromAccess
                val fromId = idClaims.optString(key, "").trim()
                return fromId.ifEmpty { null }
            }

            val resolvedInstitute = claim("kreta:institute_code")
                ?: claim("institute_code")
                ?: fallbackInstituteCode?.trim()?.takeIf { it.isNotEmpty() }
                ?: throw IllegalStateException("Nem sikerült meghatározni az intézménykódot a tokenből.")

            val resolvedUser = claim("kreta:user_name")
                ?: claim("sub")
                ?: fallbackUserName?.trim()?.takeIf { it.isNotEmpty() }
            val resolvedName = studentName?.trim()?.ifEmpty { null }
                ?: claim("name")
            val expClaim = accessClaims.optLong("exp", 0L).takeIf { it > 0L }
                ?: idClaims.optLong("exp", 0L).takeIf { it > 0L }
            val expiresAtMs = expClaim?.times(1000L) ?: (nowMs + expiresInSec * 1000L)

            return StoredSession(
                accessToken = accessToken,
                refreshToken = refreshToken,
                idToken = idToken,
                instituteCode = resolvedInstitute,
                userName = resolvedUser,
                expiresAtEpochMs = expiresAtMs,
                studentName = resolvedName,
                studentUid = studentUid?.trim()?.ifEmpty { null },
                instituteName = instituteName?.trim()?.ifEmpty { null },
                schoolYearUid = schoolYearUid?.trim()?.ifEmpty { null },
            )
        }
    }
}

data class AuthSessionPayload(
    val accessToken: String,
    val refreshToken: String,
    val idToken: String,
    val instituteCode: String,
    val userName: String?,
    val expiresAtEpochMs: Long,
    val studentName: String?,
    val studentUid: String?,
    val instituteName: String?,
    val schoolYearUid: String?,
    val syncedAtEpochMs: Long,
    val forceSync: Boolean,
) {
    fun mergeInto(existing: StoredSession?): StoredSession {
        val sameAccount = existing != null &&
            existing.instituteCode.equals(instituteCode, ignoreCase = true) &&
            (userName == null || existing.userName == null || existing.userName == userName)

        val keepExistingTokens = sameAccount &&
            !forceSync &&
            existing!!.refreshToken.isNotBlank() &&
            !existing.isExpired() &&
            existing.expiresAtEpochMs > expiresAtEpochMs

        val effectiveAccess = if (keepExistingTokens) existing!!.accessToken else accessToken
        val effectiveRefresh = if (keepExistingTokens) existing!!.refreshToken else refreshToken
        val effectiveIdToken = if (keepExistingTokens) {
            existing!!.idToken
        } else {
            idToken.ifEmpty { existing?.idToken.orEmpty() }
        }
        val effectiveExpiresAt = if (keepExistingTokens) {
            existing!!.expiresAtEpochMs
        } else if (effectiveAccess.isBlank()) {
            0L
        } else {
            expiresAtEpochMs
        }

        return StoredSession(
            accessToken = effectiveAccess,
            refreshToken = effectiveRefresh,
            idToken = effectiveIdToken,
            instituteCode = instituteCode,
            userName = userName ?: existing?.userName,
            expiresAtEpochMs = effectiveExpiresAt,
            studentName = studentName ?: existing?.studentName,
            studentUid = studentUid ?: existing?.studentUid,
            instituteName = instituteName ?: existing?.instituteName,
            schoolYearUid = schoolYearUid ?: existing?.schoolYearUid,
        )
    }

    companion object {
        fun fromMap(values: Map<String, Any?>): AuthSessionPayload? {
            fun str(key: String): String = values[key]?.toString()?.trim().orEmpty()
            fun optStr(key: String): String? = str(key).ifEmpty { null }
            fun longVal(key: String): Long = when (val raw = values[key]) {
                is Number -> raw.toLong()
                is String -> raw.toLongOrNull() ?: 0L
                else -> 0L
            }
            fun boolVal(key: String): Boolean = when (val raw = values[key]) {
                is Boolean -> raw
                is String -> raw.equals("true", ignoreCase = true)
                else -> false
            }

            val refreshToken = str("refresh_token")
            val accessToken = str("access_token")
            val idToken = str("id_token")
            val accessClaims = if (accessToken.isNotEmpty()) JwtPayloadDecoder.decodeJwtPayload(accessToken) else JSONObject()
            val idClaims = if (idToken.isNotEmpty()) JwtPayloadDecoder.decodeJwtPayload(idToken) else JSONObject()

            val instituteCode = str("institute_code")
                .ifEmpty { accessClaims.optString("kreta:institute_code", "").trim() }
                .ifEmpty { idClaims.optString("kreta:institute_code", "").trim() }
            if (refreshToken.isEmpty() || instituteCode.isEmpty()) {
                return null
            }

            val userName = optStr("user_name")
                ?: accessClaims.optString("kreta:user_name", "").trim().ifEmpty { null }
                ?: accessClaims.optString("sub", "").trim().ifEmpty { null }

            val expClaimMs = accessClaims.optLong("exp", 0L).takeIf { it > 0L }?.times(1000L)
            val expiresAt = longVal("expires_at_ms").takeIf { it > 0L }
                ?: expClaimMs
                ?: 0L

            return AuthSessionPayload(
                accessToken = accessToken,
                refreshToken = refreshToken,
                idToken = idToken,
                instituteCode = instituteCode,
                userName = userName,
                expiresAtEpochMs = expiresAt,
                studentName = optStr("student_name"),
                studentUid = optStr("student_uid"),
                instituteName = optStr("institute_name"),
                schoolYearUid = optStr("school_year_uid"),
                syncedAtEpochMs = longVal("synced_at_ms"),
                forceSync = boolVal("force_sync"),
            )
        }
    }
}

data class Homework(
    val uid: String,
    val subjectUid: String,
    val subjectName: String,
    val description: String,
    val startDateEpochMs: Long,
    val dueDateEpochMs: Long,
    val creationDateEpochMs: Long,
    val isDone: Boolean,
) {
    val leadId: String
        get() = uid.substringBefore(',').trim()

    fun toJson(): JSONObject = JSONObject().apply {
        put("Uid", uid)
        put("Tantargy", JSONObject().apply {
            put("Uid", subjectUid)
            put("Nev", subjectName)
        })
        put("TantargyNeve", subjectName)
        put("Szoveg", description)
        put("FeladasDatuma", Instant.ofEpochMilli(startDateEpochMs).toString())
        put("HataridoDatuma", Instant.ofEpochMilli(dueDateEpochMs).toString())
        put("RogzitesIdopontja", Instant.ofEpochMilli(creationDateEpochMs).toString())
        put("IsMegoldva", isDone)
    }

    companion object {
        fun fromJson(json: JSONObject): Homework {
            val tantargy = json.optJSONObject("Tantargy")
            val subjUid = tantargy?.optString("Uid", "")?.trim().orEmpty()
            val subjName = json.optString("TantargyNeve", "").trim()
                .ifEmpty { tantargy?.optString("Nev", "")?.trim().orEmpty() }
            val startMs = KretaDateParser.parseEpochMillis(json.optString("FeladasDatuma", ""))
                ?: KretaDateParser.parseEpochMillis(json.optString("RogzitesIdopontja", ""))
                ?: KretaDateParser.parseEpochMillis(json.optString("HataridoDatuma", ""))
                ?: System.currentTimeMillis()
            val dueMs = KretaDateParser.parseEpochMillis(json.optString("HataridoDatuma", "")) ?: startMs
            val createdMs = KretaDateParser.parseEpochMillis(json.optString("RogzitesIdopontja", "")) ?: startMs

            return Homework(
                uid = json.optString("Uid", json.optString("Id", "")).trim(),
                subjectUid = subjUid,
                subjectName = subjName.ifEmpty { "Házi feladat" },
                description = stripHtmlTags(json.optString("Szoveg", "")),
                startDateEpochMs = startMs,
                dueDateEpochMs = dueMs,
                creationDateEpochMs = createdMs,
                isDone = json.optBoolean("IsMegoldva", false),
            )
        }

        fun stripHtmlTags(raw: String): String {
            if (raw.isBlank()) return ""
            return raw
                .replace(Regex("<\\s*br\\s*/?\\s*>", RegexOption.IGNORE_CASE), "\n")
                .replace(Regex("</\\s*(p|div|li)\\s*>", RegexOption.IGNORE_CASE), "\n")
                .replace(Regex("<[^>]*>"), "")
                .replace("&nbsp;", " ")
                .replace("&amp;", "&")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replace("&apos;", "'")
                .replace("&ndash;", "–")
                .replace("&mdash;", "—")
                .lines()
                .joinToString("\n") { it.trim() }
                .replace(Regex("\\n{3,}"), "\n\n")
                .trim()
        }
    }
}

data class Lesson(
    val uid: String,
    val date: String,
    val startEpochMs: Long,
    val endEpochMs: Long,
    val name: String,
    val lessonNumber: Int?,
    val subjectUid: String?,
    val subjectName: String?,
    val roomName: String?,
    val teacher: String?,
    val substituteTeacher: String?,
    val theme: String?,
    val stateName: String,
    val stateDescription: String,
    val homeworkUid: String?,
    val isHomeworkComplete: Boolean,
) {
    val displaySubject: String
        get() = subjectName?.trim()?.takeIf { it.isNotEmpty() }
            ?: name.trim().takeIf { it.isNotEmpty() }
            ?: "Tanóra"

    val cleanRoomName: String?
        get() = roomName?.trim()?.takeIf { it.isNotEmpty() }

    val cleanTeacher: String?
        get() = teacher?.trim()?.takeIf { it.isNotEmpty() }

    val cleanSubstituteTeacher: String?
        get() = substituteTeacher?.trim()?.takeIf { it.isNotEmpty() }

    val isCancelled: Boolean
        get() {
            val sName = stateName.lowercase().trim()
            val sDesc = stateDescription.lowercase().trim()
            return sName == "elmaradt" || sName.contains("elmarad") || sDesc.contains("elmarad")
        }

    val isSubstituted: Boolean
        get() = !isCancelled && !cleanSubstituteTeacher.isNullOrEmpty()

    val hasHomeworkReference: Boolean
        get() = !homeworkUid.isNullOrBlank() && !isHomeworkComplete

    val timeRangeLabel: String
        get() = "${KretaDateParser.formatHm(startEpochMs)} – ${KretaDateParser.formatHm(endEpochMs)}"

    val compactTimeRangeLabel: String
        get() = "${KretaDateParser.formatHm(startEpochMs)}–${KretaDateParser.formatHm(endEpochMs)}"

    fun periodAndSubjectLabel(): String =
        if (lessonNumber != null) "$lessonNumber. $displaySubject" else displaySubject

    fun periodSubjectRoomBadge(): String {
        val base = periodAndSubjectLabel()
        val room = cleanRoomName
        return if (room != null) "$base • $room" else base
    }

    fun matchedHomework(homeworks: List<Homework>, zoneId: ZoneId = ZoneId.systemDefault()): Homework? {
        val hwUid = homeworkUid?.trim().orEmpty()
        if (hwUid.isNotEmpty()) {
            val hwLead = hwUid.substringBefore(',').trim()
            homeworks.firstOrNull {
                it.uid == hwUid || (hwLead.isNotEmpty() && it.leadId == hwLead)
            }?.let { return it }
        }

        val lessonDay = Instant.ofEpochMilli(startEpochMs).atZone(zoneId).toLocalDate()
        val subjUid = subjectUid?.trim().orEmpty()
        val subjName = displaySubject.trim().lowercase()
        return homeworks.firstOrNull { hw ->
            val sameSubject = (subjUid.isNotEmpty() && hw.subjectUid == subjUid) ||
                hw.subjectName.trim().lowercase() == subjName
            if (!sameSubject) return@firstOrNull false
            val hwStartDay = Instant.ofEpochMilli(hw.startDateEpochMs).atZone(zoneId).toLocalDate()
            val hwDueDay = Instant.ofEpochMilli(hw.dueDateEpochMs).atZone(zoneId).toLocalDate()
            hwStartDay == lessonDay || hwDueDay == lessonDay
        }
    }

    fun hasActiveHomework(homeworks: List<Homework>, zoneId: ZoneId = ZoneId.systemDefault()): Boolean {
        val hw = matchedHomework(homeworks, zoneId)
        if (hw != null) return !hw.isDone
        return hasHomeworkReference
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("Uid", uid)
        put("Datum", date)
        put("KezdetIdopont", Instant.ofEpochMilli(startEpochMs).toString())
        put("VegIdopont", Instant.ofEpochMilli(endEpochMs).toString())
        put("Nev", name)
        if (lessonNumber != null) put("Oraszam", lessonNumber)
        if (subjectName != null || subjectUid != null) {
            put("Tantargy", JSONObject().apply {
                put("Uid", subjectUid ?: "")
                put("Nev", subjectName ?: "")
            })
        }
        put("TeremNeve", roomName)
        put("TanarNeve", teacher)
        put("HelyettesTanarNeve", substituteTeacher)
        put("Tema", theme)
        put("HaziFeladatUid", homeworkUid)
        put("IsHaziFeladatMegoldva", isHomeworkComplete)
        put("Allapot", JSONObject().apply {
            put("Nev", stateName)
            put("Leiras", stateDescription)
        })
    }

    companion object {
        fun fromJson(json: JSONObject): Lesson {
            val tantargy = json.optJSONObject("Tantargy")
            val subjUid = tantargy?.optString("Uid", "")?.trim()?.ifEmpty { null }
            val subjName = tantargy?.optString("Nev", "")?.trim()?.ifEmpty { null }
            val allapot = json.optJSONObject("Allapot")
            val stateName = allapot?.optString("Nev", "").orEmpty()
            val stateDesc = allapot?.optString("Leiras", "").orEmpty()

            val startMs = KretaDateParser.parseEpochMillis(json.optString("KezdetIdopont", ""))
                ?: System.currentTimeMillis()
            val endMs = KretaDateParser.parseEpochMillis(json.optString("VegIdopont", ""))
                ?: (startMs + 45L * 60_000L)

            val lessonNum = if (json.has("Oraszam") && !json.isNull("Oraszam")) {
                json.optInt("Oraszam")
            } else {
                null
            }

            return Lesson(
                uid = json.optString("Uid", ""),
                date = json.optString("Datum", ""),
                startEpochMs = startMs,
                endEpochMs = endMs,
                name = json.optString("Nev", ""),
                lessonNumber = lessonNum,
                subjectUid = subjUid,
                subjectName = subjName,
                roomName = json.optNullableString("TeremNeve"),
                teacher = json.optNullableString("TanarNeve"),
                substituteTeacher = json.optNullableString("HelyettesTanarNeve"),
                theme = json.optNullableString("Tema"),
                stateName = stateName,
                stateDescription = stateDesc,
                homeworkUid = json.optNullableString("HaziFeladatUid"),
                isHomeworkComplete = json.optBoolean("IsHaziFeladatMegoldva", false),
            )
        }
    }
}

data class Grade(
    val uid: String,
    val subjectUid: String,
    val subjectName: String,
    val topic: String?,
    val modeDescription: String?,
    val typeDescription: String,
    val teacher: String,
    val numericValue: Int?,
    val strValue: String,
    val shortStrValue: String?,
    val weightPercentage: Int?,
    val recordedAtEpochMs: Long,
) {
    val displayValue: String
        get() = numericValue?.toString()
            ?: shortStrValue?.takeIf { it.isNotBlank() }
            ?: strValue.ifBlank { "•" }

    fun toJson(): JSONObject = JSONObject().apply {
        put("Uid", uid)
        put("KeszitesDatuma", Instant.ofEpochMilli(recordedAtEpochMs).toString())
        put("RogzitesDatuma", Instant.ofEpochMilli(recordedAtEpochMs).toString())
        put("Tantargy", JSONObject().apply {
            put("Uid", subjectUid)
            put("Nev", subjectName)
        })
        put("Tema", topic)
        put("Mod", modeDescription?.let { JSONObject().put("Leiras", it) })
        put("Tipus", JSONObject().put("Leiras", typeDescription))
        put("ErtekeloTanarNeve", teacher)
        if (numericValue != null) put("SzamErtek", numericValue)
        put("SzovegesErtek", strValue)
        put("SzovegesErtekelesRovidNev", shortStrValue)
        if (weightPercentage != null) put("SulySzazalekErteke", weightPercentage)
    }

    companion object {
        fun fromJson(json: JSONObject, zoneId: ZoneId = ZoneId.systemDefault()): Grade {
            val tantargy = json.optJSONObject("Tantargy")
            val subjUid = tantargy?.optString("Uid", "")?.trim().orEmpty()
            val subjName = tantargy?.optString("Nev", "")?.trim().orEmpty().ifEmpty { "Tantárgy" }
            val createdMs = KretaDateParser.parseEpochMillis(json.optString("KeszitesDatuma", ""), zoneId)
            val recordMs = KretaDateParser.parseEpochMillis(json.optString("RogzitesDatuma", ""), zoneId)
            val effectiveMs = resolveRecordedAt(createdMs, recordMs, zoneId)

            val numVal = if (json.has("SzamErtek") && !json.isNull("SzamErtek")) {
                json.optInt("SzamErtek")
            } else {
                null
            }
            val weight = if (json.has("SulySzazalekErteke") && !json.isNull("SulySzazalekErteke")) {
                json.optInt("SulySzazalekErteke")
            } else {
                null
            }

            return Grade(
                uid = json.optString("Uid", ""),
                subjectUid = subjUid.ifEmpty { subjName },
                subjectName = subjName,
                topic = json.optNullableString("Tema"),
                modeDescription = json.optJSONObject("Mod")?.optNullableString("Leiras"),
                typeDescription = json.optJSONObject("Tipus")?.optString("Leiras", "")?.trim().orEmpty(),
                teacher = json.optString("ErtekeloTanarNeve", "").trim(),
                numericValue = numVal,
                strValue = json.optString("SzovegesErtek", "").trim(),
                shortStrValue = json.optNullableString("SzovegesErtekelesRovidNev"),
                weightPercentage = weight,
                recordedAtEpochMs = effectiveMs,
            )
        }

        private fun resolveRecordedAt(
            createdMs: Long?,
            recordMs: Long?,
            zoneId: ZoneId,
        ): Long {
            val c = createdMs ?: recordMs ?: System.currentTimeMillis()
            val r = recordMs ?: return c
            val createdLocal = Instant.ofEpochMilli(c).atZone(zoneId).toLocalTime()
            val recordLocal = Instant.ofEpochMilli(r).atZone(zoneId).toLocalTime()
            return if (createdLocal.hour == 0 && createdLocal.minute == 0 && createdLocal.second == 0 &&
                (recordLocal.hour != 0 || recordLocal.minute != 0 || recordLocal.second != 0)
            ) {
                r
            } else {
                c
            }
        }
    }
}

data class SubjectAverageSummary(
    val subjectKey: String,
    val subjectName: String,
    val weightedAverage: Double?,
    val gradeCount: Int,
    val latestGrade: Grade,
)

object GradeAnalytics {
    fun computeWeightedAverage(grades: List<Grade>): Double? {
        var weightedSum = 0.0
        var totalWeight = 0.0
        for (grade in grades) {
            val v = grade.numericValue ?: continue
            if (v !in 1..5) continue
            val weight = if (grade.weightPercentage != null && grade.weightPercentage > 0) {
                grade.weightPercentage.toDouble()
            } else {
                100.0
            }
            weightedSum += v * weight
            totalWeight += weight
        }
        return if (totalWeight > 0.0) weightedSum / totalWeight else null
    }

    fun summarizeBySubject(grades: List<Grade>): List<SubjectAverageSummary> {
        if (grades.isEmpty()) return emptyList()
        val sorted = grades.sortedByDescending { it.recordedAtEpochMs }
        return sorted
            .groupBy { it.subjectUid.ifBlank { it.subjectName } }
            .map { (key, list) ->
                SubjectAverageSummary(
                    subjectKey = key,
                    subjectName = list.first().subjectName,
                    weightedAverage = computeWeightedAverage(list),
                    gradeCount = list.size,
                    latestGrade = list.first(),
                )
            }
            .sortedBy { it.subjectName.lowercase() }
    }

    fun computeOverallSubjectAverage(summaries: List<SubjectAverageSummary>): Double? {
        val valid = summaries.mapNotNull { it.weightedAverage }
        if (valid.isEmpty()) return null
        return valid.sum() / valid.size
    }
}

enum class TimetablePhase {
    ACTIVE_LESSON,
    BREAK,
    BEFORE_FIRST_LESSON,
    AFTER_SCHOOL,
    NO_CLASSES_TODAY,
}

data class TimetableStatus(
    val phase: TimetablePhase,
    val badgeLabel: String,
    val titleLabel: String,
    val subtitleLabel: String,
    val roomLabel: String?,
    val remainingMillis: Long?,
    val remainingFraction: Float,
    val currentLesson: Lesson?,
    val nextLesson: Lesson?,
    val upcomingLessons: List<Lesson>,
    val phaseStartEpochMs: Long? = null,
    val phaseEndEpochMs: Long? = null,
) {
    fun remainingMillisAt(nowEpochMs: Long): Long? {
        val endMs = phaseEndEpochMs ?: return remainingMillis
        return (endMs - nowEpochMs).coerceAtLeast(0L)
    }

    fun remainingFractionAt(nowEpochMs: Long): Float {
        val startMs = phaseStartEpochMs ?: return remainingFraction
        val endMs = phaseEndEpochMs ?: return remainingFraction
        val total = (endMs - startMs).coerceAtLeast(1L)
        return ((endMs - nowEpochMs).toDouble() / total.toDouble()).toFloat().coerceIn(0f, 1f)
    }
}

data class RolloverTimetableState(
    val todayStatus: TimetableStatus,
    val isRolledOverToNextDay: Boolean,
    val displayDate: LocalDate,
    val displayDayPillLabel: String,
    val page1DayBadgeLabel: String?,
    val displayLessons: List<Lesson>,
    val previewFirstLesson: Lesson?,
    val previewSecondLesson: Lesson?,
)

object TimetableStatusEvaluator {
    private const val PRE_SCHOOL_WINDOW_MS = 60L * 60_000L

    @JvmOverloads
    fun evaluate(
        lessons: List<Lesson>,
        nowEpochMs: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): TimetableStatus {
        val sampleDate = KretaDateParser.localDateFor(nowEpochMs, zoneId)
        val todaysLessons = lessons.filter { KretaDateParser.isSameLocalDay(it.startEpochMs, sampleDate, zoneId) }
        val active = todaysLessons.filter { !it.isCancelled }.sortedBy { it.startEpochMs }
        if (active.isEmpty()) {
            val allCancelled = todaysLessons.isNotEmpty()
            return TimetableStatus(
                phase = if (allCancelled) TimetablePhase.AFTER_SCHOOL else TimetablePhase.NO_CLASSES_TODAY,
                badgeLabel = "Ma",
                titleLabel = if (allCancelled) "Nincs több óra ma" else "Ma nincs tanóra",
                subtitleLabel = if (allCancelled) "Mai órák elmaradtak" else "Szabadnap",
                roomLabel = null,
                remainingMillis = null,
                remainingFraction = 0f,
                currentLesson = null,
                nextLesson = null,
                upcomingLessons = emptyList(),
            )
        }

        // 1. Active ongoing lesson: start <= now < end
        for (i in active.indices) {
            val lesson = active[i]
            if (nowEpochMs in lesson.startEpochMs until lesson.endEpochMs) {
                val totalMs = (lesson.endEpochMs - lesson.startEpochMs).coerceAtLeast(1L)
                val remMs = (lesson.endEpochMs - nowEpochMs).coerceAtLeast(0L)
                val fraction = (remMs.toDouble() / totalMs.toDouble()).toFloat().coerceIn(0f, 1f)
                val upcoming = active.drop(i + 1).filter { it.startEpochMs >= lesson.endEpochMs }.take(2)
                return TimetableStatus(
                    phase = TimetablePhase.ACTIVE_LESSON,
                    badgeLabel = lesson.lessonNumber?.let { "MOST • $it. óra" } ?: "MOST",
                    titleLabel = lesson.displaySubject,
                    subtitleLabel = lesson.compactTimeRangeLabel,
                    roomLabel = lesson.cleanRoomName,
                    remainingMillis = remMs,
                    remainingFraction = fraction,
                    currentLesson = lesson,
                    nextLesson = upcoming.firstOrNull(),
                    upcomingLessons = upcoming,
                    phaseStartEpochMs = lesson.startEpochMs,
                    phaseEndEpochMs = lesson.endEpochMs,
                )
            }
        }

        // 2. Before first lesson
        val first = active.first()
        if (nowEpochMs < first.startEpochMs) {
            val remMs = (first.startEpochMs - nowEpochMs).coerceAtLeast(0L)
            val fraction = (remMs.toDouble() / PRE_SCHOOL_WINDOW_MS.toDouble()).toFloat().coerceIn(0f, 1f)
            val upcoming = active.drop(1).filter { it.startEpochMs >= first.endEpochMs }.take(2)
            return TimetableStatus(
                phase = TimetablePhase.BEFORE_FIRST_LESSON,
                badgeLabel = first.lessonNumber?.let { "KÖVI • $it. óra" } ?: "ELSŐ ÓRA",
                titleLabel = first.displaySubject,
                subtitleLabel = first.compactTimeRangeLabel,
                roomLabel = first.cleanRoomName,
                remainingMillis = remMs,
                remainingFraction = fraction,
                currentLesson = null,
                nextLesson = first,
                upcomingLessons = upcoming,
                phaseStartEpochMs = first.startEpochMs - PRE_SCHOOL_WINDOW_MS,
                phaseEndEpochMs = first.startEpochMs,
            )
        }

        // 3. Break between lessons
        val nextIdx = active.indexOfFirst { it.startEpochMs > nowEpochMs }
        if (nextIdx > 0) {
            val prev = active[nextIdx - 1]
            val next = active[nextIdx]
            val totalMs = (next.startEpochMs - prev.endEpochMs).coerceAtLeast(1L)
            val remMs = (next.startEpochMs - nowEpochMs).coerceAtLeast(0L)
            val fraction = (remMs.toDouble() / totalMs.toDouble()).toFloat().coerceIn(0f, 1f)
            val upcomingAfterNext = active.drop(nextIdx).take(2)
            return TimetableStatus(
                phase = TimetablePhase.BREAK,
                badgeLabel = "SZÜNET",
                titleLabel = "Következik: ${next.periodAndSubjectLabel()}",
                subtitleLabel = "${KretaDateParser.formatHm(prev.endEpochMs)}–${KretaDateParser.formatHm(next.startEpochMs)}",
                roomLabel = next.cleanRoomName,
                remainingMillis = remMs,
                remainingFraction = fraction,
                currentLesson = null,
                nextLesson = next,
                upcomingLessons = upcomingAfterNext,
                phaseStartEpochMs = prev.endEpochMs,
                phaseEndEpochMs = next.startEpochMs,
            )
        }

        // 4. After all lessons
        return TimetableStatus(
            phase = TimetablePhase.AFTER_SCHOOL,
            badgeLabel = "KÉSZ",
            titleLabel = "Nincs több óra ma",
            subtitleLabel = "${active.size} tanóra lezárult",
            roomLabel = null,
            remainingMillis = null,
            remainingFraction = 0f,
            currentLesson = null,
            nextLesson = null,
            upcomingLessons = emptyList(),
        )
    }

    @JvmOverloads
    fun millisUntilNextTransition(
        lessons: List<Lesson>,
        nowEpochMs: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): Long {
        val nextMidnightMs = KretaDateParser.localDateFor(nowEpochMs, zoneId)
            .plusDays(1)
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()
        val nextLessonBoundary = lessons
            .asSequence()
            .filter { !it.isCancelled }
            .flatMap { sequenceOf(it.startEpochMs, it.endEpochMs) }
            .filter { it > nowEpochMs }
            .minOrNull()
        val target = if (nextLessonBoundary != null) {
            minOf(nextLessonBoundary, nextMidnightMs)
        } else {
            nextMidnightMs
        }
        return ((target - nowEpochMs) + 50L).coerceIn(500L, 60L * 60_000L)
    }

    @JvmOverloads
    fun evaluateWithRollover(
        lessons: List<Lesson>,
        nowEpochMs: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): RolloverTimetableState {
        val todayDate = KretaDateParser.localDateFor(nowEpochMs, zoneId)
        val todayStatus = evaluate(lessons, nowEpochMs, zoneId)
        val todaysLessons = lessons
            .filter { KretaDateParser.isSameLocalDay(it.startEpochMs, todayDate, zoneId) }
            .sortedBy { it.startEpochMs }

        val todayEnded = todayStatus.phase == TimetablePhase.AFTER_SCHOOL ||
            todayStatus.phase == TimetablePhase.NO_CLASSES_TODAY

        if (todayEnded) {
            val futureByDate = lessons
                .mapNotNull { lesson ->
                    val lessonDate = KretaDateParser.localDateFor(lesson.startEpochMs, zoneId)
                    if (lessonDate.isAfter(todayDate)) lessonDate to lesson else null
                }
                .groupBy({ it.first }, { it.second })
                .toSortedMap()

            val nextSchoolEntry = futureByDate.entries.firstOrNull { (_, dayLessons) ->
                dayLessons.any { !it.isCancelled }
            } ?: futureByDate.entries.firstOrNull()

            if (nextSchoolEntry != null) {
                val nextDate = nextSchoolEntry.key
                val nextDayLessons = nextSchoolEntry.value.sortedBy { it.startEpochMs }
                val nonCancelled = nextDayLessons.filter { !it.isCancelled }
                val isTomorrow = nextDate == todayDate.plusDays(1)
                val weekday = KretaDateParser.weekdayNameHu(nextDate)
                return RolloverTimetableState(
                    todayStatus = todayStatus,
                    isRolledOverToNextDay = true,
                    displayDate = nextDate,
                    displayDayPillLabel = if (isTomorrow) {
                        "Holnap • $weekday"
                    } else {
                        "$weekday • ${KretaDateParser.formatMonthDay(nextDate)}"
                    },
                    page1DayBadgeLabel = if (isTomorrow) "Holnap" else weekday,
                    displayLessons = nextDayLessons,
                    previewFirstLesson = nonCancelled.firstOrNull(),
                    previewSecondLesson = nonCancelled.drop(1).firstOrNull(),
                )
            }
        }

        return RolloverTimetableState(
            todayStatus = todayStatus,
            isRolledOverToNextDay = false,
            displayDate = todayDate,
            displayDayPillLabel = "Ma • ${KretaDateParser.weekdayNameHu(todayDate)}",
            page1DayBadgeLabel = null,
            displayLessons = todaysLessons,
            previewFirstLesson = null,
            previewSecondLesson = null,
        )
    }

    fun formatTabularCountdown(remainingMs: Long): String {
        if (remainingMs <= 0L) return "00:00"
        val totalSec = ceil(remainingMs / 1000.0).toLong()
        val h = totalSec / 3600L
        val m = (totalSec % 3600L) / 60L
        val s = totalSec % 60L
        return if (h > 0L) {
            "%d:%02d:%02d".format(h, m, s)
        } else {
            "%02d:%02d".format(m, s)
        }
    }

    fun formatRemainingMinutesBadge(remainingMs: Long): String {
        if (remainingMs <= 0L) return "Most ér véget"
        val minutes = ceil(remainingMs / 60_000.0).toLong()
        return if (minutes <= 1L) "1 perc hátra" else "$minutes perc hátra"
    }
}

object KretaDateParser {
    private val hmFormatter = DateTimeFormatter.ofPattern("HH:mm")
    private val monthDayFormatter = DateTimeFormatter.ofPattern("MM. dd.")

    fun formatHm(epochMs: Long, zoneId: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochMilli(epochMs).atZone(zoneId).toLocalTime().format(hmFormatter)

    fun formatMonthDay(epochMs: Long, zoneId: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochMilli(epochMs).atZone(zoneId).toLocalDate().format(monthDayFormatter)

    fun formatMonthDay(date: LocalDate): String = date.format(monthDayFormatter)

    fun localDateFor(epochMs: Long, zoneId: ZoneId = ZoneId.systemDefault()): LocalDate =
        Instant.ofEpochMilli(epochMs).atZone(zoneId).toLocalDate()

    fun weekdayNameHu(date: LocalDate): String = when (date.dayOfWeek) {
        DayOfWeek.MONDAY -> "Hétfő"
        DayOfWeek.TUESDAY -> "Kedd"
        DayOfWeek.WEDNESDAY -> "Szerda"
        DayOfWeek.THURSDAY -> "Csütörtök"
        DayOfWeek.FRIDAY -> "Péntek"
        DayOfWeek.SATURDAY -> "Szombat"
        DayOfWeek.SUNDAY -> "Vasárnap"
    }

    fun dateKeyFor(epochMs: Long = System.currentTimeMillis(), zoneId: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochMilli(epochMs).atZone(zoneId).toLocalDate().toString()

    fun isSameLocalDay(epochMs: Long, targetDate: LocalDate, zoneId: ZoneId = ZoneId.systemDefault()): Boolean =
        Instant.ofEpochMilli(epochMs).atZone(zoneId).toLocalDate() == targetDate

    fun parseEpochMillis(raw: String, zoneId: ZoneId = ZoneId.systemDefault()): Long? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return runCatching { Instant.parse(trimmed).toEpochMilli() }.getOrElse {
            runCatching {
                LocalDateTime.parse(trimmed, DateTimeFormatter.ISO_DATE_TIME)
                    .atZone(zoneId)
                    .toInstant()
                    .toEpochMilli()
            }.getOrElse {
                runCatching {
                    LocalDate.parse(trimmed, DateTimeFormatter.ISO_LOCAL_DATE)
                        .atStartOfDay(zoneId)
                        .toInstant()
                        .toEpochMilli()
                }.getOrNull()
            }
        }
    }
}

private fun JSONObject.optNullableString(key: String): String? {
    if (!has(key) || isNull(key)) return null
    return optString(key, "").trim().ifEmpty { null }
}

fun JSONArray.toJsonObjectList(): List<JSONObject> = buildList {
    for (i in 0 until length()) {
        optJSONObject(i)?.let { add(it) }
    }
}
