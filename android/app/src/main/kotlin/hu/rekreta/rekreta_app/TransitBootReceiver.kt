package hu.rekreta.rekreta_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TransitBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val prefs = context.applicationContext.getSharedPreferences(
                MainActivity.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            val triggerAtMillis = prefs.getLong("triggerAtMillis", 0L)
            if (triggerAtMillis > System.currentTimeMillis()) {
                val notificationId = prefs.getInt("notificationId", 7090)
                val title = prefs.getString("title", "🚶 Indulj lassan az állomásra!")
                    ?: "🚶 Indulj lassan az állomásra!"
                val body = prefs.getString("body", "") ?: ""
                MainActivity.scheduleExactAlarmInternal(
                    context = context.applicationContext,
                    triggerAtMillis = triggerAtMillis,
                    notificationId = notificationId,
                    title = title,
                    body = body
                )
            }
        }
    }
}
