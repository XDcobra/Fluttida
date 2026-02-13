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
            buildConfigField("boolean", "ADS_ENABLED", "true")
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
            if (isReleaseTask && admobAppIdAndroid.isNullOrBlank()) {
                throw GradleException("ADMOB_APP_ID_ANDROID is required for release builds")
            }
            if (isReleaseTask && admobBannerUnitAndroid.isNullOrBlank()) {
                throw GradleException("ADMOB_BANNER_UNIT_ANDROID is required for release builds")
            }

            manifestPlaceholders["admobAppId"] = admobAppIdAndroid
                ?: "ca-app-pub-3940256099942544~3347511713"
            buildConfigField("boolean", "ADS_ENABLED", "true")
            buildConfigField(
                "String",
                "ADMOB_BANNER_UNIT_ANDROID",
                "\"${admobBannerUnitAndroid ?: "ca-app-pub-3940256099942544/6300978111"}\""
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
