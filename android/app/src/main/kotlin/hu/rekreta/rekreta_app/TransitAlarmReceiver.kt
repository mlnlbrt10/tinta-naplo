package hu.rekreta.rekreta_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TransitAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val notificationId = intent?.getIntExtra("notificationId", 7090) ?: 7090
        val title = intent?.getStringExtra("title") ?: "🚶 Indulj lassan az állomásra!"
        val body = intent?.getStringExtra("body")
            ?: "A 07:09-es vonathoz legkésőbb 06:55-kor indulnod kell (10 perc séta). Ne késs el a suliból!"

        MainActivity.showNotificationNow(
            context = context.applicationContext,
            notificationId = notificationId,
            title = title,
            body = body
        )
    }
}
