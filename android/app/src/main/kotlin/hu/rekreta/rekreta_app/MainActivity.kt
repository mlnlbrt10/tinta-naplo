package hu.rekreta.rekreta_app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "hu.rekreta.rekreta_app/dynamic_icon"
        private const val LEGACY_CHANNEL_NAME = "flutter_dynamic_icon"
        private const val TRANSIT_CHANNEL_NAME = "hu.rekreta.rekreta_app/transit"
        private const val UPDATER_CHANNEL_NAME = "hu.rekreta.rekreta_app/updater"

        const val TRANSIT_NOTIFICATION_CHANNEL_ID = "rekreta_menetrendgo_alerts"
        const val TRANSIT_NOTIFICATION_CHANNEL_NAME = "MenetrendGO Indulási & Késési riasztások"
        const val PREFS_NAME = "rekreta_transit_alarms"
        const val MENETRENDGO_PACKAGE = "hu.matepazy.menetrendgo"
        const val MENETRENDGO_RELEASES_URL = "https://github.com/matepazy/menetrend-go/releases"

        private val ALIAS_MAP = mapOf(
            "icon_normal" to ".MainActivityNormal",
            "normal" to ".MainActivityNormal",
            "default" to ".MainActivityNormal",
            ".MainActivityNormal" to ".MainActivityNormal",
            "MainActivityNormal" to ".MainActivityNormal",
            "icon_oled" to ".MainActivityOled",
            "oled" to ".MainActivityOled",
            "minimal_oled" to ".MainActivityOled",
            ".MainActivityOled" to ".MainActivityOled",
            "MainActivityOled" to ".MainActivityOled",
            "icon_christmas" to ".MainActivityChristmas",
            "christmas" to ".MainActivityChristmas",
            ".MainActivityChristmas" to ".MainActivityChristmas",
            "MainActivityChristmas" to ".MainActivityChristmas",
            "icon_christmas_oled" to ".MainActivityChristmasOled",
            "christmas_oled" to ".MainActivityChristmasOled",
            ".MainActivityChristmasOled" to ".MainActivityChristmasOled",
            "MainActivityChristmasOled" to ".MainActivityChristmasOled"
        )

        private val ALL_ALIASES = listOf(
            ".MainActivityNormal",
            ".MainActivityOled",
            ".MainActivityChristmas",
            ".MainActivityChristmasOled"
        )

        fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    TRANSIT_NOTIFICATION_CHANNEL_ID,
                    TRANSIT_NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Reggeli indulási figyelmeztetések és élő járatkésések"
                    enableVibration(true)
                }
                manager.createNotificationChannel(channel)
            }
        }

        fun buildMenetrendGoIntent(context: Context): Intent {
            val pm = context.packageManager
            val launchIntent = pm.getLaunchIntentForPackage(MENETRENDGO_PACKAGE)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                return launchIntent
            }
            return Intent(Intent.ACTION_VIEW, Uri.parse(MENETRENDGO_RELEASES_URL)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }

        fun showNotificationNow(
            context: Context,
            notificationId: Int,
            title: String,
            body: String
        ) {
            ensureNotificationChannel(context)
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("from_transit_notification", true)
            }
            val openAppPending = PendingIntent.getActivity(
                context,
                notificationId * 10 + 1,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val menetrendIntent = buildMenetrendGoIntent(context)
            val menetrendPending = PendingIntent.getActivity(
                context,
                notificationId * 10 + 2,
                menetrendIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, TRANSIT_NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher_normal)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(openAppPending)
                .addAction(0, "Megnyitás az appban", openAppPending)
                .addAction(0, "MenetrendGO", menetrendPending)

            manager.notify(notificationId, builder.build())
        }

        fun scheduleExactAlarmInternal(
            context: Context,
            triggerAtMillis: Long,
            notificationId: Int,
            title: String,
            body: String
        ) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, TransitAlarmReceiver::class.java).apply {
                putExtra("notificationId", notificationId)
                putExtra("title", title)
                putExtra("body", body)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMillis,
                            pendingIntent
                        )
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
            } catch (_: SecurityException) {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel(applicationContext)

        val iconHandler = MethodChannel.MethodCallHandler { call, result ->
            handleIconMethodCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(iconHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_CHANNEL_NAME)
            .setMethodCallHandler(iconHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = (call.arguments as? Map<*, *>)?.get("filePath")?.toString()
                            ?: (call.arguments as? String)
                        if (filePath.isNullOrBlank()) {
                            result.error("NO_PATH", "filePath missing", null)
                        } else {
                            installApk(filePath, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSIT_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                handleTransitMethodCall(call, result)
            }
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(settingsIntent)
                result.success("permission_required")
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                File(filePath)
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    private fun handleIconMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setAlternateIconName", "setAppIcon" -> {
                val rawName = when (val args = call.arguments) {
                    is Map<*, *> -> (args["iconName"] ?: args["alias"] ?: args["preset"])?.toString()
                    is String -> args
                    else -> null
                } ?: "icon_normal"

                try {
                    val appliedAlias = applyLauncherAlias(rawName)
                    result.success(appliedAlias)
                } catch (e: Exception) {
                    result.error("ICON_SWITCH_FAILED", e.message, null)
                }
            }
            "getAlternateIconName", "getAppIcon" -> {
                result.success(getCurrentEnabledAlias())
            }
            "supportsAlternateIcons" -> {
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleTransitMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestNotificationPermissions" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!granted) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            9101
                        )
                    }
                }
                result.success(true)
            }
            "scheduleDepartureAlarm" -> {
                val args = call.arguments as? Map<*, *>
                val triggerAtMillis = (args?.get("triggerAtMillis") as? Number)?.toLong()
                    ?: (System.currentTimeMillis() + 60_000L)
                val notificationId = (args?.get("notificationId") as? Number)?.toInt() ?: 7090
                val title = args?.get("title")?.toString() ?: "🚶 Indulj lassan az állomásra!"
                val body = args?.get("body")?.toString() ?: ""

                val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putLong("triggerAtMillis", triggerAtMillis)
                    .putInt("notificationId", notificationId)
                    .putString("title", title)
                    .putString("body", body)
                    .apply()

                scheduleExactAlarmInternal(
                    applicationContext,
                    triggerAtMillis,
                    notificationId,
                    title,
                    body
                )
                result.success(true)
            }
            "showTransitNotification" -> {
                val args = call.arguments as? Map<*, *>
                val notificationId = (args?.get("notificationId") as? Number)?.toInt() ?: 7091
                val title = args?.get("title")?.toString() ?: "MenetrendGO"
                val body = args?.get("body")?.toString() ?: ""
                showNotificationNow(applicationContext, notificationId, title, body)
                result.success(true)
            }
            "cancelDepartureAlarms" -> {
                val alarmManager =
                    applicationContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(applicationContext, TransitAlarmReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    applicationContext,
                    7090,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
                applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .clear()
                    .apply()
                result.success(true)
            }
            "launchMenetrendGo" -> {
                try {
                    val pm = applicationContext.packageManager
                    val args = call.arguments as? Map<*, *>
                    val deepLinkStr = args?.get("deepLinkUri") as? String
                    if (!deepLinkStr.isNullOrBlank()) {
                        val deepIntent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLinkStr)).apply {
                            setPackage(MENETRENDGO_PACKAGE)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            args.forEach { (k, v) ->
                                if (k is String && v != null) {
                                    putExtra(k, v.toString())
                                }
                            }
                        }
                        if (deepIntent.resolveActivity(pm) != null) {
                            startActivity(deepIntent)
                            result.success(true)
                            return
                        }
                    }
                    val launchIntent = pm.getLaunchIntentForPackage(MENETRENDGO_PACKAGE)
                    if (launchIntent != null) {
                        args?.forEach { (k, v) ->
                            if (k is String && v != null) {
                                launchIntent.putExtra(k, v.toString())
                            }
                        }
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launchIntent)
                        result.success(true)
                    } else {
                        val fallbackIntent =
                            Intent(Intent.ACTION_VIEW, Uri.parse(MENETRENDGO_RELEASES_URL)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        startActivity(fallbackIntent)
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun applyLauncherAlias(requestedKey: String): String {
        val targetAlias = ALIAS_MAP[requestedKey] ?: ".MainActivityNormal"
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName

        // First enable the target alias so the app always has an active launcher entry
        val targetComponent = ComponentName(pkg, "$pkg$targetAlias")
        pm.setComponentEnabledSetting(
            targetComponent,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )

        // Then disable all other aliases unconditionally
        for (alias in ALL_ALIASES) {
            if (alias == targetAlias) continue
            val component = ComponentName(pkg, "$pkg$alias")
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        return targetAlias
    }

    private fun getCurrentEnabledAlias(): String {
        val pm = applicationContext.packageManager
        val pkg = applicationContext.packageName
        for (alias in ALL_ALIASES) {
            val component = ComponentName(pkg, "$pkg$alias")
            val state = pm.getComponentEnabledSetting(component)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias
            }
        }
        return ".MainActivityNormal"
    }
}
