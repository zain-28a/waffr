import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    // Kotlin comes from AGP built-in support; do not apply org.jetbrains.kotlin.android.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key. android/key.properties and the .jks file stay out of
// git (see .gitignore); locally you copy them in, on GitHub Actions they are
// written from repository secrets. Without them release builds fall back to
// the debug key so `flutter run --release` still works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.waffr.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent store identity of the app; never change it after publishing.
        applicationId = "com.waffr.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug",
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

tasks.configureEach {
    if (name != "assembleRelease") return@configureEach
    doLast {
        val named = "Waffr-${flutter.versionName}.apk"
        val outputs = layout.buildDirectory.get().asFile
        val releaseApk = outputs.resolve("outputs/apk/release/app-release.apk")
        val flutterDir = outputs.resolve("outputs/flutter-apk")
        val flutterApk = flutterDir.resolve("app-release.apk")

        fun copyNamed(source: File) {
            if (!source.exists()) return
            source.copyTo(File(source.parentFile, named), overwrite = true)
        }

        copyNamed(releaseApk)
        copyNamed(flutterApk)

        if (releaseApk.exists()) {
            flutterDir.mkdirs()
            releaseApk.copyTo(flutterDir.resolve(named), overwrite = true)
        }
    }
}
