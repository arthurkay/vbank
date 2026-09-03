import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, in order of preference (see DEPLOYMENT.md):
//  1. CI environment — the variables Codemagic's `android_signing` injects and
//     that .github/workflows/release.yml exports after decoding the secret:
//       CM_KEYSTORE_PATH, CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS, CM_KEY_PASSWORD
//  2. Local — android/key.properties (git-ignored):
//       storeFile=/absolute/path/to/vbank-release.jks
//       storePassword=...  keyAlias=vbank  keyPassword=...
//  3. Neither — the DEBUG key, so `flutter run --release` still works locally.
//     Never distribute such a build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val ciKeystorePath: String? = System.getenv("CM_KEYSTORE_PATH")
val hasCiKeystore = ciKeystorePath != null && file(ciKeystorePath).exists()
val hasReleaseKeystore = hasCiKeystore || keystorePropertiesFile.exists()

android {
    namespace = "zm.co.tickethost.vbank"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "zm.co.tickethost.vbank"
        // minSdk >= 21 has native multidex; no multiDexEnabled needed.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                if (hasCiKeystore) {
                    storeFile = file(ciKeystorePath!!)
                    storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("CM_KEY_ALIAS")
                    keyPassword = System.getenv("CM_KEY_PASSWORD")
                } else {
                    storeFile = file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No key.properties present: fall back to the debug key so local
                // `flutter run --release` still works. NEVER ship this build —
                // the debug key is public. Create android/key.properties first.
                logger.warn(
                    "WARNING: no release keystore (CM_KEYSTORE_PATH or android/key.properties) — release build is " +
                        "signed with the DEBUG keystore and must not be distributed."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
