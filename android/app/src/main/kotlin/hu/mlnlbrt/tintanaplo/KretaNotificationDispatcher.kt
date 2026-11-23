package hu.mlnlbrt.tintanaplo

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object KretaNotificationDispatcher {
    const val CHANNEL_ID = "tinta_kreta_alerts"
    const val CHANNEL_NAME = "KRÉTA Értesítések"
    const val WORK_NAME = "tinta_kreta_bg_sync"
    const val IMMEDIATE_WORK_NAME = "tinta_kreta_immediate_sync"
    const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    const val KEY_NOTIFICATION_CONFIG = "flutter.kreta_notification_config_v1"

    private val PLACEHOLDER_KEYS = listOf(
        "{subject}",
        "{grade}",
        "{weight}",
        "{teacher}",
        "{room}",
        "{date}",
        "{topic}",
        "{substitute_teacher}",
        "{lesson_number}",
        "{minutes}",
        "{excused_status}",
        "{type}",
        "{sender}",
        "{title}",
        "{preview}",
    )

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Azonnali értesítések új jegyekről, számonkérésekről, óraváltozásokról, késésekről, hiányzásokról és üzenetekről"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun showNotification(
        context: Context,
        notificationId: Int,
        category: String,
        title: String,
        body: String,
    ) {
        ensureChannel(context)
        if (!hasNotificationPermission(context)) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_kreta_notification", true)
            putExtra("kreta_notification_category", category)
        }
        val pending = PendingIntent.getActivity(
            context,
            notificationId,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tinta)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setContentIntent(pending)

        runCatching {
            manager.notify(notificationId, builder.build())
        }
    }

    fun schedulePeriodicSync(
        context: Context,
        enabled: Boolean,
        intervalMinutes: Int = 15,
    ) {
        val wm = WorkManager.getInstance(context.applicationContext)
        if (!enabled) {
            wm.cancelUniqueWork(WORK_NAME)
            return
        }
        val safeMinutes = intervalMinutes.coerceAtLeast(15).toLong()
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = PeriodicWorkRequestBuilder<KretaSyncWorker>(
            safeMinutes,
            TimeUnit.MINUTES,
        )
            .setConstraints(constraints)
            .build()
        wm.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun enqueueImmediateSync(context: Context) {
        val wm = WorkManager.getInstance(context.applicationContext)
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = OneTimeWorkRequestBuilder<KretaSyncWorker>()
            .setConstraints(constraints)
            .build()
        wm.enqueueUniqueWork(
            IMMEDIATE_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun rescheduleFromSavedPrefs(context: Context) {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_NOTIFICATION_CONFIG, null)
        if (raw.isNullOrBlank()) {
            schedulePeriodicSync(context, enabled = true, intervalMinutes = 15)
            return
        }
        val parsed = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val master = parsed.optBoolean("masterEnabled", true)
        val interval = parsed.optInt("backgroundIntervalMinutes", 15)
        val cats = parsed.optJSONObject("categories")
        val anyEnabled = master && (cats == null || listOf(
            "newGrade",
            "newExam",
            "cancelledLesson",
            "substitution",
            "lateArrival",
            "absence",
            "newMessage",
        ).any { key ->
            val obj = cats.optJSONObject(key)
            obj?.optBoolean("enabled", true) ?: true
        })
        schedulePeriodicSync(context, enabled = anyEnabled, intervalMinutes = interval)
    }

    fun renderTemplate(template: String, values: Map<String, String>): String {
        var result = template
        for (token in PLACEHOLDER_KEYS) {
            val replacement = values[token]?.trim().orEmpty()
            result = result.replace(token, replacement)
        }
        result = result.replace(Regex("\\s*•\\s*(?:•\\s*)+"), " • ")
        result = result.replace(Regex("^\\s*•\\s*|\\s*•\\s*$"), "")
        result = result.replace(Regex("\\(\\s*\\)"), "")
        result = result.replace(Regex("\\(\\s*perc\\s*\\)"), "")
        result = result.replace(Regex("\\(\\s*\\.\\s*óra\\s*\\)"), "")
        result = result.replace(Regex(" {2,}"), " ").trim()
        return result
    }

    private val FRONT_VOWELS = setOf('e', 'é', 'i', 'í', 'ö', 'ő', 'ü', 'ű')
    private val FRONT_ROUNDED_VOWELS = setOf('ö', 'ő', 'ü', 'ű')
    private val BACK_VOWELS = setOf('a', 'á', 'o', 'ó', 'u', 'ú')

    private val FRONT_COMPOUND_TAILS = listOf(
        "nevelés", "kezelés", "fejlesztés", "tesztelés", "tervezés",
        "szerkesztés", "elemzés", "mérés", "képzés", "védelem", "elmélet",
        "történet", "történelem", "ismeret", "ismeretek", "rendszer",
        "rendszerek", "főnöki", "főnökök", "főnök", "nyelvek", "nyelvi",
        "nyelv", "kör", "ügy", "zene",
    )

    private val BACK_COMPOUND_TAILS = listOf(
        "rajz", "tan", "tudomány", "gyakorlat", "munka", "irodalom",
        "programozás", "adatbázis", "alkalmazás", "technika", "elektronika",
        "informatika", "matematika", "fizika", "kémia", "biológia", "grafika",
        "statisztika", "etika", "dráma", "média", "kultúra", "hálózatok",
        "hálózat", "szolgálat", "számtan", "mértan",
    )

    private val PERSONA_KEYWORDS = setOf(
        "bad boy", "király", "zseni", "profi", "legenda", "clutch", "béna",
        "gyenge", "bot", "npc", "goat", "császár", "mágus", "ász", "bajnok",
        "hős", "szuperhős", "főnök", "boss", "king", "queen", "god", "sigma",
        "alpha", "gigachad", "chad", "lúzer", "kuka", "amatőr", "kezdő", "menő",
        "brutál", "kemény", "erős", "top", "elit", "elite", "sztár", "star",
        "zseniális", "szuper", "tökéletes", "mester", "isten", "best", "mvp",
        "carry", "okos", "ügyes", "bátor", "lusta", "rosszfiú", "gengszter",
        "noob", "pro", "gyilkos", "terminátor", "nagyon jó", "szép", "csúnya",
    )

    private val POSITIVE_PERSONAS = setOf(
        "király", "zseni", "profi", "legenda", "clutch", "goat", "császár",
        "mágus", "ász", "bajnok", "hős", "szuperhős", "boss", "king", "queen",
        "god", "sigma", "alpha", "gigachad", "chad", "menő", "brutál", "top",
        "elit", "elite", "sztár", "star", "zseniális", "szuper", "tökéletes",
        "mester", "isten", "best", "mvp", "carry", "okos", "ügyes", "pro",
        "nagyon jó",
    )

    private val GRADE_OBJECT_KEYWORDS = setOf(
        "karó", "ötös", "négyes", "hármas", "kettes", "egyes",
        "csillagos ötös", "kampó", "bukta", "bukó", "pipa", "jeles", "jó",
        "közepes", "elégséges", "elégtelen", "dicséret", "százalék", "jegy",
        "pont", "piros pont", "fekete pont", "pacsi", "medál", "arany",
        "ezüst", "bronz", "trófea", "serleg", "kupa", "korona", "jutalom",
        "bomba", "rakéta", "intő", "szaktanári", "nyakleves", "csillag",
        "szívecske", "nulla", "nullás", "1", "2", "3", "4", "5", "1-es",
        "2-es", "3-as", "4-es", "5-ös", "w", "l",
    )

    private val ACCUSATIVE_IRREGULARS = mapOf(
        "ötös" to "ötöst", "négyes" to "négyest", "hármas" to "hármast",
        "kettes" to "kettest", "egyes" to "egyest", "jeles" to "jelest",
        "közepes" to "közepest", "elégséges" to "elégségest",
        "elégtelen" to "elégtelent", "százalék" to "százalékot",
        "jegy" to "jegyet", "pont" to "pontot", "dicséret" to "dicséretet",
        "csillag" to "csillagot", "nullás" to "nullást", "nyakleves" to "nyaklevest",
        "w" to "W-t", "l" to "L-t",
    )

    fun cleanSubjectStem(rawSubject: String): String {
        var s = rawSubject.trim()
        if (s.isEmpty()) return "tantárgy"
        s = s.replace(Regex("\\s*\\([^)]*\\)"), "").trim()
        s = s.replace(Regex("\\s+(?:X{0,2}(?:IX|IV|V?I{0,3}))\\.?$"), "").trim()
        s = s.replace(Regex("\\s+\\d+\\.?$"), "").trim()
        s = s.replace(Regex("[.,:;/-]+\\s*$"), "").trim()
        return s.ifEmpty { "tantárgy" }
    }

    private fun usesBackHarmony(wordLower: String): Boolean {
        if (wordLower.isEmpty()) return true
        for (tail in FRONT_COMPOUND_TAILS) {
            if (wordLower == tail || wordLower.endsWith(tail)) return false
        }
        for (tail in BACK_COMPOUND_TAILS) {
            if (wordLower == tail || wordLower.endsWith(tail)) return true
        }
        var hasBack = false
        var hasFrontRounded = false
        var lastSignificantIsBack = false
        var sawSignificant = false
        for (ch in wordLower) {
            when (ch) {
                in BACK_VOWELS -> {
                    hasBack = true
                    lastSignificantIsBack = true
                    sawSignificant = true
                }
                in FRONT_ROUNDED_VOWELS -> {
                    hasFrontRounded = true
                    lastSignificantIsBack = false
                    sawSignificant = true
                }
            }
        }
        if (sawSignificant) return lastSignificantIsBack
        if (hasFrontRounded) return false
        if (hasBack) return true
        return false
    }

    fun formatSubjectElative(rawSubject: String): String {
        val stem = cleanSubjectStem(rawSubject)
        val parts = stem.split(Regex("[\\s-]+"))
        val lastWord = if (parts.isNotEmpty()) parts.last().lowercase() else stem.lowercase()
        val suffix = if (usesBackHarmony(lastWord)) "ból" else "ből"
        val last = stem.last()
        val prefix = stem.dropLast(1)
        return when (last) {
            'a' -> "${prefix}á$suffix"
            'A' -> "${prefix}Á$suffix"
            'e' -> "${prefix}é$suffix"
            'E' -> "${prefix}É$suffix"
            else -> "$stem$suffix"
        }
    }

    fun formatAccusative(rawPhrase: String): String {
        var clean = rawPhrase.trim().replace(Regex("[.!?]+$"), "").trim()
        if (clean.isEmpty()) return clean
        val lw = clean.lowercase()
        clean = when (lw) {
            "1" -> "egyes"
            "2" -> "kettes"
            "3" -> "hármas"
            "4" -> "négyes"
            "5" -> "ötös"
            "1-es" -> return "1-est"
            "2-es" -> return "2-est"
            "3-as" -> return "3-ast"
            "4-es" -> return "4-est"
            "5-ös" -> return "5-öst"
            else -> clean
        }
        val words = clean.split(Regex("\\s+"))
        val lastOrig = words.last()
        val lastLower = lastOrig.lowercase()
        val inflected = when {
            ACCUSATIVE_IRREGULARS.containsKey(lastLower) -> {
                val base = ACCUSATIVE_IRREGULARS[lastLower]!!
                if (lastOrig.first().isUpperCase()) base.replaceFirstChar { it.uppercase() } else base
            }
            lastLower.endsWith("a") -> lastOrig.dropLast(1) + if (lastOrig.endsWith("A")) "Át" else "át"
            lastLower.endsWith("e") -> lastOrig.dropLast(1) + if (lastOrig.endsWith("E")) "Ét" else "ét"
            Regex("[áéíiíoóöőuúüű]$", RegexOption.IGNORE_CASE).containsMatchIn(lastLower) -> "${lastOrig}t"
            Regex("(?:ly|ny|sz|zs|j|l|n|r|s|z)$", RegexOption.IGNORE_CASE).containsMatchIn(lastLower) -> "${lastOrig}t"
            usesBackHarmony(lastLower) -> "${lastOrig}ot"
            else -> {
                var rounded = false
                for (ch in lastLower.reversed()) {
                    if (ch in FRONT_ROUNDED_VOWELS) {
                        rounded = true
                        break
                    }
                    if (ch in FRONT_VOWELS || ch in BACK_VOWELS) break
                }
                lastOrig + if (rounded) "öt" else "et"
            }
        }
        return if (words.size == 1) inflected else "${words.dropLast(1).joinToString(" ")} $inflected"
    }

    fun buildGradeNotificationBody(
        labelOrTemplate: String,
        subjectName: String,
        gradeValue: Int?,
        legacyValues: Map<String, String>,
    ): String {
        val trimmed = labelOrTemplate.trim()
        if (trimmed.contains('{') && trimmed.contains('}')) {
            return renderTemplate(trimmed, legacyValues)
        }
        val effective = trimmed.ifEmpty {
            when (gradeValue) {
                5 -> "ötös"
                4 -> "négyes"
                3 -> "hármas"
                2 -> "kettes"
                1 -> "egyes"
                else -> "értékelés"
            }
        }
        val elative = formatSubjectElative(subjectName)
        val cleanSubject = cleanSubjectStem(subjectName)
        val punct = Regex("([!?]+)$").find(effective)?.value.orEmpty()
        val labelNoPunct = effective.replace(Regex("[.!?]+$"), "").trim()
        if (labelNoPunct.isEmpty()) return "Új értékelés érkezett $elative"

        val normalized = labelNoPunct.lowercase().replace(Regex("\\s+"), " ").trim()
        val words = normalized.split(" ")
        val kind = when {
            GRADE_OBJECT_KEYWORDS.contains(normalized) -> "object"
            PERSONA_KEYWORDS.contains(normalized) -> "persona"
            Regex("\\b(vagyok|vagy|volt|lett|lettem|voltál|főztem|buktam|jött|össze|sikerült|megvan|meglett|ez|nem|jaj|rip|gg|bro)\\b").containsMatchIn(normalized) || words.size >= 3 -> "phrase"
            words.size == 2 && GRADE_OBJECT_KEYWORDS.contains(words.last()) -> "object"
            words.size == 2 && PERSONA_KEYWORDS.contains(words.last()) -> "persona"
            Regex("(?:telen|talan|ságos|séges|iális|ális|i)$").containsMatchIn(normalized) -> "persona"
            Regex("(?:tem|tam|tál|tél|sz|ok|ek|ök)$").containsMatchIn(normalized) && normalized.length > 4 -> "phrase"
            Regex("(?:ó|ő|a|e)$").containsMatchIn(normalized) -> "object"
            else -> "persona"
        }

        val cap = labelNoPunct.replaceFirstChar { it.uppercase() }
        return when (kind) {
            "persona" -> {
                val endPunct = punct.ifEmpty {
                    if (POSITIVE_PERSONAS.contains(normalized) || (gradeValue != null && gradeValue >= 5)) "!" else ""
                }
                "$cap voltál $elative$endPunct"
            }
            "object" -> {
                val acc = formatAccusative(labelNoPunct).replaceFirstChar { it.uppercase() }
                "$acc kaptál $elative$punct"
            }
            else -> {
                val fitsOutcome = Regex("^(?:ez\\s+|nem\\s+|összejött|sikerült|megvan|meglett|bevált)").containsMatchIn(normalized) && !normalized.contains("vagyok")
                if (fitsOutcome) "$cap $elative$punct" else "$cleanSubject: $labelNoPunct$punct"
            }
        }
    }
}
