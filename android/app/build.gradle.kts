import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

apply(from = "../../shared/kreta_config_codegen.gradle.kts")

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "hu.mlnlbrt.tintanaplo"
    sourceSets.getByName("main").java.srcDir(layout.buildDirectory.dir("generated/kreta/kotlin").get().asFile)
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "hu.mlnlbrt.tintanaplo"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "DebugProbesKt.bin",
            )
        }
    }

    applicationVariants.all {
        val variant = this
        val versionLabel = variant.versionName ?: "2.0.2"
        val customApkName = "tinta-naplo-v${versionLabel}.apk"
        val arm64CustomApkName = "tinta-naplo-v${versionLabel}-arm64-v8a.apk"
        variant.assembleProvider.configure {
            doLast {
                try {
                    Runtime.getRuntime()
                        .exec(
                            arrayOf(
                                "adb",
                                "shell",
                                "pm",
                                "enable",
                                "hu.mlnlbrt.tintanaplo/hu.mlnlbrt.tintanaplo.MainActivityNormal"
                            )
                        )
                        .waitFor()
                } catch (_: Exception) {
                }

                if (variant.buildType.name == "release") {
                    val flutterApkDir = rootProject.projectDir.resolve("../build/app/outputs/flutter-apk")
                    flutterApkDir.mkdirs()
                    val releaseApkDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
                    val sourceApk = listOf(
                        flutterApkDir.resolve("app-arm64-v8a-release.apk"),
                        releaseApkDir.resolve("app-arm64-v8a-release.apk"),
                        flutterApkDir.resolve("app-release.apk"),
                        releaseApkDir.resolve("app-release.apk"),
                    ).firstOrNull { it.exists() }
                    if (sourceApk != null) {
                        sourceApk.copyTo(flutterApkDir.resolve(arm64CustomApkName), overwrite = true)
                        sourceApk.copyTo(flutterApkDir.resolve(customApkName), overwrite = true)
                    }
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("Kotlin")) {
        dependsOn("generateKretaSharedConfig")
    }
}
