import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing config from key.properties (written in CI/local with your keystore secrets)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val admobAppIdAndroid = (project.findProperty("ADMOB_APP_ID_ANDROID") as String?)?.trim()
val admobBannerUnitAndroid = (project.findProperty("ADMOB_BANNER_UNIT_ANDROID") as String?)?.trim()
// Determine ADS_ENABLED from project property (set via ORG_GRADLE_PROJECT_ADS_ENABLED in CI).
// If the property is not provided, default to true for release builds (ads enabled).
val adsEnabled: Boolean = if (project.hasProperty("ADS_ENABLED")) {
    val adsEnabledProp = (project.findProperty("ADS_ENABLED") as String?)?.trim()?.lowercase()
    when (adsEnabledProp) {
        "true", "1", "yes" -> true
        "false", "0", "no" -> false
        else -> true
    }
} else {
    true
}

android {
    namespace = "com.xdcobra.fluttida"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.xdcobra.fluttida"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = rootProject.file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
            buildConfigField("boolean", "ADS_ENABLED", "false")
            buildConfigField(
                "String",
                "ADMOB_BANNER_UNIT_ANDROID",
                "\"ca-app-pub-3940256099942544/6300978111\""
            )
        }
        getByName("profile") {
            initWith(getByName("debug"))
        }
        getByName("release") {
            val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

            // Only require ADMOB secrets when ads are enabled for the build.
            if (isReleaseTask && adsEnabled) {
                if (admobAppIdAndroid.isNullOrBlank()) {
                    throw GradleException("ADMOB_APP_ID_ANDROID is required for release builds when ADS_ENABLED=true")
                }
                if (admobBannerUnitAndroid.isNullOrBlank()) {
                    throw GradleException("ADMOB_BANNER_UNIT_ANDROID is required for release builds when ADS_ENABLED=true")
                }
            }

            // Use provided IDs when ads are enabled, otherwise fall back to test IDs.
            val testAppId = "ca-app-pub-3940256099942544~3347511713"
            val testBanner = "ca-app-pub-3940256099942544/6300978111"

            manifestPlaceholders["admobAppId"] = if (adsEnabled) {
                admobAppIdAndroid ?: testAppId
            } else {
                testAppId
            }
            buildConfigField("boolean", "ADS_ENABLED", if (adsEnabled) "true" else "false")
            buildConfigField(
                "String",
                "ADMOB_BANNER_UNIT_ANDROID",
                "\"${if (adsEnabled) (admobBannerUnitAndroid ?: testBanner) else testBanner}\""
            )

            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback to debug signing so local `flutter run --release` still works without a keystore
                signingConfigs.getByName("debug")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Ensure native code is built and R8 keeps JNI symbols
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.10.0")
}

// Cronet runtime dependency (embedded). Update version as needed for your project.
dependencies {
    implementation("org.chromium.net:cronet-embedded:141.7340.3")
}
