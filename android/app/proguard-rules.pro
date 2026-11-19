# Tinta Naplo ProGuard / R8 keep rules
-keep class hu.mlnlbrt.tintanaplo.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class androidx.core.app.NotificationCompat$ProgressStyle** { *; }
-keep class android.app.Notification$ProgressStyle** { *; }
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends com.google.android.gms.wearable.WearableListenerService { *; }
-keep class org.json.** { *; }

-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-dontwarn com.google.android.play.core.**
-dontwarn android.app.Notification$ProgressStyle**
-dontwarn io.flutter.plugin.**
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
