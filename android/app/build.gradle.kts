plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.io.File
import java.util.Properties

fun guessKeyStoreType(file: File): String {
    return try {
        FileInputStream(file).use { input ->
            val header = ByteArray(4)
            val read = input.read(header)
            if (
                read == 4 &&
                    header[0] == 0xFE.toByte() &&
                    header[1] == 0xED.toByte() &&
                    header[2] == 0xFE.toByte() &&
                    header[3] == 0xED.toByte()
            ) {
                "JKS"
            } else {
                "PKCS12"
            }
        }
    } catch (_: Exception) {
        "JKS"
    }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystoreProperties = keystorePropertiesFile.exists()

if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.tianyanmczj.vault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tianyanmczj.vault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystoreProperties) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                val store = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storeFile = store
                storePassword = keystoreProperties.getProperty("storePassword")
                storeType = keystoreProperties.getProperty("storeType") ?: guessKeyStoreType(store)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
