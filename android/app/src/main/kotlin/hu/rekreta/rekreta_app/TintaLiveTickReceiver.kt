package hu.rekreta.rekreta_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LiveLessonState

/**
 * Unified minute-by-minute live updater for both Home Screen Widgets (`2x1` / `2x2`)
 * and the Live Activity / Samsung Now Bar notification.
 *
 * Aligns 60-second [AlarmManager.setAndAllowWhileIdle] ticks strictly to minute
 * boundaries while school is active (or within 30 minutes before the first bell),
 * and pauses overnight with a single scheduled wake-up before the next school day.
 */
class TintaLiveTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        refreshAndSchedule(context)
    }

    companion object {
        private const val TICK_REQUEST_CODE = 7202

        fun triggerBroadcastUpdate(context: Context) {
            val intent = Intent(context, TintaLiveTickReceiver::class.java).apply {
                action = TintaLiveLessonResolver.ACTION_TINTA_LIVE_UPDATE
            }
            context.sendBroadcast(intent)
        }

        fun refreshAndSchedule(context: Context) {
            val state = TintaLiveLessonResolver.resolve(context)
            TintaWidgetRenderer.updateAllWidgets(context, state)
            TintaLiveActivityManager.syncNotification(context, state)
            scheduleNextTickIfNeeded(context, state)
        }

        fun scheduleNextTickIfNeeded(context: Context, state: LiveLessonState) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = buildTickPendingIntent(context)
            alarmManager.cancel(pendingIntent)

            val hasConsumers = state.liveActivityEnabled || TintaWidgetRenderer.hasAnyActiveWidgets(context)
            if (!hasConsumers || !state.hasSyncedData) {
                return
            }

            val nextTriggerMs: Long? = when {
                state.shouldTickPerMinute -> {
                    // Align cleanly to the start of the next wall-clock minute (+250ms slack).
                    ((state.nowMs / 60_000L) + 1L) * 60_000L + 250L
                }
                else -> state.nextWakeTriggerAtMs
            }

            if (nextTriggerMs != null && nextTriggerMs > state.nowMs) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextTriggerMs,
                    pendingIntent,
                )
            }
        }

        private fun buildTickPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, TintaLiveTickReceiver::class.java).apply {
                action = TintaLiveLessonResolver.ACTION_TINTA_LIVE_UPDATE
            }
            return PendingIntent.getBroadcast(
                context,
                TICK_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
