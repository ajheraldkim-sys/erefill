plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.erefill.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.erefill.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = "erefill"
            keyPassword = "erefill123"
            storeFile = file("erefill_keystore.jks")
            storePassword = "erefill123"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            (this as? com.android.build.gradle.internal.api.BaseVariantOutputImpl)?.let { output ->
                if (variant.buildType.name == "release") {
                    output.outputFileName = "eRefill.apk"
                }
            }
        }
    }
}

tasks.matching { it.name.contains("assembleRelease", ignoreCase = true) }.configureEach {
    doLast {
        val flutterApkDir = file("${project.layout.buildDirectory.get()}/outputs/flutter-apk")
        val appRelease = file("$flutterApkDir/app-release.apk")
        val eRefill = file("$flutterApkDir/eRefill.apk")
        if (appRelease.exists()) {
            appRelease.copyTo(eRefill, overwrite = true)
        }
        val apkReleaseDir = file("${project.layout.buildDirectory.get()}/outputs/apk/release")
        val apkFile = file("$apkReleaseDir/eRefill.apk")
        if (apkFile.exists() && !eRefill.exists()) {
            apkFile.copyTo(eRefill, overwrite = true)
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
