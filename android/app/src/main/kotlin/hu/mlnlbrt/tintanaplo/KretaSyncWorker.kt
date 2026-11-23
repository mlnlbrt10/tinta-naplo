package hu.mlnlbrt.tintanaplo

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class KretaSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    companion object {
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_NOTIFICATION_CONFIG = "flutter.kreta_notification_config_v1"
        private const val KEY_NOTIFICATION_SNAPSHOT = "flutter.kreta_notification_snapshot_v1"
        private const val KEY_SESSION_BACKUP = "flutter.kreta_session_backup_v2"
        private const val KEY_DEMO_ENABLED = "flutter.profile_prefs_v1"
    }

    private data class SessionData(
        val accessToken: String,
        val refreshToken: String,
        val idToken: String,
        val instituteCode: String,
        val userName: String,
        val expiresAtMs: Long,
    )

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val configRaw = prefs.getString(KEY_NOTIFICATION_CONFIG, null)
        val configJson = configRaw?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()

        val masterEnabled = configJson.optBoolean("masterEnabled", true)
        if (!masterEnabled) return Result.success()

        val catsJson = configJson.optJSONObject("categories") ?: JSONObject()
        fun isCatEnabled(key: String): Boolean =
            catsJson.optJSONObject(key)?.optBoolean("enabled", true) ?: true

        val gradeEnabled = isCatEnabled("newGrade")
        val examEnabled = isCatEnabled("newExam")
        val cancelEnabled = isCatEnabled("cancelledLesson")
        val subEnabled = isCatEnabled("substitution")
        val lateEnabled = isCatEnabled("lateArrival")
        val absenceEnabled = isCatEnabled("absence")
        val msgEnabled = isCatEnabled("newMessage")
        if (!gradeEnabled &&
            !examEnabled &&
            !cancelEnabled &&
            !subEnabled &&
            !lateEnabled &&
            !absenceEnabled &&
            !msgEnabled
        ) {
            return Result.success()
        }

        // Skip background sync while showcase demo mode is active.
        val profilePrefsRaw = prefs.getString(KEY_DEMO_ENABLED, null)
        if (!profilePrefsRaw.isNullOrBlank()) {
            val demoOn = runCatching {
                JSONObject(profilePrefsRaw).optJSONObject("extras")?.optBoolean("demoModeEnabled", false) == true
            }.getOrDefault(false)
            if (demoOn) return Result.success()
        }

        var session = loadSession(prefs) ?: return Result.success()
        if (session.instituteCode.isBlank() || session.refreshToken.isBlank()) {
            return Result.success()
        }

        if (session.accessToken.isBlank() || System.currentTimeMillis() + 60_000L >= session.expiresAtMs) {
            val refreshed = refreshSession(prefs, session)
            if (refreshed != null) {
                session = refreshed
            } else if (System.currentTimeMillis() >= session.expiresAtMs) {
                return Result.retry()
            }
        }

        val acctKey = "${session.instituteCode.trim()}|${session.userName.trim().ifEmpty { "default" }}"
        val snapshotsRoot = prefs.getString(KEY_NOTIFICATION_SNAPSHOT, null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: JSONObject()
        val prevSnapshot = snapshotsRoot.optJSONObject(acctKey) ?: JSONObject()
        val initialized = prevSnapshot.optBoolean("initialized", false)
        val omissionsInitialized =
            prevSnapshot.optBoolean("omissionsInitialized", false) || prevSnapshot.has("lateArrivalIds")
        val messagesInitialized =
            prevSnapshot.optBoolean("messagesInitialized", false) || prevSnapshot.has("messageIds")

        val prevGrades = jsonArrayToSet(prevSnapshot.optJSONArray("gradeIds"))
        val prevTests = jsonArrayToSet(prevSnapshot.optJSONArray("testIds"))
        val prevCancelled = jsonArrayToSet(prevSnapshot.optJSONArray("cancelledLessonIds"))
        val prevSubstituted = jsonArrayToSet(prevSnapshot.optJSONArray("substitutedLessonIds"))
        val prevLate = jsonArrayToSet(prevSnapshot.optJSONArray("lateArrivalIds"))
        val prevAbsence = jsonArrayToSet(prevSnapshot.optJSONArray("absenceIds"))
        val prevMessages = jsonArrayToSet(prevSnapshot.optJSONArray("messageIds"))

        val baseApi = "https://${session.instituteCode}.${KretaSharedConfig.KRETA_BASE_DOMAIN}"
        val gradesArr = fetchJsonArray("$baseApi${KretaSharedConfig.ENDPOINT_GRADES}", session.accessToken)
        val testsArr = fetchJsonArray("$baseApi${KretaSharedConfig.ENDPOINT_TESTS}", session.accessToken)

        val dateQueryFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cal = Calendar.getInstance()
        val fromStr = dateQueryFmt.format(cal.time)
        cal.add(Calendar.DAY_OF_YEAR, 7)
        val toStr = dateQueryFmt.format(cal.time)
        val lessonsArr = fetchJsonArray(
            "$baseApi${KretaSharedConfig.ENDPOINT_TIMETABLE}?datumTol=$fromStr&datumIg=$toStr",
            session.accessToken,
        )
        val omissionsArr = fetchJsonArray(
            "$baseApi/ellenorzo/v3/sajat/Mulasztasok",
            session.accessToken,
        )
        val messagesArr = fetchEugyintezesJsonArray(
            "https://eugyintezes.e-kreta.hu/integration-kretamobile-api/v1/kommunikacio/postaladaelemek/sajat",
            session.accessToken,
        ) ?: fetchEugyintezesJsonArray(
            "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/beerkezett",
            session.accessToken,
        )

        if (gradesArr == null && testsArr == null && lessonsArr == null && omissionsArr == null && messagesArr == null) {
            return Result.retry()
        }

        val currentGrades = mutableSetOf<String>()
        val currentTests = mutableSetOf<String>()
        val currentCancelled = mutableSetOf<String>()
        val currentSubstituted = mutableSetOf<String>()
        val currentLate = mutableSetOf<String>()
        val currentAbsence = mutableSetOf<String>()
        val currentMessages = mutableSetOf<String>()

        var nextNotifyId = 8500
        val shortDateFmt = SimpleDateFormat("MM. dd.", Locale.getDefault())

        // 1. Diff grades
        if (gradesArr != null) {
            val gradeCatObj = catsJson.optJSONObject("newGrade")
            val defaultGradeTitleTpl = gradeCatObj?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Új jegy: {grade} ({subject})"
            val defaultGradeBodyTpl = gradeCatObj?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{topic} • Súly: {weight} • {teacher}"
            val gradeOverrides = gradeCatObj?.optJSONObject("gradeTemplates")

            for (i in 0 until gradesArr.length()) {
                val g = gradesArr.optJSONObject(i) ?: continue
                val subjObj = g.optJSONObject("Tantargy")
                val subjectName = subjObj?.optString("Nev")?.trim().orEmpty().ifEmpty { "Tantárgy" }
                val recordedRaw = g.optString("KeszitesDatuma").ifBlank { g.optString("RogzitesDatuma") }
                val numericNum = if (!g.isNull("SzamErtek")) g.optInt("SzamErtek", 0) else 0
                val numericVal = if (!g.isNull("SzamErtek")) g.optInt("SzamErtek").toString() else ""
                val shortStr = g.optString("SzovegesErtekelesRovidNev").trim()
                val strVal = g.optString("SzovegesErtek").trim()
                val gradeText = numericVal.ifEmpty { shortStr.ifEmpty { strVal } }

                val uid = g.optString("Uid").trim().ifEmpty {
                    "${subjectName}_${recordedRaw}_$gradeText"
                }
                currentGrades.add(uid)

                if (initialized && gradeEnabled && !prevGrades.contains(uid)) {
                    val weight = g.optInt("SulySzazalekErteke", 100).let { if (it > 0) "$it%" else "100%" }
                    val teacher = g.optString("ErtekeloTanarNeve").trim()
                    val topic = g.optString("Tema").trim().ifEmpty {
                        g.optJSONObject("Mod")?.optString("Leiras")?.trim().orEmpty()
                            .ifEmpty { g.optJSONObject("Tipus")?.optString("Leiras")?.trim().orEmpty() }
                    }
                    val dateLabel = parseAndFormatDate(recordedRaw, shortDateFmt)
                    val values = mapOf(
                        "{subject}" to subjectName,
                        "{grade}" to gradeText,
                        "{weight}" to weight,
                        "{teacher}" to teacher,
                        "{room}" to "",
                        "{date}" to dateLabel,
                        "{topic}" to topic,
                        "{substitute_teacher}" to "",
                        "{lesson_number}" to "",
                    )
                    val overrideObj = if (numericNum in 1..5) gradeOverrides?.optJSONObject(numericNum.toString()) else null
                    val titleTpl = overrideObj?.optString("titleTemplate")?.takeIf { it.isNotBlank() }
                        ?: defaultGradeTitleTpl
                    val bodyTpl = overrideObj?.optString("bodyTemplate")?.takeIf { it.isNotBlank() }
                        ?: defaultGradeBodyTpl
                    val title = KretaNotificationDispatcher.renderTemplate(titleTpl, values)
                        .ifEmpty { "Új jegy: $subjectName" }
                    val body = KretaNotificationDispatcher.buildGradeNotificationBody(
                        bodyTpl,
                        subjectName,
                        if (numericNum in 1..5) numericNum else null,
                        values,
                    )
                    KretaNotificationDispatcher.showNotification(
                        applicationContext,
                        nextNotifyId++,
                        "newGrade",
                        title,
                        body,
                    )
                }
            }
        } else {
            currentGrades.addAll(prevGrades)
        }

        // 2. Diff announced tests/exams
        if (testsArr != null) {
            val titleTpl = catsJson.optJSONObject("newExam")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Új számonkérés: {subject}"
            val bodyTpl = catsJson.optJSONObject("newExam")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{topic} • {date} ({lesson_number}. óra) • {teacher}"

            for (i in 0 until testsArr.length()) {
                val t = testsArr.optJSONObject(i) ?: continue
                val subjObj = t.optJSONObject("Tantargy")
                val subjectName = t.optString("TantargyNeve").trim()
                    .ifEmpty { subjObj?.optString("Nev")?.trim().orEmpty() }
                    .ifEmpty { "Tantárgy" }
                val dateRaw = t.optString("Datum").ifBlank { t.optString("BejelentesDatuma") }
                val lessonNum = t.optInt("OrarendiOraOraszama", 0)
                val uid = t.optString("Uid").trim().ifEmpty {
                    "${subjectName}_${dateRaw}_$lessonNum"
                }
                currentTests.add(uid)

                if (initialized && examEnabled && !prevTests.contains(uid)) {
                    val teacher = t.optString("RogzitoTanarNeve").trim()
                    val topic = t.optString("Temaja").trim()
                        .ifEmpty { t.optJSONObject("Modja")?.optString("Leiras")?.trim().orEmpty() }
                    val dateLabel = parseAndFormatDate(dateRaw, shortDateFmt)
                    val values = mapOf(
                        "{subject}" to subjectName,
                        "{grade}" to "",
                        "{weight}" to "",
                        "{teacher}" to teacher,
                        "{room}" to "",
                        "{date}" to dateLabel,
                        "{topic}" to topic,
                        "{substitute_teacher}" to "",
                        "{lesson_number}" to if (lessonNum > 0) lessonNum.toString() else "",
                    )
                    val title = KretaNotificationDispatcher.renderTemplate(titleTpl, values)
                        .ifEmpty { "Új számonkérés: $subjectName" }
                    val body = KretaNotificationDispatcher.renderTemplate(bodyTpl, values)
                    KretaNotificationDispatcher.showNotification(
                        applicationContext,
                        nextNotifyId++,
                        "newExam",
                        title,
                        body,
                    )
                }
            }
        } else {
            currentTests.addAll(prevTests)
        }

        // 3. Diff cancelled & substituted lessons
        if (lessonsArr != null) {
            val cancelTitleTpl = catsJson.optJSONObject("cancelledLesson")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Elmaradt óra: {subject}"
            val cancelBodyTpl = catsJson.optJSONObject("cancelledLesson")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{date} • {lesson_number}. óra • Terem: {room}"
            val subTitleTpl = catsJson.optJSONObject("substitution")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Helyettesítés: {subject}"
            val subBodyTpl = catsJson.optJSONObject("substitution")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{lesson_number}. óra • Helyettesítő: {substitute_teacher} • Terem: {room}"

            for (i in 0 until lessonsArr.length()) {
                val l = lessonsArr.optJSONObject(i) ?: continue
                val rawUid = l.optString("Uid").trim()
                if (rawUid.startsWith("inactive_period_")) continue

                val subjObj = l.optJSONObject("Tantargy")
                val subjectName = subjObj?.optString("Nev")?.trim().orEmpty()
                    .ifEmpty { l.optString("Nev").trim() }
                    .ifEmpty { "Tanóra" }
                val startRaw = l.optString("KezdetIdopont")
                val lessonNum = if (!l.isNull("Oraszam")) l.optInt("Oraszam", 0) else 0
                val keyBase = rawUid.ifEmpty {
                    "${startRaw}_${if (lessonNum > 0) lessonNum else ""}_$subjectName"
                }

                val stateObj = l.optJSONObject("Allapot")
                val stateName = stateObj?.optString("Nev")?.lowercase()?.trim().orEmpty()
                val stateDesc = stateObj?.optString("Leiras")?.lowercase()?.trim().orEmpty()
                val isCancelled = stateName == "elmaradt" ||
                    stateName.contains("elmarad") ||
                    stateDesc.contains("elmarad")

                val subTeacher = l.optString("HelyettesTanarNeve").trim()
                val room = l.optString("TeremNeve").trim()
                val teacher = l.optString("TanarNeve").trim()
                val topic = l.optString("Tema").trim()
                val dateLabel = parseAndFormatDate(startRaw, shortDateFmt)
                val lessonNumStr = if (lessonNum > 0) lessonNum.toString() else ""

                if (isCancelled) {
                    currentCancelled.add(keyBase)
                    if (initialized && cancelEnabled && !prevCancelled.contains(keyBase)) {
                        val values = mapOf(
                            "{subject}" to subjectName,
                            "{grade}" to "",
                            "{weight}" to "",
                            "{teacher}" to teacher,
                            "{room}" to room,
                            "{date}" to dateLabel,
                            "{topic}" to topic,
                            "{substitute_teacher}" to "",
                            "{lesson_number}" to lessonNumStr,
                        )
                        val title = KretaNotificationDispatcher.renderTemplate(cancelTitleTpl, values)
                            .ifEmpty { "Elmaradt óra: $subjectName" }
                        val body = KretaNotificationDispatcher.renderTemplate(cancelBodyTpl, values)
                        KretaNotificationDispatcher.showNotification(
                            applicationContext,
                            nextNotifyId++,
                            "cancelledLesson",
                            title,
                            body,
                        )
                    }
                } else if (subTeacher.isNotEmpty()) {
                    val subKey = "$keyBase::$subTeacher"
                    currentSubstituted.add(subKey)
                    if (initialized && subEnabled && !prevSubstituted.contains(subKey)) {
                        val values = mapOf(
                            "{subject}" to subjectName,
                            "{grade}" to "",
                            "{weight}" to "",
                            "{teacher}" to teacher,
                            "{room}" to room,
                            "{date}" to dateLabel,
                            "{topic}" to topic,
                            "{substitute_teacher}" to subTeacher,
                            "{lesson_number}" to lessonNumStr,
                        )
                        val title = KretaNotificationDispatcher.renderTemplate(subTitleTpl, values)
                            .ifEmpty { "Helyettesítés: $subjectName" }
                        val body = KretaNotificationDispatcher.renderTemplate(subBodyTpl, values)
                        KretaNotificationDispatcher.showNotification(
                            applicationContext,
                            nextNotifyId++,
                            "substitution",
                            title,
                            body,
                        )
                    }
                }
            }
        } else {
            currentCancelled.addAll(prevCancelled)
            currentSubstituted.addAll(prevSubstituted)
        }

        // 4. Diff omissions (late arrivals & absences)
        if (omissionsArr != null) {
            val lateTitleTpl = catsJson.optJSONObject("lateArrival")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Késés: {subject} ({minutes} perc)"
            val lateBodyTpl = catsJson.optJSONObject("lateArrival")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{date} • {lesson_number}. óra • {teacher}"
            val absTitleTpl = catsJson.optJSONObject("absence")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Hiányzás: {subject}"
            val absBodyTpl = catsJson.optJSONObject("absence")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{date} • {lesson_number}. óra • {excused_status} ({type})"

            for (i in 0 until omissionsArr.length()) {
                val o = omissionsArr.optJSONObject(i) ?: continue
                val subjObj = o.optJSONObject("Tantargy")
                val subjectName = subjObj?.optString("Nev")?.trim().orEmpty()
                    .ifEmpty { o.optString("TantargyNev").trim() }
                    .ifEmpty { "Tanóra" }
                val dateRaw = o.optString("Datum").ifBlank { o.optString("KeszitesDatuma") }
                val oraObj = o.optJSONObject("Ora")
                val lessonNum = if (oraObj != null && !oraObj.isNull("Oraszam")) {
                    oraObj.optInt("Oraszam", 0)
                } else {
                    0
                }
                val lateMin = if (!o.isNull("KesesPercben")) o.optInt("KesesPercben", 0) else 0
                val typeObj = o.optJSONObject("Tipus")
                val typeName = typeObj?.optString("Nev")?.lowercase()?.trim().orEmpty()
                val typeDesc = typeObj?.optString("Leiras")?.trim().orEmpty()
                val isLate = lateMin > 0 ||
                    typeName.contains("keses") ||
                    typeDesc.lowercase().contains("késés")

                val uid = o.optString("Uid").trim().ifEmpty {
                    "${subjectName}_${dateRaw}_${lessonNum}_$lateMin"
                }
                val dateLabel = parseAndFormatDate(dateRaw, shortDateFmt)
                val teacher = o.optString("RogzitoTanarNeve").trim()
                val stateHu = when (o.optString("IgazolasAllapota").trim()) {
                    "Igazolt" -> "Igazolt"
                    "Igazolatlan" -> "Igazolatlan"
                    "Igazolando" -> "Igazolandó"
                    else -> "Ismeretlen"
                }
                val modeDesc = o.optJSONObject("Mod")?.optString("Leiras")?.trim().orEmpty()
                val resolvedType = typeDesc.ifEmpty { modeDesc }.ifEmpty {
                    if (isLate) "Késés" else "Hiányzás"
                }

                if (isLate) {
                    currentLate.add(uid)
                    if (initialized && omissionsInitialized && lateEnabled && !prevLate.contains(uid)) {
                        val values = mapOf(
                            "{subject}" to subjectName,
                            "{grade}" to "",
                            "{weight}" to "",
                            "{teacher}" to teacher,
                            "{room}" to "",
                            "{date}" to dateLabel,
                            "{topic}" to resolvedType,
                            "{substitute_teacher}" to "",
                            "{lesson_number}" to if (lessonNum > 0) lessonNum.toString() else "",
                            "{minutes}" to lateMin.toString(),
                            "{excused_status}" to stateHu,
                            "{type}" to resolvedType,
                            "{sender}" to "",
                            "{title}" to "",
                            "{preview}" to "",
                        )
                        val title = KretaNotificationDispatcher.renderTemplate(lateTitleTpl, values)
                            .ifEmpty { "Késés: $subjectName" }
                        val body = KretaNotificationDispatcher.renderTemplate(lateBodyTpl, values)
                        KretaNotificationDispatcher.showNotification(
                            applicationContext,
                            nextNotifyId++,
                            "lateArrival",
                            title,
                            body,
                        )
                    }
                } else {
                    currentAbsence.add(uid)
                    if (initialized && omissionsInitialized && absenceEnabled && !prevAbsence.contains(uid)) {
                        val values = mapOf(
                            "{subject}" to subjectName,
                            "{grade}" to "",
                            "{weight}" to "",
                            "{teacher}" to teacher,
                            "{room}" to "",
                            "{date}" to dateLabel,
                            "{topic}" to resolvedType,
                            "{substitute_teacher}" to "",
                            "{lesson_number}" to if (lessonNum > 0) lessonNum.toString() else "",
                            "{minutes}" to "",
                            "{excused_status}" to stateHu,
                            "{type}" to resolvedType,
                            "{sender}" to "",
                            "{title}" to "",
                            "{preview}" to "",
                        )
                        val title = KretaNotificationDispatcher.renderTemplate(absTitleTpl, values)
                            .ifEmpty { "Hiányzás: $subjectName" }
                        val body = KretaNotificationDispatcher.renderTemplate(absBodyTpl, values)
                        KretaNotificationDispatcher.showNotification(
                            applicationContext,
                            nextNotifyId++,
                            "absence",
                            title,
                            body,
                        )
                    }
                }
            }
        } else {
            currentLate.addAll(prevLate)
            currentAbsence.addAll(prevAbsence)
        }

        // 5. Diff unread incoming messages
        if (messagesArr != null) {
            val msgTitleTpl = catsJson.optJSONObject("newMessage")?.optString("titleTemplate")
                ?.takeIf { it.isNotBlank() } ?: "Új üzenet: {sender}"
            val msgBodyTpl = catsJson.optJSONObject("newMessage")?.optString("bodyTemplate")
                ?.takeIf { it.isNotBlank() } ?: "{title} • {preview}"

            for (i in 0 until messagesArr.length()) {
                val item = messagesArr.optJSONObject(i) ?: continue
                if (item.optBoolean("isToroltElem", false)) continue
                val tipusKod = item.optJSONObject("tipus")?.optString("kod")?.uppercase()?.trim().orEmpty()
                if (tipusKod.contains("ELKULD")) continue
                if (item.optBoolean("isElolvasva", false)) continue

                val nested = item.optJSONObject("uzenet")
                val rawUid = item.opt("azonosito")?.toString()?.trim().orEmpty()
                if (rawUid.isEmpty()) continue
                val msgKey = "msg:$rawUid"
                currentMessages.add(msgKey)

                if (initialized && messagesInitialized && msgEnabled && !prevMessages.contains(msgKey)) {
                    val sender = (nested?.optString("feladoNev") ?: "").ifBlank {
                        item.optString("uzenetFeladoNev")
                    }.trim().ifEmpty { "KRÉTA Üzenet" }
                    val msgSubject = (nested?.optString("targy") ?: "").ifBlank {
                        item.optString("uzenetTargy")
                    }.trim()
                    val rawBody = (nested?.optString("szoveg") ?: "").ifBlank {
                        item.optString("uzenetSzoveg")
                    }
                    val cleanPreview = stripHtmlAndTruncate(rawBody)
                    val sentRaw = (nested?.optString("kuldesDatum") ?: "").ifBlank {
                        item.optString("uzenetKuldesDatum")
                    }
                    val dateLabel = parseAndFormatDate(sentRaw, shortDateFmt)
                    val values = mapOf(
                        "{subject}" to msgSubject,
                        "{grade}" to "",
                        "{weight}" to "",
                        "{teacher}" to sender,
                        "{room}" to "",
                        "{date}" to dateLabel,
                        "{topic}" to msgSubject,
                        "{substitute_teacher}" to "",
                        "{lesson_number}" to "",
                        "{minutes}" to "",
                        "{excused_status}" to "",
                        "{type}" to "Üzenet",
                        "{sender}" to sender,
                        "{title}" to msgSubject,
                        "{preview}" to cleanPreview,
                    )
                    val title = KretaNotificationDispatcher.renderTemplate(msgTitleTpl, values)
                        .ifEmpty { "Új üzenet: $sender" }
                    val body = KretaNotificationDispatcher.renderTemplate(msgBodyTpl, values)
                    KretaNotificationDispatcher.showNotification(
                        applicationContext,
                        nextNotifyId++,
                        "newMessage",
                        title,
                        body,
                    )
                }
            }
        } else {
            currentMessages.addAll(prevMessages)
        }

        val mergedSnapshot = JSONObject().apply {
            put("initialized", true)
            put("omissionsInitialized", omissionsInitialized || omissionsArr != null)
            put("messagesInitialized", messagesInitialized || messagesArr != null)
            put("gradeIds", setToJsonArray(prevGrades + currentGrades))
            put("testIds", setToJsonArray(prevTests + currentTests))
            put("cancelledLessonIds", setToJsonArray(prevCancelled + currentCancelled))
            put("substitutedLessonIds", setToJsonArray(prevSubstituted + currentSubstituted))
            put("lateArrivalIds", setToJsonArray(prevLate + currentLate))
            put("absenceIds", setToJsonArray(prevAbsence + currentAbsence))
            put("messageIds", setToJsonArray(prevMessages + currentMessages))
        }
        snapshotsRoot.put(acctKey, mergedSnapshot)
        prefs.edit().putString(KEY_NOTIFICATION_SNAPSHOT, snapshotsRoot.toString()).apply()

        return Result.success()
    }

    private fun loadSession(prefs: android.content.SharedPreferences): SessionData? {
        val rawBackup = prefs.getString(KEY_SESSION_BACKUP, null)
        if (!rawBackup.isNullOrBlank()) {
            val parsed = runCatching {
                val obj = JSONObject(rawBackup)
                SessionData(
                    accessToken = obj.optString("accessToken", "").trim(),
                    refreshToken = obj.optString("refreshToken", "").trim(),
                    idToken = obj.optString("idToken", ""),
                    instituteCode = obj.optString("instituteCode", "").trim(),
                    userName = obj.optString("userName", "").trim(),
                    expiresAtMs = parseIsoDate(obj.optString("expiresAt", "")) ?: 0L,
                )
            }.getOrNull()
            if (parsed != null && parsed.refreshToken.isNotEmpty() && parsed.instituteCode.isNotEmpty()) {
                return parsed
            }
        }

        val wearCached = WearSessionBridge.loadCachedSession(applicationContext) ?: return null
        return SessionData(
            accessToken = wearCached.accessToken,
            refreshToken = wearCached.refreshToken,
            idToken = wearCached.idToken,
            instituteCode = wearCached.instituteCode,
            userName = wearCached.userName,
            expiresAtMs = wearCached.expiresAtMs,
        )
    }

    private fun refreshSession(
        prefs: android.content.SharedPreferences,
        current: SessionData,
    ): SessionData? {
        return runCatching {
            val conn = (URL(KretaSharedConfig.TOKEN_ENDPOINT).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 10_000
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                setRequestProperty("User-Agent", KretaSharedConfig.USER_AGENT)
            }
            val body = "grant_type=refresh_token" +
                "&refresh_token=${URLEncoder.encode(current.refreshToken, "UTF-8")}" +
                "&client_id=${URLEncoder.encode(KretaSharedConfig.CLIENT_ID_IOS, "UTF-8")}"
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            if (conn.responseCode != 200) return null
            val respText = conn.inputStream.bufferedReader().use(BufferedReader::readText)
            val json = JSONObject(respText)
            val newAccess = json.optString("access_token", "").trim()
            val newRefresh = json.optString("refresh_token", "").trim().ifEmpty { current.refreshToken }
            val newId = json.optString("id_token", "").ifEmpty { current.idToken }
            val expiresIn = json.optLong("expires_in", 1800L)
            if (newAccess.isEmpty()) return null

            val newExpiresMs = System.currentTimeMillis() + expiresIn * 1000L
            val updated = current.copy(
                accessToken = newAccess,
                refreshToken = newRefresh,
                idToken = newId,
                expiresAtMs = newExpiresMs,
            )
            val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val backupJson = JSONObject().apply {
                put("accessToken", updated.accessToken)
                put("refreshToken", updated.refreshToken)
                put("idToken", updated.idToken)
                put("instituteCode", updated.instituteCode)
                put("userName", updated.userName)
                put("expiresAt", isoFmt.format(Date(updated.expiresAtMs)))
            }.toString()
            prefs.edit().putString(KEY_SESSION_BACKUP, backupJson).apply()
            WearSessionBridge.loadCachedSession(applicationContext)?.let { cachedWear ->
                WearSessionBridge.cacheSession(
                    applicationContext,
                    cachedWear.copy(
                        accessToken = updated.accessToken,
                        refreshToken = updated.refreshToken,
                        idToken = updated.idToken,
                        expiresAtMs = updated.expiresAtMs,
                    ),
                )
            }
            updated
        }.getOrNull()
    }

    private fun fetchJsonArray(urlStr: String, accessToken: String): JSONArray? {
        return runCatching {
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("Accept", "application/json, */*")
                setRequestProperty("User-Agent", KretaSharedConfig.USER_AGENT)
                setRequestProperty("Authorization", "Bearer $accessToken")
                setRequestProperty("apiKey", KretaSharedConfig.API_KEY)
            }
            if (conn.responseCode != 200) return null
            val text = conn.inputStream.bufferedReader().use(BufferedReader::readText).trim()
            if (text.isEmpty()) return JSONArray()
            JSONArray(text)
        }.getOrNull()
    }

    private fun fetchEugyintezesJsonArray(urlStr: String, accessToken: String): JSONArray? {
        return runCatching {
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("Accept", "application/json, text/plain, */*")
                setRequestProperty("User-Agent", KretaSharedConfig.USER_AGENT)
                setRequestProperty("Authorization", "Bearer $accessToken")
            }
            if (conn.responseCode != 200) return null
            val text = conn.inputStream.bufferedReader().use(BufferedReader::readText).trim()
            if (text.isEmpty()) return JSONArray()
            if (text.startsWith("[")) {
                JSONArray(text)
            } else {
                val obj = JSONObject(text)
                obj.optJSONArray("data") ?: obj.optJSONArray("items")
            }
        }.getOrNull()
    }

    private fun stripHtmlAndTruncate(raw: String, maxLen: Int = 110): String {
        val cleaned = raw
            .replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("</p>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<[^>]*>"), " ")
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace(Regex("\\s+"), " ")
            .trim()
        return if (cleaned.length <= maxLen) cleaned else cleaned.take(maxLen - 3).trim() + "..."
    }

    private fun parseIsoDate(raw: String): Long? {
        if (raw.isBlank()) return null
        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        )
        for (p in patterns) {
            val fmt = SimpleDateFormat(p, Locale.US)
            if (p.endsWith("'Z'")) {
                fmt.timeZone = TimeZone.getTimeZone("UTC")
            }
            val parsed = runCatching { fmt.parse(raw)?.time }.getOrNull()
            if (parsed != null) return parsed
        }
        return null
    }

    private fun parseAndFormatDate(raw: String, outFmt: SimpleDateFormat): String {
        val ms = parseIsoDate(raw) ?: return ""
        return outFmt.format(Date(ms))
    }

    private fun jsonArrayToSet(arr: JSONArray?): Set<String> {
        if (arr == null) return emptySet()
        val set = mutableSetOf<String>()
        for (i in 0 until arr.length()) {
            val s = arr.optString(i).trim()
            if (s.isNotEmpty()) set.add(s)
        }
        return set
    }

    private fun setToJsonArray(set: Set<String>): JSONArray {
        val arr = JSONArray()
        set.sorted().forEach { arr.put(it) }
        return arr
    }
}
