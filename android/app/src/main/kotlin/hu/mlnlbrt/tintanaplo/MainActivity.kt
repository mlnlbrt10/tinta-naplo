package hu.mlnlbrt.tintanaplo

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import java.io.File
import java.net.URLConnection
import java.util.TimeZone
import java.util.concurrent.Executors
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import hu.mlnlbrt.tintanaplo.shared.KretaSharedConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/dynamic_icon"
        private const val LEGACY_CHANNEL_NAME = "flutter_dynamic_icon"
        private const val TRANSIT_CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/transit"
        private const val UPDATER_CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/updater"
        private const val CALENDAR_CHANNEL_NAME = "tinta_naplo/calendar_sync"
        private const val WEAR_SYNC_CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/wear_sync"
        private const val HOME_WIDGET_CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/home_widget"
        private const val NOTIFICATIONS_CHANNEL_NAME = "hu.mlnlbrt.tintanaplo/notifications"
        private const val CALENDAR_PERMISSION_REQUEST_CODE = 4208
        private const val LIVE_ACTIVITY_PERMISSION_REQUEST_CODE = 4209
        private const val KRETA_NOTIFICATIONS_PERMISSION_REQUEST_CODE = 4210

        const val EXTRA_WEAR_AUTH_REQUEST = "extra_wear_auth_request"

        const val TRANSIT_NOTIFICATION_CHANNEL_ID = "tinta_menetrendgo_alerts"
        const val TRANSIT_NOTIFICATION_CHANNEL_NAME = "MenetrendGO Indulási & Késési riasztások"
        const val PREFS_NAME = "tinta_transit_alarms"
        const val MENETRENDGO_PACKAGE = "hu.matepazy.menetrendgo"
        const val MENETRENDGO_RELEASES_URL = "https://github.com/matepazy/menetrend-go/releases"

        private val ALIAS_MAP = mapOf(
            "icon_normal" to ".MainActivityNormal",
            "normal" to ".MainActivityNormal",
            "default" to ".MainActivityNormal",
            ".MainActivityNormal" to ".MainActivityNormal",
            "MainActivityNormal" to ".MainActivityNormal",
            "classic" to ".MainActivityClassic",
            "icon_classic" to ".MainActivityClassic",
            ".MainActivityClassic" to ".MainActivityClassic",
            "MainActivityClassic" to ".MainActivityClassic",
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
            "MainActivityChristmasOled" to ".MainActivityChristmasOled",
            "icon_fityma" to ".MainActivityFityma",
            "fityma" to ".MainActivityFityma",
            ".MainActivityFityma" to ".MainActivityFityma",
            "MainActivityFityma" to ".MainActivityFityma"
        )

        private val ALL_ALIASES = listOf(
            ".MainActivityNormal",
            ".MainActivityClassic",
            ".MainActivityOled",
            ".MainActivityChristmas",
            ".MainActivityChristmasOled",
            ".MainActivityFityma"
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
                .setSmallIcon(R.drawable.ic_stat_tinta)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(openAppPending)
                .addAction(0, "Megnyitás az appban", openAppPending)
                .addAction(0, "MenetrendGO", menetrendPending)

            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    return
                }
                manager.notify(notificationId, builder.build())
            }
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

    private var wearSyncChannel: MethodChannel? = null
    private var homeWidgetChannel: MethodChannel? = null
    private var pendingLiveActivityPermissionResult: MethodChannel.Result? = null
    private var pendingKretaNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingOpenTimetableTab: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        inspectAndConsumeWearAuthIntent(intent)
        inspectAndConsumeHomeWidgetIntent(intent, fromNewIntent = false)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        inspectAndConsumeWearAuthIntent(intent)
        inspectAndConsumeHomeWidgetIntent(intent, fromNewIntent = true)
        super.onNewIntent(intent)
    }

    private fun inspectAndConsumeHomeWidgetIntent(incoming: Intent?, fromNewIntent: Boolean) {
        if (incoming == null) return
        val tab = incoming.getStringExtra(TintaLiveLessonResolver.EXTRA_OPEN_TAB)
        if (tab == TintaLiveLessonResolver.TAB_TIMETABLE) {
            incoming.removeExtra(TintaLiveLessonResolver.EXTRA_OPEN_TAB)
            val activeChannel = homeWidgetChannel
            if (fromNewIntent && activeChannel != null) {
                activeChannel.invokeMethod("openTimetableTab", null)
            } else {
                pendingOpenTimetableTab = true
            }
        }
    }

    private fun inspectAndConsumeWearAuthIntent(incoming: Intent?) {
        if (incoming == null) return
        val data = incoming.data
        val isWearDeepLink = data != null &&
            data.scheme == KretaSharedConfig.WEAR_DEEP_LINK_SCHEME &&
            data.host == KretaSharedConfig.WEAR_DEEP_LINK_HOST
        val isWearExtra = incoming.getBooleanExtra(EXTRA_WEAR_AUTH_REQUEST, false)
        if (!isWearDeepLink && !isWearExtra) return

        if (isWearDeepLink) {
            // Strip deep-link URI before FlutterActivity processes it as a Navigator route.
            incoming.data = null
            incoming.action = Intent.ACTION_MAIN
        }
        incoming.removeExtra(EXTRA_WEAR_AUTH_REQUEST)
        WearSessionBridge.markPendingWatchAuthRequest()
        WearSessionBridge.notifyActiveFlutterAuthRequest()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel(applicationContext)
        KretaNotificationDispatcher.ensureChannel(applicationContext)
        TintaLiveActivityManager.ensureChannel(applicationContext)

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
                    "openFile" -> {
                        val args = call.arguments as? Map<*, *>
                        val filePath = args?.get("filePath")?.toString()
                            ?: (call.arguments as? String)
                        val mimeType = args?.get("mimeType")?.toString()
                        if (filePath.isNullOrBlank()) {
                            result.error("NO_PATH", "filePath missing", null)
                        } else {
                            openFileWithProvider(filePath, mimeType, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSIT_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                handleTransitMethodCall(call, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                handleCalendarMethodCall(call, result)
            }

        val wearChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WEAR_SYNC_CHANNEL_NAME,
        )
        wearSyncChannel = wearChannel
        wearChannel.setMethodCallHandler { call, result ->
            handleWearSyncMethodCall(call, result)
        }
        WearSessionBridge.registerAuthRequestListener {
            wearSyncChannel?.invokeMethod("onWatchAuthRequested", null)
        }
        WearSessionBridge.registerSessionUpdatedListener { snapshot ->
            wearSyncChannel?.invokeMethod("onSessionUpdatedFromWatch", snapshot.toMethodMap())
        }

        val widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_WIDGET_CHANNEL_NAME,
        )
        homeWidgetChannel = widgetChannel
        widgetChannel.setMethodCallHandler { call, result ->
            handleHomeWidgetMethodCall(call, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            handleNotificationsMethodCall(call, result)
        }
    }

    private fun handleNotificationsMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasNotificationPermissions" -> {
                result.success(KretaNotificationDispatcher.hasNotificationPermission(this))
            }
            "requestNotificationPermissions" -> {
                if (KretaNotificationDispatcher.hasNotificationPermission(this)) {
                    result.success(true)
                    return
                }
                if (pendingKretaNotificationPermissionResult != null) {
                    result.success(false)
                    return
                }
                pendingKretaNotificationPermissionResult = result
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        KRETA_NOTIFICATIONS_PERMISSION_REQUEST_CODE,
                    )
                } else {
                    pendingKretaNotificationPermissionResult = null
                    result.success(true)
                }
            }
            "showNotification" -> {
                val args = call.arguments as? Map<*, *>
                val notificationId = (args?.get("notificationId") as? Number)?.toInt() ?: 8100
                val category = args?.get("category")?.toString().orEmpty()
                val title = args?.get("title")?.toString() ?: "Tinta Napló"
                val body = args?.get("body")?.toString().orEmpty()
                KretaNotificationDispatcher.showNotification(
                    applicationContext,
                    notificationId,
                    category,
                    title,
                    body,
                )
                result.success(true)
            }
            "configureBackgroundSync" -> {
                val args = call.arguments as? Map<*, *>
                val enabled = args?.get("enabled") as? Boolean ?: true
                val intervalMinutes = (args?.get("intervalMinutes") as? Number)?.toInt() ?: 15
                KretaNotificationDispatcher.schedulePeriodicSync(
                    applicationContext,
                    enabled,
                    intervalMinutes,
                )
                result.success(true)
            }
            "triggerImmediateSync" -> {
                KretaNotificationDispatcher.enqueueImmediateSync(applicationContext)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleHomeWidgetMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncTimetableData" -> {
                val args = call.arguments as? Map<*, *>
                val json = args?.get("timetableJson")?.toString()
                if (json.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                val accent = (args["accentColorArgb"] as? Number)?.toInt()
                val liveEnabled = args["liveActivityEnabled"] as? Boolean
                val updatedAt = (args["updatedAtMs"] as? Number)?.toLong()
                TintaLiveLessonResolver.saveTimetableData(
                    context = applicationContext,
                    timetableJson = json,
                    accentColorArgb = accent,
                    liveActivityEnabled = liveEnabled,
                    updatedAtMs = updatedAt,
                )
                TintaLiveTickReceiver.triggerBroadcastUpdate(applicationContext)
                result.success(true)
            }
            "setLiveActivityEnabled" -> {
                val args = call.arguments as? Map<*, *>
                val enabled = args?.get("enabled") as? Boolean ?: false
                val requestPermission = args?.get("requestPermission") as? Boolean ?: true
                if (!enabled) {
                    TintaLiveLessonResolver.setLiveActivityEnabled(applicationContext, false)
                    TintaLiveActivityManager.dismiss(applicationContext)
                    TintaLiveTickReceiver.triggerBroadcastUpdate(applicationContext)
                    result.success(true)
                    return
                }
                val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED
                } else {
                    true
                }
                if (granted) {
                    TintaLiveLessonResolver.setLiveActivityEnabled(applicationContext, true)
                    TintaLiveTickReceiver.triggerBroadcastUpdate(applicationContext)
                    result.success(true)
                } else if (!requestPermission) {
                    result.success(false)
                } else {
                    if (pendingLiveActivityPermissionResult != null) {
                        result.error("PERMISSION_IN_PROGRESS", "Notification permission request already in progress", null)
                        return
                    }
                    pendingLiveActivityPermissionResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        LIVE_ACTIVITY_PERMISSION_REQUEST_CODE,
                    )
                }
            }
            "refreshLiveUpdateNow" -> {
                TintaLiveTickReceiver.triggerBroadcastUpdate(applicationContext)
                result.success(true)
            }
            "canPostPromotedNotifications" -> {
                result.success(
                    TintaLiveActivityManager.canPostPromotedNotifications(applicationContext),
                )
            }
            "openPromotedNotificationSettings" -> {
                result.success(
                    TintaLiveActivityManager.openPromotedNotificationSettings(this),
                )
            }
            "consumePendingOpenTimetableTab" -> {
                val pending = pendingOpenTimetableTab
                pendingOpenTimetableTab = false
                result.success(pending)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleWearSyncMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumePendingWatchAuthRequest" -> {
                result.success(WearSessionBridge.consumePendingWatchAuthRequest())
            }
            "cacheSessionForWear" -> {
                val args = call.arguments as? Map<*, *>
                val snapshot = args?.let { PhoneWearSessionSnapshot.fromMethodArgs(it) }
                if (snapshot == null) {
                    result.success(false)
                } else {
                    WearSessionBridge.cacheSession(applicationContext, snapshot)
                    result.success(true)
                }
            }
            "pushSessionToWatch" -> {
                val args = call.arguments as? Map<*, *>
                val snapshot = args?.let { PhoneWearSessionSnapshot.fromMethodArgs(it) }
                if (snapshot == null) {
                    result.success(false)
                } else {
                    WearSessionBridge.pushSessionToWatch(applicationContext, snapshot) { ok ->
                        runOnUiThread { result.success(ok) }
                    }
                }
            }
            "pushDashboardToWatch" -> {
                val args = call.arguments as? Map<*, *>
                val snapshot = args?.let { PhoneWearSessionSnapshot.fromMethodArgs(it) }
                if (snapshot == null) {
                    result.success(false)
                } else {
                    WearSessionBridge.pushDashboardToWatch(applicationContext, snapshot) { ok ->
                        runOnUiThread { result.success(ok) }
                    }
                }
            }
            "getCachedSessionForPhone" -> {
                val cached = WearSessionBridge.loadCachedSession(applicationContext)
                result.success(cached?.toMethodMap())
            }
            "clearWearSession" -> {
                WearSessionBridge.clearSession(applicationContext)
                result.success(true)
            }
            "getWearConnectionStatus" -> {
                WearSessionBridge.getConnectionStatus(applicationContext) { status ->
                    runOnUiThread { result.success(status) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun readPackageArchiveInfo(apkPath: String): PackageInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                apkPath,
                PackageManager.PackageInfoFlags.of(0L)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(apkPath, 0)
        }
    }

    private fun readInstalledPackageInfo(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0L)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            val shareFile = ensureFileInCacheDir(filePath)
            val archiveInfo = readPackageArchiveInfo(shareFile.absolutePath)
            if (archiveInfo == null) {
                runCatching { shareFile.delete() }
                result.error(
                    "INVALID_APK",
                    "A letöltött telepítőfájl sérült vagy nem érvényes Android APK.",
                    null
                )
                return
            }
            if (archiveInfo.packageName != packageName) {
                runCatching { shareFile.delete() }
                result.error(
                    "PACKAGE_MISMATCH",
                    "A letöltött APK csomagneve (${archiveInfo.packageName}) nem egyezik az alkalmazáséval.",
                    null
                )
                return
            }
            val incomingVersionCode = PackageInfoCompat.getLongVersionCode(archiveInfo)
            val installedVersionCode = PackageInfoCompat.getLongVersionCode(readInstalledPackageInfo())
            if (incomingVersionCode < installedVersionCode) {
                result.error(
                    "VERSION_DOWNGRADE",
                    "A letöltött APK verziókódja ($incomingVersionCode) alacsonyabb a jelenleg telepítetténél ($installedVersionCode).",
                    null
                )
                return
            }
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
                shareFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("apk", uri)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    private fun ensureFileInCacheDir(filePath: String): File {
        val sourceFile = File(filePath)
        if (!sourceFile.exists() || !sourceFile.isFile || sourceFile.length() <= 0L) {
            throw IllegalStateException("A telepítő fájl hiányzik vagy üres: $filePath")
        }
        val targetFile = File(cacheDir, sourceFile.name)
        return if (sourceFile.canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)) {
            sourceFile
        } else {
            sourceFile.copyTo(targetFile, overwrite = true)
            targetFile
        }
    }

    private fun openFileWithProvider(
        filePath: String,
        requestedMimeType: String?,
        result: MethodChannel.Result
    ) {
        try {
            val shareFile = ensureFileInCacheDir(filePath)
            val ext = shareFile.extension.lowercase()
            val detectedMime = requestedMimeType?.takeIf { it.isNotBlank() }
                ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                ?: URLConnection.guessContentTypeFromName(shareFile.name)
                ?: "*/*"
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                shareFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, detectedMime)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            try {
                startActivity(intent)
            } catch (_: Exception) {
                val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "*/*")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                }
                startActivity(
                    Intent.createChooser(fallbackIntent, shareFile.name).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }
            result.success("opened")
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
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
                val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val savedId = prefs.getInt("notificationId", 7090)
                for (id in setOf(savedId, 7090)) {
                    val intent = Intent(applicationContext, TransitAlarmReceiver::class.java)
                    val pendingIntent = PendingIntent.getBroadcast(
                        applicationContext,
                        id,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    runCatching { alarmManager.cancel(pendingIntent) }
                }
                prefs.edit().clear().apply()
                result.success(true)
            }
            "launchMenetrendGo" -> {
                try {
                    val pm = applicationContext.packageManager
                    val args = call.arguments as? Map<*, *>

                    fun populateExtras(intent: Intent) {
                        args?.forEach { (k, v) ->
                            if (k is String && v != null && k != "deepLinkUris") {
                                when (v) {
                                    is Double -> intent.putExtra(k, v)
                                    is Float -> intent.putExtra(k, v)
                                    is Int -> intent.putExtra(k, v)
                                    is Long -> intent.putExtra(k, v)
                                    is Boolean -> intent.putExtra(k, v)
                                    else -> intent.putExtra(k, v.toString())
                                }
                            }
                        }
                        val query = args?.get("query")?.toString()
                        if (!query.isNullOrBlank()) {
                            intent.putExtra(android.app.SearchManager.QUERY, query)
                            intent.putExtra(Intent.EXTRA_TEXT, query)
                        }
                    }

                    val candidateUris = mutableListOf<String>()
                    (args?.get("deepLinkUris") as? List<*>)?.forEach { item ->
                        val s = item?.toString()
                        if (!s.isNullOrBlank()) candidateUris.add(s)
                    }
                    val singleUri = args?.get("deepLinkUri") as? String
                    if (!singleUri.isNullOrBlank() && !candidateUris.contains(singleUri)) {
                        candidateUris.add(0, singleUri)
                    }

                    // 1. Try each candidate deep-link URI (menetrendgo://search?..., https://menetrendgo.hu/...)
                    for (uriStr in candidateUris) {
                        val deepIntent = Intent(Intent.ACTION_VIEW, Uri.parse(uriStr)).apply {
                            setPackage(MENETRENDGO_PACKAGE)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            populateExtras(this)
                        }
                        if (deepIntent.resolveActivity(pm) != null) {
                            startActivity(deepIntent)
                            result.success(true)
                            return
                        }
                    }

                    // 2. Try ACTION_SEARCH intent targeted at MenetrendGO
                    val searchIntent = Intent(Intent.ACTION_SEARCH).apply {
                        setPackage(MENETRENDGO_PACKAGE)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        populateExtras(this)
                    }
                    if (searchIntent.resolveActivity(pm) != null) {
                        startActivity(searchIntent)
                        result.success(true)
                        return
                    }

                    // 3. Fallback to package launcher intent with pre-populated deep-link URI & route search extras
                    val launchIntent = pm.getLaunchIntentForPackage(MENETRENDGO_PACKAGE)
                    if (launchIntent != null) {
                        populateExtras(launchIntent)
                        candidateUris.firstOrNull()?.let { launchIntent.data = Uri.parse(it) }
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        try {
                            startActivity(launchIntent)
                        } catch (_: Exception) {
                            val plainLaunch = pm.getLaunchIntentForPackage(MENETRENDGO_PACKAGE)
                            if (plainLaunch != null) {
                                populateExtras(plainLaunch)
                                plainLaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                                startActivity(plainLaunch)
                            } else {
                                throw IllegalStateException("MenetrendGO launch intent missing")
                            }
                        }
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

    private val calendarExecutor = Executors.newSingleThreadExecutor()
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null

    override fun onDestroy() {
        WearSessionBridge.registerAuthRequestListener(null)
        WearSessionBridge.registerSessionUpdatedListener(null)
        wearSyncChannel?.setMethodCallHandler(null)
        wearSyncChannel = null
        homeWidgetChannel?.setMethodCallHandler(null)
        homeWidgetChannel = null
        pendingCalendarPermissionResult = null
        pendingLiveActivityPermissionResult = null
        pendingKretaNotificationPermissionResult = null
        calendarExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALENDAR_PERMISSION_REQUEST_CODE) {
            val pending = pendingCalendarPermissionResult
            pendingCalendarPermissionResult = null
            pending?.success(hasCalendarPermissions())
        } else if (requestCode == LIVE_ACTIVITY_PERMISSION_REQUEST_CODE) {
            val pending = pendingLiveActivityPermissionResult
            pendingLiveActivityPermissionResult = null
            val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            TintaLiveLessonResolver.setLiveActivityEnabled(applicationContext, granted)
            if (granted) {
                TintaLiveTickReceiver.triggerBroadcastUpdate(applicationContext)
            } else {
                TintaLiveActivityManager.dismiss(applicationContext)
            }
            pending?.success(granted)
        } else if (requestCode == KRETA_NOTIFICATIONS_PERMISSION_REQUEST_CODE) {
            val pending = pendingKretaNotificationPermissionResult
            pendingKretaNotificationPermissionResult = null
            pending?.success(KretaNotificationDispatcher.hasNotificationPermission(this))
        }
    }

    private fun hasCalendarPermissions(): Boolean {
        val readGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        val writeGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        return readGranted && writeGranted
    }

    private fun handleCalendarMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasCalendarPermissions" -> {
                result.success(hasCalendarPermissions())
            }
            "requestCalendarPermissions" -> {
                if (hasCalendarPermissions()) {
                    result.success(true)
                    return
                }
                pendingCalendarPermissionResult?.success(false)
                pendingCalendarPermissionResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_CALENDAR,
                        Manifest.permission.WRITE_CALENDAR
                    ),
                    CALENDAR_PERMISSION_REQUEST_CODE
                )
            }
            "getAvailableCalendars" -> {
                if (!hasCalendarPermissions()) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                calendarExecutor.execute {
                    try {
                        val calendars = queryWritableCalendars()
                        runOnUiThread { result.success(calendars) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("CALENDAR_QUERY_FAILED", e.message, null)
                        }
                    }
                }
            }
            "getCalendarEventColors" -> {
                if (!hasCalendarPermissions()) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                val calendarId = call.argument<Any>("calendarId")?.toString()?.toLongOrNull()
                if (calendarId == null) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                calendarExecutor.execute {
                    try {
                        val colors = queryCalendarEventColors(calendarId)
                        runOnUiThread { result.success(colors) }
                    } catch (_: Exception) {
                        runOnUiThread { result.success(emptyList<Map<String, Any?>>()) }
                    }
                }
            }
            "findExistingEvents" -> {
                if (!hasCalendarPermissions()) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                val calendarId = call.argument<Any>("calendarId")?.toString()?.toLongOrNull()
                val fromMillis = (call.argument<Number>("fromMillis"))?.toLong() ?: 0L
                val toMillis = (call.argument<Number>("toMillis"))?.toLong() ?: Long.MAX_VALUE
                if (calendarId == null) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                calendarExecutor.execute {
                    try {
                        val events = queryCalendarEvents(calendarId, fromMillis, toMillis)
                        runOnUiThread { result.success(events) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("CALENDAR_FIND_FAILED", e.message, null)
                        }
                    }
                }
            }
            "upsertEvent" -> {
                if (!hasCalendarPermissions()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "Nincs naptár hozzáférési engedély.",
                        null
                    )
                    return
                }
                val calendarId = call.argument<Any>("calendarId")?.toString()?.toLongOrNull()
                if (calendarId == null) {
                    result.error("INVALID_ARGS", "Hiányzó calendarId.", null)
                    return
                }
                val existingEventId = call.argument<Any>("eventId")?.toString()?.toLongOrNull()
                val title = call.argument<String>("title")?.trim() ?: ""
                val description = call.argument<String>("description")?.trim() ?: ""
                val startMillis = (call.argument<Number>("startMillis"))?.toLong()
                val endMillis = (call.argument<Number>("endMillis"))?.toLong()
                val reminderMinutes = (call.argument<Number>("reminderMinutes"))?.toInt() ?: 60
                val allDay = call.argument<Boolean>("allDay") ?: false
                val syncTag = call.argument<String>("syncTag")?.trim()?.takeIf { it.isNotEmpty() }
                val eventColor = (call.argument<Number>("eventColor"))?.toInt()
                val eventColorKey = call.argument<String>("eventColorKey")?.trim()?.takeIf { it.isNotEmpty() }
                if (title.isEmpty() || startMillis == null || endMillis == null) {
                    result.error("INVALID_ARGS", "Hiányzó esemény adatok.", null)
                    return
                }
                calendarExecutor.execute {
                    try {
                        val savedEventId = upsertCalendarEvent(
                            calendarId = calendarId,
                            existingEventId = existingEventId,
                            title = title,
                            description = description,
                            startMillis = startMillis,
                            endMillis = endMillis,
                            reminderMinutes = reminderMinutes,
                            allDay = allDay,
                            syncTag = syncTag,
                            eventColor = eventColor,
                            eventColorKey = eventColorKey
                        )
                        runOnUiThread { result.success(savedEventId) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("CALENDAR_UPSERT_FAILED", e.message, null)
                        }
                    }
                }
            }
            "deleteEvent" -> {
                if (!hasCalendarPermissions()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "Nincs naptár hozzáférési engedély.",
                        null
                    )
                    return
                }
                val eventId = call.argument<Any>("eventId")?.toString()?.toLongOrNull()
                if (eventId == null) {
                    result.success(false)
                    return
                }
                calendarExecutor.execute {
                    try {
                        val removed = deleteCalendarEvent(eventId)
                        runOnUiThread { result.success(removed) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("CALENDAR_DELETE_FAILED", e.message, null)
                        }
                    }
                }
            }
            "deleteEvents" -> {
                if (!hasCalendarPermissions()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "Nincs naptár hozzáférési engedély.",
                        null
                    )
                    return
                }
                val rawIds = call.argument<List<Any?>>("eventIds") ?: emptyList()
                val ids = rawIds.mapNotNull { it?.toString()?.toLongOrNull() }
                calendarExecutor.execute {
                    try {
                        var deletedCount = 0
                        for (id in ids) {
                            if (deleteCalendarEvent(id)) {
                                deletedCount++
                            }
                        }
                        runOnUiThread { result.success(deletedCount) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("CALENDAR_DELETE_FAILED", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun queryWritableCalendars(): List<Map<String, Any?>> {
        val hasPrimaryCol = Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1
        val projectionList = mutableListOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.OWNER_ACCOUNT,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.VISIBLE
        )
        if (hasPrimaryCol) {
            projectionList.add(CalendarContract.Calendars.IS_PRIMARY)
        }
        val selection =
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"
        val selectionArgs = arrayOf(
            CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()
        )
        val items = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projectionList.toTypedArray(),
            selection,
            selectionArgs,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accNameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
            val accTypeIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE)
            val ownerIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.OWNER_ACCOUNT)
            val colorIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_COLOR)
            val visibleIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.VISIBLE)
            val primaryIdx = if (hasPrimaryCol) {
                cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                val displayName = cursor.getString(nameIdx) ?: "Naptár ($id)"
                val accountName = cursor.getString(accNameIdx) ?: ""
                val accountType = cursor.getString(accTypeIdx) ?: ""
                val ownerAccount = cursor.getString(ownerIdx) ?: ""
                val color = cursor.getInt(colorIdx)
                val visible = cursor.getInt(visibleIdx) == 1
                val isGoogle = accountType == "com.google"
                val isPrimaryFlag = if (primaryIdx >= 0) cursor.getInt(primaryIdx) == 1 else false
                val isPrimary = isPrimaryFlag || (accountName.isNotEmpty() && ownerAccount == accountName)
                items.add(
                    mapOf(
                        "id" to id.toString(),
                        "displayName" to displayName,
                        "accountName" to accountName,
                        "accountType" to accountType,
                        "ownerAccount" to ownerAccount,
                        "isGoogle" to isGoogle,
                        "isPrimary" to isPrimary,
                        "color" to color,
                        "visible" to visible
                    )
                )
            }
        }
        items.sortWith(
            compareByDescending<Map<String, Any?>> { it["isGoogle"] == true }
                .thenByDescending { it["isPrimary"] == true }
                .thenByDescending { it["visible"] == true }
                .thenBy { (it["displayName"] as? String ?: "").lowercase() }
        )
        return items
    }

    private fun queryCalendarAccount(calendarId: Long): Pair<String, String>? {
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(
                CalendarContract.Calendars.ACCOUNT_NAME,
                CalendarContract.Calendars.ACCOUNT_TYPE
            ),
            "${CalendarContract.Calendars._ID} = ?",
            arrayOf(calendarId.toString()),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val accName = cursor.getString(0) ?: ""
                val accType = cursor.getString(1) ?: ""
                return accName to accType
            }
        }
        return null
    }

    private fun queryCalendarEventColors(calendarId: Long): List<Map<String, Any?>> {
        val account = queryCalendarAccount(calendarId) ?: return emptyList()
        val (accName, accType) = account
        if (accName.isEmpty() || accType.isEmpty()) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            CalendarContract.Colors.CONTENT_URI,
            arrayOf(
                CalendarContract.Colors.COLOR_KEY,
                CalendarContract.Colors.COLOR
            ),
            "${CalendarContract.Colors.ACCOUNT_NAME} = ? AND ${CalendarContract.Colors.ACCOUNT_TYPE} = ? AND ${CalendarContract.Colors.COLOR_TYPE} = ?",
            arrayOf(
                accName,
                accType,
                CalendarContract.Colors.TYPE_EVENT.toString()
            ),
            null
        )?.use { cursor ->
            val keyIdx = cursor.getColumnIndex(CalendarContract.Colors.COLOR_KEY)
            val colorIdx = cursor.getColumnIndex(CalendarContract.Colors.COLOR)
            if (keyIdx < 0 || colorIdx < 0) return emptyList()
            while (cursor.moveToNext()) {
                val colorKey = cursor.getString(keyIdx) ?: continue
                val color = cursor.getInt(colorIdx)
                results.add(
                    mapOf(
                        "colorKey" to colorKey,
                        "color" to color
                    )
                )
            }
        }
        return results
    }

    private fun resolveNearestEventColorKey(calendarId: Long, targetArgb: Int): String? {
        val colors = runCatching { queryCalendarEventColors(calendarId) }.getOrNull() ?: return null
        if (colors.isEmpty()) return null
        val tr = (targetArgb shr 16) and 0xFF
        val tg = (targetArgb shr 8) and 0xFF
        val tb = targetArgb and 0xFF
        var bestKey: String? = null
        var bestDist = Int.MAX_VALUE
        for (entry in colors) {
            val key = entry["colorKey"] as? String ?: continue
            val c = (entry["color"] as? Number)?.toInt() ?: continue
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            val dist = (r - tr) * (r - tr) + (g - tg) * (g - tg) + (b - tb) * (b - tb)
            if (dist < bestDist) {
                bestDist = dist
                bestKey = key
            }
        }
        return bestKey
    }

    private fun queryCalendarEvents(
        calendarId: Long,
        fromMillis: Long,
        toMillis: Long
    ): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.EVENT_COLOR,
            CalendarContract.Events.EVENT_COLOR_KEY
        )
        val selection =
            "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} != 1 AND ${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?"
        val selectionArgs = arrayOf(
            calendarId.toString(),
            fromMillis.toString(),
            toMillis.toString()
        )
        val items = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${CalendarContract.Events.DTSTART} ASC"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndex(CalendarContract.Events._ID)
            val titleIdx = cursor.getColumnIndex(CalendarContract.Events.TITLE)
            val descIdx = cursor.getColumnIndex(CalendarContract.Events.DESCRIPTION)
            val startIdx = cursor.getColumnIndex(CalendarContract.Events.DTSTART)
            val endIdx = cursor.getColumnIndex(CalendarContract.Events.DTEND)
            val colorIdx = cursor.getColumnIndex(CalendarContract.Events.EVENT_COLOR)
            val colorKeyIdx = cursor.getColumnIndex(CalendarContract.Events.EVENT_COLOR_KEY)
            while (cursor.moveToNext()) {
                val id = if (idIdx >= 0) cursor.getLong(idIdx) else continue
                items.add(
                    mapOf(
                        "eventId" to id.toString(),
                        "title" to (if (titleIdx >= 0) cursor.getString(titleIdx) ?: "" else ""),
                        "description" to (if (descIdx >= 0) cursor.getString(descIdx) ?: "" else ""),
                        "startMillis" to (if (startIdx >= 0) cursor.getLong(startIdx) else 0L),
                        "endMillis" to (if (endIdx >= 0) cursor.getLong(endIdx) else 0L),
                        "eventColor" to (if (colorIdx >= 0 && !cursor.isNull(colorIdx)) cursor.getInt(colorIdx) else null),
                        "eventColorKey" to (if (colorKeyIdx >= 0) cursor.getString(colorKeyIdx) else null)
                    )
                )
            }
        }
        return items
    }

    private fun findMatchingNativeEventId(
        calendarId: Long,
        title: String,
        startMillis: Long,
        endMillis: Long,
        syncTag: String?
    ): Long? {
        if (!syncTag.isNullOrBlank()) {
            contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                arrayOf(CalendarContract.Events._ID, CalendarContract.Events.DESCRIPTION),
                "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} != 1 AND ${CalendarContract.Events.DESCRIPTION} LIKE ?",
                arrayOf(calendarId.toString(), "%$syncTag%"),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getLong(0)
                }
            }
        }
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID),
            "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} != 1 AND ${CalendarContract.Events.TITLE} = ? AND ${CalendarContract.Events.DTSTART} = ? AND ${CalendarContract.Events.DTEND} = ?",
            arrayOf(calendarId.toString(), title, startMillis.toString(), endMillis.toString()),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }
        return null
    }

    private fun upsertCalendarEvent(
        calendarId: Long,
        existingEventId: Long?,
        title: String,
        description: String,
        startMillis: Long,
        endMillis: Long,
        reminderMinutes: Int,
        allDay: Boolean,
        syncTag: String? = null,
        eventColor: Int? = null,
        eventColorKey: String? = null
    ): String {
        val safeEndMillis = if (endMillis > startMillis) endMillis else startMillis + 60_000L
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.DTSTART, startMillis)
            put(CalendarContract.Events.DTEND, safeEndMillis)
            put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
            put(
                CalendarContract.Events.EVENT_TIMEZONE,
                if (allDay) "UTC" else TimeZone.getDefault().id
            )
            put(CalendarContract.Events.HAS_ALARM, if (reminderMinutes > 0) 1 else 0)
            put(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_BUSY)
            if (!eventColorKey.isNullOrBlank()) {
                put(CalendarContract.Events.EVENT_COLOR_KEY, eventColorKey)
            } else if (eventColor != null) {
                val matchedKey = resolveNearestEventColorKey(calendarId, eventColor)
                if (!matchedKey.isNullOrBlank()) {
                    put(CalendarContract.Events.EVENT_COLOR_KEY, matchedKey)
                } else {
                    put(CalendarContract.Events.EVENT_COLOR, eventColor)
                }
            }
        }

        val resolvedExistingId = existingEventId ?: findMatchingNativeEventId(
            calendarId = calendarId,
            title = title,
            startMillis = startMillis,
            endMillis = safeEndMillis,
            syncTag = syncTag
        )

        if (resolvedExistingId != null) {
            val updateUri = ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                resolvedExistingId
            )
            val updated = runCatching {
                contentResolver.update(
                    updateUri,
                    values,
                    "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} != 1",
                    arrayOf(calendarId.toString())
                )
            }.getOrElse {
                // Retry without color columns if provider rejects custom eventColor on this calendar
                values.remove(CalendarContract.Events.EVENT_COLOR)
                values.remove(CalendarContract.Events.EVENT_COLOR_KEY)
                contentResolver.update(
                    updateUri,
                    values,
                    "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} != 1",
                    arrayOf(calendarId.toString())
                )
            }
            if (updated > 0) {
                syncEventReminder(resolvedExistingId, reminderMinutes)
                return resolvedExistingId.toString()
            }
        }

        val insertedUri = runCatching {
            contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
        }.getOrElse {
            values.remove(CalendarContract.Events.EVENT_COLOR)
            values.remove(CalendarContract.Events.EVENT_COLOR_KEY)
            contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
        } ?: throw IllegalStateException("Nem sikerült létrehozni a naptár eseményt.")
        val newId = ContentUris.parseId(insertedUri)
        if (newId < 0) {
            throw IllegalStateException("Érvénytelen naptár esemény azonosító.")
        }
        syncEventReminder(newId, reminderMinutes)
        return newId.toString()
    }

    private fun syncEventReminder(eventId: Long, reminderMinutes: Int) {
        contentResolver.delete(
            CalendarContract.Reminders.CONTENT_URI,
            "${CalendarContract.Reminders.EVENT_ID} = ?",
            arrayOf(eventId.toString())
        )
        if (reminderMinutes > 0) {
            val reminderValues = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, reminderMinutes)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
        }
    }

    private fun deleteCalendarEvent(eventId: Long): Boolean {
        contentResolver.delete(
            CalendarContract.Reminders.CONTENT_URI,
            "${CalendarContract.Reminders.EVENT_ID} = ?",
            arrayOf(eventId.toString())
        )
        val deleteUri = ContentUris.withAppendedId(
            CalendarContract.Events.CONTENT_URI,
            eventId
        )
        val rows = contentResolver.delete(deleteUri, null, null)
        return rows > 0
    }
}
