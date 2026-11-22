package hu.mlnlbrt.tintanaplo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TransitAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        runCatching {
            val notificationId = intent?.getIntExtra("notificationId", 7090) ?: 7090
            val title = intent?.getStringExtra("title") ?: "🚶 Indulj lassan az állomásra!"
            val body = intent?.getStringExtra("body")
                ?: "Ideje elindulnod a következő járatodhoz!"

            MainActivity.showNotificationNow(
                context = context.applicationContext,
                notificationId = notificationId,
                title = title,
                body = body
            )
        }
    }
}
