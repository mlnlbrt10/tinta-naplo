package hu.mlnlbrt.tintanaplo

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.ceil

object TintaLiveLessonResolver {
    const val PREFS_NAME = "tinta_home_widget_prefs"
    const val KEY_TIMETABLE_JSON = "timetable_json"
    const val KEY_LIVE_ACTIVITY_ENABLED = "live_activity_enabled"
    const val KEY_ACCENT_COLOR_ARGB = "accent_color_argb"
    const val KEY_UPDATED_AT_MS = "updated_at_ms"

    const val ACTION_TINTA_LIVE_UPDATE = "hu.mlnlbrt.tintanaplo.ACTION_TINTA_LIVE_UPDATE"
    const val EXTRA_OPEN_TAB = "extra_open_tab"
    const val TAB_TIMETABLE = "timetable"

    const val DEFAULT_ACCENT_COLOR_ARGB = 0xFF38BDF8.toInt()
    private const val PRE_SCHOOL_TICK_WINDOW_MS = 30L * 60L * 1000L
    private const val PRE_SCHOOL_LIVE_ACTIVITY_WINDOW_MS = 20L * 60L * 1000L

    enum class LivePhase {
        ACTIVE_LESSON,
        BREAK,
        BEFORE_SCHOOL,
        AFTER_SCHOOL,
        NO_DATA,
    }

    data class LessonItem(
        val uid: String,
        val period: Int,
        val subject: String,
        val room: String,
        val teacher: String,
        val startMs: Long,
        val endMs: Long,
        val cancelled: Boolean,
        val substituted: Boolean,
        val dateKey: String,
    ) {
        val periodBadgeText: String
            get() = if (period > 0) "$period." else "•"
    }

    data class LiveLessonState(
        val phase: LivePhase,
        val nowMs: Long,
        val accentColorArgb: Int,
        val liveActivityEnabled: Boolean,
        val hasSyncedData: Boolean,
        val currentLesson: LessonItem?,
        val previousLesson: LessonItem?,
        val nextLesson: LessonItem?,
        val upcomingToday: List<LessonItem>,
        val nextSchoolDayLessons: List<LessonItem>,
        val remainingMinutes: Int,
        val progressFraction: Float,
        val remainingFraction: Float,
        val windowStartMs: Long,
        val windowEndMs: Long,
        val shouldTickPerMinute: Boolean,
        val shouldShowLiveActivity: Boolean,
        val nextWakeTriggerAtMs: Long?,
    )

    fun saveTimetableData(
        context: Context,
        timetableJson: String,
        accentColorArgb: Int?,
        liveActivityEnabled: Boolean?,
        updatedAtMs: Long?,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
            .putString(KEY_TIMETABLE_JSON, timetableJson)
            .putLong(KEY_UPDATED_AT_MS, updatedAtMs ?: System.currentTimeMillis())
        if (accentColorArgb != null) {
            editor.putInt(KEY_ACCENT_COLOR_ARGB, accentColorArgb)
        }
        if (liveActivityEnabled != null) {
            editor.putBoolean(KEY_LIVE_ACTIVITY_ENABLED, liveActivityEnabled)
        }
        editor.apply()
    }

    fun setLiveActivityEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_LIVE_ACTIVITY_ENABLED, enabled)
            .apply()
    }

    fun isLiveActivityEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_LIVE_ACTIVITY_ENABLED, false)

    fun createOpenTimetablePendingIntent(context: Context, requestCode: Int): PendingIntent {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_TAB, TAB_TIMETABLE)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun formatHHmm(epochMs: Long): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))

    fun formatDayHeaderLabel(epochMs: Long, nowMs: Long): String {
        val targetCal = Calendar.getInstance().apply { timeInMillis = epochMs }
        val nowCal = Calendar.getInstance().apply { timeInMillis = nowMs }
        val tomorrowCal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            add(Calendar.DAY_OF_YEAR, 1)
        }
        if (isSameCalendarDay(targetCal, nowCal)) return "Ma"
        if (isSameCalendarDay(targetCal, tomorrowCal)) return "Holnap"
        return when (targetCal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> "Hétfő"
            Calendar.TUESDAY -> "Kedd"
            Calendar.WEDNESDAY -> "Szerda"
            Calendar.THURSDAY -> "Csütörtök"
            Calendar.FRIDAY -> "Péntek"
            Calendar.SATURDAY -> "Szombat"
            Calendar.SUNDAY -> "Vasárnap"
            else -> SimpleDateFormat("EEEE", Locale("hu")).format(Date(epochMs))
        }
    }

    fun resolve(context: Context, nowMs: Long = System.currentTimeMillis()): LiveLessonState {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val rawJson = prefs.getString(KEY_TIMETABLE_JSON, null)
        val liveEnabled = prefs.getBoolean(KEY_LIVE_ACTIVITY_ENABLED, false)
        val savedAccent = prefs.getInt(KEY_ACCENT_COLOR_ARGB, DEFAULT_ACCENT_COLOR_ARGB)

        if (rawJson.isNullOrBlank()) {
            return LiveLessonState(
                phase = LivePhase.NO_DATA,
                nowMs = nowMs,
                accentColorArgb = savedAccent,
                liveActivityEnabled = liveEnabled,
                hasSyncedData = false,
                currentLesson = null,
                previousLesson = null,
                nextLesson = null,
                upcomingToday = emptyList(),
                nextSchoolDayLessons = emptyList(),
                remainingMinutes = 0,
                progressFraction = 0f,
                remainingFraction = 0f,
                windowStartMs = 0L,
                windowEndMs = 0L,
                shouldTickPerMinute = false,
                shouldShowLiveActivity = false,
                nextWakeTriggerAtMs = null,
            )
        }

        val parsed = runCatching { JSONObject(rawJson) }.getOrNull()
        if (parsed == null) {
            return LiveLessonState(
                phase = LivePhase.NO_DATA,
                nowMs = nowMs,
                accentColorArgb = savedAccent,
                liveActivityEnabled = liveEnabled,
                hasSyncedData = false,
                currentLesson = null,
                previousLesson = null,
                nextLesson = null,
                upcomingToday = emptyList(),
                nextSchoolDayLessons = emptyList(),
                remainingMinutes = 0,
                progressFraction = 0f,
                remainingFraction = 0f,
                windowStartMs = 0L,
                windowEndMs = 0L,
                shouldTickPerMinute = false,
                shouldShowLiveActivity = false,
                nextWakeTriggerAtMs = null,
            )
        }

        val accentColorArgb = if (parsed.has("accentColorArgb") && !parsed.isNull("accentColorArgb")) {
            parsed.optInt("accentColorArgb", savedAccent)
        } else {
            savedAccent
        }

        val lessonsArray = parsed.optJSONArray("lessons")
        val allLessons = mutableListOf<LessonItem>()
        if (lessonsArray != null) {
            for (i in 0 until lessonsArray.length()) {
                val obj = lessonsArray.optJSONObject(i) ?: continue
                val startMs = obj.optLong("startMs", 0L)
                val endMs = obj.optLong("endMs", 0L)
                if (startMs <= 0L || endMs <= startMs) continue
                allLessons.add(
                    LessonItem(
                        uid = obj.optString("uid", "$startMs"),
                        period = obj.optInt("period", 0),
                        subject = obj.optString("subject", "Óra").ifBlank { "Óra" },
                        room = obj.optString("room", "").trim(),
                        teacher = obj.optString("teacher", "").trim(),
                        startMs = startMs,
                        endMs = endMs,
                        cancelled = obj.optBoolean("cancelled", false),
                        substituted = obj.optBoolean("substituted", false),
                        dateKey = obj.optString("dateKey", ""),
                    )
                )
            }
        }
        allLessons.sortBy { it.startMs }

        val activeLessons = allLessons.filter { !it.cancelled }
        val todayStartMs = startOfDayMs(nowMs)
        val tomorrowStartMs = startOfDayMs(todayStartMs + 26L * 3600L * 1000L)

        val todaysActive = activeLessons.filter { it.startMs in todayStartMs until tomorrowStartMs }
        val futureActive = activeLessons.filter { it.startMs >= tomorrowStartMs }
        val nextDayLessons = if (futureActive.isNotEmpty()) {
            val firstNextDayStart = startOfDayMs(futureActive.first().startMs)
            val firstNextDayEnd = startOfDayMs(firstNextDayStart + 26L * 3600L * 1000L)
            futureActive.filter { it.startMs in firstNextDayStart until firstNextDayEnd }
        } else {
            emptyList()
        }

        // 1. Check active lesson right now (`startMs <= nowMs < endMs`)
        val activeIdx = todaysActive.indexOfFirst { nowMs >= it.startMs && nowMs < it.endMs }
        if (activeIdx >= 0) {
            val current = todaysActive[activeIdx]
            val upcoming = if (activeIdx + 1 < todaysActive.size) {
                todaysActive.subList(activeIdx + 1, todaysActive.size)
            } else {
                emptyList()
            }
            val totalMs = (current.endMs - current.startMs).coerceAtLeast(1L)
            val elapsed = ((nowMs - current.startMs).toDouble() / totalMs.toDouble()).coerceIn(0.0, 1.0).toFloat()
            val remFrac = (1f - elapsed).coerceIn(0f, 1f)
            val remMin = ceil((current.endMs - nowMs).toDouble() / 60_000.0).toInt().coerceAtLeast(1)

            return LiveLessonState(
                phase = LivePhase.ACTIVE_LESSON,
                nowMs = nowMs,
                accentColorArgb = accentColorArgb,
                liveActivityEnabled = liveEnabled,
                hasSyncedData = true,
                currentLesson = current,
                previousLesson = if (activeIdx > 0) todaysActive[activeIdx - 1] else null,
                nextLesson = upcoming.firstOrNull(),
                upcomingToday = upcoming,
                nextSchoolDayLessons = nextDayLessons,
                remainingMinutes = remMin,
                progressFraction = elapsed,
                remainingFraction = remFrac,
                windowStartMs = current.startMs,
                windowEndMs = current.endMs,
                shouldTickPerMinute = true,
                shouldShowLiveActivity = true,
                nextWakeTriggerAtMs = null,
            )
        }

        val nextToday = todaysActive.firstOrNull { it.startMs > nowMs }
        val lastEndedToday = todaysActive.lastOrNull { it.endMs <= nowMs }

        // 2. Break between two active lessons today
        if (lastEndedToday != null && nextToday != null) {
            val upcoming = todaysActive.filter { it.startMs >= nextToday.startMs }
            val totalMs = (nextToday.startMs - lastEndedToday.endMs).coerceAtLeast(1L)
            val elapsed = ((nowMs - lastEndedToday.endMs).toDouble() / totalMs.toDouble()).coerceIn(0.0, 1.0).toFloat()
            val remFrac = (1f - elapsed).coerceIn(0f, 1f)
            val remMin = ceil((nextToday.startMs - nowMs).toDouble() / 60_000.0).toInt().coerceAtLeast(1)

            return LiveLessonState(
                phase = LivePhase.BREAK,
                nowMs = nowMs,
                accentColorArgb = accentColorArgb,
                liveActivityEnabled = liveEnabled,
                hasSyncedData = true,
                currentLesson = nextToday,
                previousLesson = lastEndedToday,
                nextLesson = nextToday,
                upcomingToday = upcoming,
                nextSchoolDayLessons = nextDayLessons,
                remainingMinutes = remMin,
                progressFraction = elapsed,
                remainingFraction = remFrac,
                windowStartMs = lastEndedToday.endMs,
                windowEndMs = nextToday.startMs,
                shouldTickPerMinute = true,
                shouldShowLiveActivity = true,
                nextWakeTriggerAtMs = null,
            )
        }

        // 3. Before today's first lesson
        if (nextToday != null && lastEndedToday == null) {
            val msUntilFirst = nextToday.startMs - nowMs
            val inTickWindow = msUntilFirst <= PRE_SCHOOL_TICK_WINDOW_MS
            val inLiveWindow = msUntilFirst <= PRE_SCHOOL_LIVE_ACTIVITY_WINDOW_MS
            val windowStart = nextToday.startMs - PRE_SCHOOL_TICK_WINDOW_MS
            val elapsed = if (inTickWindow) {
                ((nowMs - windowStart).toDouble() / PRE_SCHOOL_TICK_WINDOW_MS.toDouble())
                    .coerceIn(0.0, 1.0)
                    .toFloat()
            } else {
                0f
            }
            val remFrac = (1f - elapsed).coerceIn(0f, 1f)
            val remMin = ceil(msUntilFirst.toDouble() / 60_000.0).toInt().coerceAtLeast(1)

            return LiveLessonState(
                phase = LivePhase.BEFORE_SCHOOL,
                nowMs = nowMs,
                accentColorArgb = accentColorArgb,
                liveActivityEnabled = liveEnabled,
                hasSyncedData = true,
                currentLesson = nextToday,
                previousLesson = null,
                nextLesson = nextToday,
                upcomingToday = todaysActive,
                nextSchoolDayLessons = nextDayLessons,
                remainingMinutes = remMin,
                progressFraction = elapsed,
                remainingFraction = remFrac,
                windowStartMs = windowStart,
                windowEndMs = nextToday.startMs,
                shouldTickPerMinute = inTickWindow,
                shouldShowLiveActivity = inLiveWindow,
                nextWakeTriggerAtMs = if (inTickWindow) null else windowStart,
            )
        }

        // 4. After school (or day with no remaining lessons) -> preview next school day
        val nextFirst = nextDayLessons.firstOrNull()
        val wakeAt = nextFirst?.let { it.startMs - PRE_SCHOOL_TICK_WINDOW_MS }?.takeIf { it > nowMs }
        return LiveLessonState(
            phase = LivePhase.AFTER_SCHOOL,
            nowMs = nowMs,
            accentColorArgb = accentColorArgb,
            liveActivityEnabled = liveEnabled,
            hasSyncedData = true,
            currentLesson = null,
            previousLesson = lastEndedToday,
            nextLesson = nextFirst,
            upcomingToday = emptyList(),
            nextSchoolDayLessons = nextDayLessons,
            remainingMinutes = 0,
            progressFraction = 0f,
            remainingFraction = 0f,
            windowStartMs = 0L,
            windowEndMs = 0L,
            shouldTickPerMinute = false,
            shouldShowLiveActivity = false,
            nextWakeTriggerAtMs = wakeAt,
        )
    }

    private fun startOfDayMs(epochMs: Long): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }

    private fun isSameCalendarDay(a: Calendar, b: Calendar): Boolean =
        a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
}
