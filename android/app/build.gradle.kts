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

fun resolveReleaseStoreFile(rawPath: String?): File? {
    if (rawPath.isNullOrBlank()) return null
    return listOf(
        file(rawPath),
        rootProject.file("app/$rawPath"),
        rootProject.file(rawPath),
    ).firstOrNull { it.exists() && it.isFile }
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
        val cleanVersionName = flutter.versionName.let { raw ->
            val parts = raw.split(".")
            if (parts.size == 3 && parts[2] == "0") "${parts[0]}.${parts[1]}" else raw
        }
        versionCode = flutter.versionCode
        versionName = cleanVersionName
        resourceConfigurations += listOf("hu", "en")
        val targetPlatforms = (project.findProperty("target-platform") as? String)
            ?.split(",")
            ?.map { it.trim() }
            ?: emptyList()
        val isSplitPerAbi = (project.findProperty("split-per-abi") as? String)?.toBoolean() == true
        if (!isSplitPerAbi && targetPlatforms == listOf("android-arm64")) {
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            val resolvedStoreFile = resolveReleaseStoreFile(keystoreProperties.getProperty("storeFile"))
            if (resolvedStoreFile != null) {
                storeFile = resolvedStoreFile
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
            ndk {
                debugSymbolLevel = "NONE"
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
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

    applicationVariants.all {
        val variant = this
        val versionLabel = variant.versionName ?: "3.1"
        val customApkName = "tinta-naplo-v${versionLabel}.apk"
        val androidCustomApkName = "tinta-naplo-android-v${versionLabel}.apk"
        val androidArm64CustomApkName = "tinta-naplo-android-v${versionLabel}-arm64-v8a.apk"
        val arm64CustomApkName = "tinta-naplo-v${versionLabel}-arm64-v8a.apk"
        variant.assembleProvider.configure {
            doFirst {
                if (variant.buildType.name == "release") {
                    val releaseSigning = signingConfigs.getByName("release")
                    val resolvedStore = releaseSigning.storeFile
                    if (!keystorePropertiesFile.exists() || resolvedStore == null || !resolvedStore.exists()) {
                        throw GradleException(
                            "Release signing keystore missing: check android/key.properties and android/app/tinta-release.jks."
                        )
                    }
                    if (releaseSigning.storePassword.isNullOrBlank() ||
                        releaseSigning.keyAlias.isNullOrBlank() ||
                        releaseSigning.keyPassword.isNullOrBlank()
                    ) {
                        throw GradleException("Release signing credentials incomplete in android/key.properties.")
                    }
                }
            }
            doLast {
                if (variant.buildType.name == "release") {
                    val flutterApkDir = rootProject.projectDir.resolve("../build/app/outputs/flutter-apk")
                    flutterApkDir.mkdirs()
                    val producedApks = variant.outputs
                        .map { it.outputFile }
                        .filter { it.exists() && it.extension == "apk" }
                    for (apk in producedApks) {
                        when {
                            apk.name.contains("arm64-v8a") -> {
                                apk.copyTo(flutterApkDir.resolve(androidArm64CustomApkName), overwrite = true)
                                apk.copyTo(flutterApkDir.resolve(arm64CustomApkName), overwrite = true)
                            }
                            apk.name == "app-release.apk" -> {
                                apk.copyTo(flutterApkDir.resolve(androidCustomApkName), overwrite = true)
                                apk.copyTo(flutterApkDir.resolve(customApkName), overwrite = true)
                            }
                        }
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
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("Kotlin")) {
        dependsOn("generateKretaSharedConfig")
    }
}
