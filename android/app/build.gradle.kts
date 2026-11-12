plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "hu.rekreta.rekreta_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "hu.rekreta.rekreta_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    applicationVariants.all {
        val variant = this
        val versionLabel = variant.versionName ?: "1.2.5"
        val customApkName = "reKRETA-v${versionLabel}.apk"
        variant.outputs
            .map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }
            .forEach { output ->
                if (variant.buildType.name == "release") {
                    output.outputFileName = customApkName
                }
            }
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
                                "hu.rekreta.rekreta_app/hu.rekreta.rekreta_app.MainActivityNormal"
                            )
                        )
                        .waitFor()
                } catch (_: Exception) {
                }

                if (variant.buildType.name == "release") {
                    val flutterApkDir = rootProject.projectDir.resolve("../build/app/outputs/flutter-apk")
                    flutterApkDir.mkdirs()
                    val releaseApkDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
                    val generatedApk = releaseApkDir.resolve(customApkName)
                    if (generatedApk.exists()) {
                        generatedApk.copyTo(flutterApkDir.resolve(customApkName), overwrite = true)
                    } else {
                        val fallbackFlutterApk = flutterApkDir.resolve("app-release.apk")
                        if (fallbackFlutterApk.exists()) {
                            fallbackFlutterApk.copyTo(flutterApkDir.resolve(customApkName), overwrite = true)
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
}
