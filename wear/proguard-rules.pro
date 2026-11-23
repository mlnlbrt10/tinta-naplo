# Tinta Naplo Wear OS ProGuard / R8 keep rules
-allowaccessmodification
-repackageclasses 'w'

# App entry points, TileService, WearableListenerService & WorkManager workers
-keep class hu.mlnlbrt.tintanaplo.wear.MainActivity { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.tile.TintaTimetableTileService { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.auth.WearAuthListenerService { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class hu.mlnlbrt.tintanaplo.wear.sync.TileTransitionWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# WorkManager, Wear Tiles & Wearable DataLayer listeners
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
-keep class * extends androidx.wear.tiles.TileService { *; }
-keep class * extends com.google.android.gms.wearable.WearableListenerService { *; }

# Kotlin coroutines & conditional kotlinx.serialization
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-keepclassmembers class kotlin.coroutines.SafeContinuation {
    volatile <fields>;
}
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> { *; }

# JSON & annotations
-keep class org.json.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,RuntimeVisibleTypeAnnotations
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn kotlinx.serialization.**
