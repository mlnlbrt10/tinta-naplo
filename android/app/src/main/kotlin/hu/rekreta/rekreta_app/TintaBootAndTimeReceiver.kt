package hu.rekreta.rekreta_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores widget state, Live Activity notification, and next AlarmManager tick
 * after device reboot, app update, or wall-clock time/timezone changes.
 */
class TintaBootAndTimeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            action == Intent.ACTION_DATE_CHANGED
        ) {
            TintaLiveTickReceiver.refreshAndSchedule(context)
        }
    }
}
