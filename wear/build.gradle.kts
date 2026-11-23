import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

apply(from = "../shared/kreta_config_codegen.gradle.kts")

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "hu.mlnlbrt.tintanaplo.wear"
    compileSdk = 36

    sourceSets.getByName("main").java.srcDir(layout.buildDirectory.dir("generated/kreta/kotlin").get().asFile)

    defaultConfig {
        applicationId = "hu.mlnlbrt.tintanaplo"
        minSdk = 30
        targetSdk = 34
        versionCode = 7003
        versionName = "3.1"
        resourceConfigurations += listOf("hu", "en")
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (!storeFilePath.isNullOrBlank()) {
                val resolved = listOf(
                    file(storeFilePath),
                    rootProject.file("app/$storeFilePath"),
                    rootProject.file(storeFilePath),
                ).firstOrNull { it.exists() && it.isFile }
                if (resolved != null) {
                    storeFile = resolved
                }
            }
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            ndk {
                debugSymbolLevel = "NONE"
            }
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += listOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/*.kotlin_module",
                "META-INF/*.version",
                "META-INF/proguard/*",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/**/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/**/NOTICE*",
                "META-INF/com/android/build/gradle/*",
                "META-INF/version-control-info.textproto",
                "DebugProbesKt.bin",
                "kotlin/**",
                "**/*.kotlin_builtins",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.05.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

    // Core Wear OS & Remote Auth
    implementation("androidx.wear:wear-remote-interactions:1.2.0")

    // Wear OS Compose UI
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-foundation:1.5.0")
    implementation("androidx.wear.compose:compose-material:1.5.0")

    // Wear OS Tiles & ProtoLayout
    implementation("androidx.wear.tiles:tiles:1.6.2")
    implementation("androidx.wear.protolayout:protolayout:1.4.2")
    implementation("androidx.wear.protolayout:protolayout-material:1.4.2")

    // Background sync & secure token storage
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    // Coroutines & ListenableFuture bridges
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.1")
    implementation("com.google.guava:listenablefuture:1.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-tooling-preview")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.1")
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("Kotlin")) {
        dependsOn("generateKretaSharedConfig")
    }
    if (name == "assembleRelease" || name == "packageRelease") {
        doFirst {
            val releaseSigning = android.signingConfigs.getByName("release")
            val resolvedStore = releaseSigning.storeFile
            if (!keystorePropertiesFile.exists() || resolvedStore == null || !resolvedStore.exists()) {
                throw GradleException(
                    "Wear OS release signing keystore missing: check android/key.properties and android/app/tinta-release.jks."
                )
            }
        }
    }
}
