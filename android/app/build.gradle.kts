import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(property: String, environmentVariable: String): String? =
    signingProperties.getProperty(property)?.takeIf(String::isNotBlank)
        ?: System.getenv(environmentVariable)?.takeIf(String::isNotBlank)

val releaseStoreFile = signingValue("storeFile", "EREFILL_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "EREFILL_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "EREFILL_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "EREFILL_KEY_PASSWORD")
val releaseSigningConfigured = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Release signing is not configured. Set the EREFILL_* signing " +
                    "environment variables or add ignored android/key.properties.",
            )
        }
    }
}

tasks.matching {
    it.name == "preReleaseBuild" ||
        it.name == "assembleRelease" ||
        it.name == "bundleRelease"
}.configureEach {
    dependsOn(validateReleaseSigning)
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
            if (releaseSigningConfigured) {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
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
