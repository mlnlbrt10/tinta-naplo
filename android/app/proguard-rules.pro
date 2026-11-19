# Tinta Naplo ProGuard / R8 keep rules
-keep class hu.mlnlbrt.tintanaplo.** { *; }
-keep class io.flutter.** { *; }
-keep class androidx.core.app.NotificationCompat$ProgressStyle** { *; }
-keep class android.app.Notification$ProgressStyle** { *; }
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends com.google.android.gms.wearable.WearableListenerService { *; }
