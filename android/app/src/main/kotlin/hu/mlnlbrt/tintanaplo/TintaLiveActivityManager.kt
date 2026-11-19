package hu.mlnlbrt.tintanaplo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import hu.mlnlbrt.tintanaplo.TintaLiveLessonResolver.LiveLessonState
import hu.mlnlbrt.tintanaplo.TintaLiveLessonResolver.LivePhase

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
 * - Concise `setShortCriticalText(...)` (e.g. `"4. • 24p"`, `"Szünet • 6p"`) for status bar & Now Bar pills
 * - Valid monochrome vector small icon (`R.drawable.ic_stat_tinta`) and NO RemoteViews / MediaStyle
 */
object TintaLiveActivityManager {
    const val CHANNEL_ID = "tinta_live_lesson_v2"
    private const val LEGACY_CHANNEL_ID = "tinta_live_lesson"
    private const val CHANNEL_NAME = "Élő óra és visszaszámláló (Now Bar)"
    private const val NOTIFICATION_ID = 7201
    private const val BREAK_ACCENT_ARGB = 0xFFF59E0B.toInt()

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

        val remaining = state.remainingMinutes.coerceAtLeast(1)
        val elapsedPercent = (state.progressFraction * 100f).toInt().coerceIn(0, 100)

        val title: String
        val contentText: String
        val shortCriticalText: String
        val accentColor: Int

        when (state.phase) {
            LivePhase.ACTIVE_LESSON -> {
                accentColor = state.accentColorArgb
                title = "${current.periodBadgeText} ${current.subject}".trim()
                contentText = if (current.room.isNotEmpty()) {
                    "${current.room} • $remaining perc hátra"
                } else {
                    "$remaining perc hátra"
                }
                shortCriticalText = if (current.periodBadgeText.isNotEmpty()) {
                    "${current.periodBadgeText} • ${remaining}p"
                } else {
                    "${remaining}p"
                }
            }
            LivePhase.BREAK -> {
                accentColor = BREAK_ACCENT_ARGB
                val nxt = state.nextLesson ?: current
                title = "Szünet • Köv: ${nxt.periodBadgeText} ${nxt.subject}".trim()
                contentText = if (nxt.room.isNotEmpty()) {
                    "${nxt.room} • $remaining perc hátra"
                } else {
                    "$remaining perc hátra"
                }
                shortCriticalText = "Szünet • ${remaining}p"
            }
            LivePhase.BEFORE_SCHOOL -> {
                accentColor = state.accentColorArgb
                title = "${current.periodBadgeText} ${current.subject}".trim()
                contentText = if (current.room.isNotEmpty()) {
                    "${current.room} • $remaining perc múlva"
                } else {
                    "$remaining perc múlva"
                }
                shortCriticalText = if (current.periodBadgeText.isNotEmpty()) {
                    "${current.periodBadgeText} • ${remaining}p"
                } else {
                    "${remaining}p"
                }
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
            .setSubText(null)
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
}
