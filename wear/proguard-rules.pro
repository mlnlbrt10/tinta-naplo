-keep class hu.mlnlbrt.tintanaplo.shared.** { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.data.** { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.MainActivity { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.tile.TintaTimetableTileService { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.auth.WearAuthListenerService { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncWorker { *; }
-keep class hu.mlnlbrt.tintanaplo.wear.sync.TileTransitionWorker { *; }

-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends androidx.work.CoroutineWorker { *; }
-keep class * extends androidx.wear.tiles.TileService { *; }
-keep class * extends com.google.android.gms.wearable.WearableListenerService { *; }

-keep class org.json.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
