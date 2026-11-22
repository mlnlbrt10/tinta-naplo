package hu.mlnlbrt.tintanaplo

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class TintaCompactWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        runCatching {
            val state = TintaLiveLessonResolver.resolve(context)
            TintaWidgetRenderer.updateCompactWidgets(context, appWidgetManager, appWidgetIds, state)
            TintaLiveActivityManager.syncNotification(context, state)
            TintaLiveTickReceiver.scheduleNextTickIfNeeded(context, state)
        }
    }

    override fun onEnabled(context: Context) {
        TintaLiveTickReceiver.refreshAndSchedule(context)
    }

    override fun onDisabled(context: Context) {
        TintaLiveTickReceiver.refreshAndSchedule(context)
    }
}
