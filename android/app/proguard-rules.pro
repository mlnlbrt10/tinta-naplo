# Tinta Naplo ProGuard / R8 keep rules
-allowaccessmodification
-repackageclasses 'o'

# App Android entry points (activities, widgets, receivers, services, workers)
-keep class hu.mlnlbrt.tintanaplo.MainActivity { *; }
-keep class hu.mlnlbrt.tintanaplo.PhoneWearAuthListenerService { *; }
-keep class hu.mlnlbrt.tintanaplo.KretaSyncWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class * extends android.content.BroadcastReceiver { *; }

# Flutter engine, embedding, JNI bindings & plugin registrant
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.engine.FlutterOverlaySurface { *; }
-keep class io.flutter.embedding.engine.mutatorsstack.FlutterMutatorsStack { *; }
-keep class io.flutter.embedding.engine.renderer.SurfaceTextureWrapper { *; }
-keep class io.flutter.view.FlutterCallbackInformation { *; }
-keep class io.flutter.view.TextureRegistry$ImageConsumer { *; }
-keep interface io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keepclassmembers class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
}
-keepclassmembers class io.flutter.embedding.engine.plugins.FlutterPlugin$FlutterPluginBinding {
    public java.lang.String getEngineId();
}

# Reflection-based & platform plugins
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class org.chromium.support_lib_boundary.* { public *; }

# WorkManager workers & parameters
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends androidx.work.CoroutineWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class androidx.work.WorkerParameters

# Wearable DataClient / MessageClient listener services
-keep class * extends com.google.android.gms.wearable.WearableListenerService { *; }

# Kotlin coroutines, JNI interop & conditional kotlinx.serialization support
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-keepclassmembers class kotlin.coroutines.SafeContinuation {
    volatile <fields>;
}
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> { *; }

# Android 16 / Samsung Now Bar ProgressStyle & Live Updates
-keep class androidx.core.app.NotificationCompat$ProgressStyle** { *; }
-keep class android.app.Notification$ProgressStyle** { *; }

# JSON & WebView JS bridge
-keep class org.json.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,RuntimeVisibleTypeAnnotations
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
-dontwarn kotlinx.serialization.**

# Room es WorkManager
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Dao class *
-dontwarn androidx.room.paging.**
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.CoroutineWorker

# Room es WorkManager
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Dao class *
-dontwarn androidx.room.paging.**
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.CoroutineWorker
