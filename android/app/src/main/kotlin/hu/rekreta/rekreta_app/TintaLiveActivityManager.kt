package hu.rekreta.rekreta_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LiveLessonState
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LivePhase

/**
 * Manages Tinta Napló's silent ongoing Live Activity / Samsung Now Bar
 * countdown notification.
 *
 * Android 16 (API 36) / Samsung One UI Now Bar requires:
 * - A notification channel with importance >= [NotificationManager.IMPORTANCE_DEFAULT]
 *   (silent via `setSound(null, null)` and `enableVibration(false)` so it never rings/buzzes)
 * - `POST_PROMOTED_NOTIFICATIONS` permission in AndroidManifest.xml + user opt-in if gated
 * - Native `Notification.ProgressStyle` (`NotificationCompat.ProgressStyle`)
 * - `setOngoing(true)`, `setOnlyAlertOnce(true)`, `setRequestPromotedOngoing(true)`
 * - Concise `setShortCriticalText(...)` (strictly <= 7 chars) for status bar & Now Bar pills
 * - Valid monochrome vector small icon (`R.drawable.ic_stat_tinta`) and NO RemoteViews / MediaStyle
 */
object TintaLiveActivityManager {
    const val CHANNEL_ID = "tinta_live_lesson_v2"
    private const val LEGACY_CHANNEL_ID = "tinta_live_lesson"
    private const val CHANNEL_NAME = "Élő óra és visszaszámláló (Now Bar)"
    private const val NOTIFICATION_ID = 7201
    private const val BREAK_ACCENT_ARGB = 0xFFF59E0B.toInt()
    private const val MAX_SHORT_CRITICAL_TEXT_LEN = 7

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(LEGACY_CHANNEL_ID) != null) {
            nm.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        }
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null && existing.importance >= NotificationManager.IMPORTANCE_DEFAULT) {
            return
        }

        // IMPORTANCE_DEFAULT is strictly required for Android 16 Live Updates / Now Bar
        // promotion; null sound + disabled vibration keeps it completely silent.
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Aktuális óra és visszaszámláló a zárolási képernyőn és az állapotsoron"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    fun canPostPromotedNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 36) return true
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return runCatching { nm.canPostPromotedNotifications() }.getOrDefault(false)
    }

    fun openPromotedNotificationSettings(context: Context): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= 36) {
            Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        val started = runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)
        if (started) return true

        val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(fallback)
            true
        }.getOrDefault(false)
    }

    fun dismiss(context: Context) {
        runCatching {
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        }
    }

    fun syncNotification(context: Context, state: LiveLessonState) {
        ensureChannel(context)
        if (!state.liveActivityEnabled || !state.shouldShowLiveActivity) {
            dismiss(context)
            return
        }
        val nmCompat = NotificationManagerCompat.from(context)
        if (!nmCompat.areNotificationsEnabled()) {
            return
        }

        val current = state.currentLesson ?: run {
            dismiss(context)
            return
        }

        val startHHmm = TintaLiveLessonResolver.formatHHmm(state.windowStartMs)
        val endHHmm = TintaLiveLessonResolver.formatHHmm(state.windowEndMs)
        val remaining = state.remainingMinutes
        val elapsedPercent = (state.progressFraction * 100f).toInt().coerceIn(0, 100)

        val title: String
        val contentText: String
        val subText: String?
        val shortCriticalText: String
        val accentColor: Int

        when (state.phase) {
            LivePhase.ACTIVE_LESSON -> {
                accentColor = state.accentColorArgb
                val subTag = if (current.substituted) " (Helyettesítés)" else ""
                title = "${current.periodBadgeText} ${current.subject}$subTag"
                val roomPrefix = if (current.room.isNotEmpty()) "${current.room} • " else ""
                contentText = "$roomPrefix$remaining perc van hátra ($startHHmm–$endHHmm)"
                subText = state.nextLesson?.let { nxt ->
                    val nxtRoom = if (nxt.room.isNotEmpty()) " (${nxt.room})" else ""
                    "Köv: ${nxt.periodBadgeText} ${nxt.subject}$nxtRoom"
                }
                shortCriticalText = buildShortCriticalText(
                    period = current.period,
                    remainingMinutes = remaining,
                    isBreak = false,
                )
            }
            LivePhase.BREAK -> {
                accentColor = BREAK_ACCENT_ARGB
                val nxt = state.nextLesson ?: current
                title = "Szünet • Köv: ${nxt.periodBadgeText} ${nxt.subject}"
                val roomPart = if (nxt.room.isNotEmpty()) " • Terem: ${nxt.room}" else ""
                contentText = "Még $remaining perc szünet ($startHHmm–$endHHmm)$roomPart"
                subText = nxt.teacher.takeIf { it.isNotEmpty() }
                shortCriticalText = buildShortCriticalText(
                    period = nxt.period,
                    remainingMinutes = remaining,
                    isBreak = true,
                )
            }
            LivePhase.BEFORE_SCHOOL -> {
                accentColor = state.accentColorArgb
                val firstStart = TintaLiveLessonResolver.formatHHmm(current.startMs)
                val roomPrefix = if (current.room.isNotEmpty()) "${current.room} • " else ""
                title = "Hamarosan: ${current.periodBadgeText} ${current.subject}"
                contentText = "${roomPrefix}Kezdés $remaining perc múlva ($firstStart)"
                subText = current.teacher.takeIf { it.isNotEmpty() }
                shortCriticalText = buildShortCriticalText(
                    period = current.period,
                    remainingMinutes = remaining,
                    isBreak = false,
                )
            }
            LivePhase.AFTER_SCHOOL,
            LivePhase.NO_DATA -> {
                dismiss(context)
                return
            }
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tinta)
            .setColor(accentColor)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSubText(subText)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(shortCriticalText)
            .setContentIntent(
                TintaLiveLessonResolver.createOpenTimetablePendingIntent(context, NOTIFICATION_ID),
            )

        if (Build.VERSION.SDK_INT >= 36) {
            val progressStyle = NotificationCompat.ProgressStyle()
                .setProgress(elapsedPercent)
                .setStyledByProgress(true)
                .addProgressSegment(
                    NotificationCompat.ProgressStyle.Segment(100)
                        .setColor(accentColor),
                )
            builder.setStyle(progressStyle)
        } else {
            builder.setProgress(100, elapsedPercent, false)
        }

        runCatching {
            nmCompat.notify(NOTIFICATION_ID, builder.build())
        }
    }

    /**
     * Formats status-bar / Now Bar chip copy strictly <= 7 chars (`"4. 24p"`,
     * `"10•24p"`, `"Szün 6p"`).
     */
    private fun buildShortCriticalText(
        period: Int,
        remainingMinutes: Int,
        isBreak: Boolean,
    ): String {
        val rem = remainingMinutes.coerceAtLeast(1)
        val raw = if (isBreak) {
            val withSpace = "Szün ${rem}p"
            if (withSpace.length <= MAX_SHORT_CRITICAL_TEXT_LEN) {
                withSpace
            } else {
                val compact = "Szü ${rem}p"
                if (compact.length <= MAX_SHORT_CRITICAL_TEXT_LEN) compact else "Szün${rem}p"
            }
        } else if (period > 0) {
            val withPeriodSpace = "$period. ${rem}p"
            if (withPeriodSpace.length <= MAX_SHORT_CRITICAL_TEXT_LEN) {
                withPeriodSpace
            } else {
                val compact = "$period•${rem}p"
                if (compact.length <= MAX_SHORT_CRITICAL_TEXT_LEN) compact else "$period.${rem}p"
            }
        } else {
            "${rem}p"
        }
        return raw.take(MAX_SHORT_CRITICAL_TEXT_LEN)
    }
}
