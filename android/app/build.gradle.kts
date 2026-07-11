import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Load keystore credentials from key.properties (not committed to VCS) ────
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.propertypulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Desugaring — required by several Firebase / Google libs on API < 26
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.propertypulse"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Required for Firestore on older API levels
        multiDexEnabled = true
    }

    // ── Signing ──────────────────────────────────────────────────────────────
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias     = keystoreProperties["keyAlias"]     as String
                keyPassword  = keystoreProperties["keyPassword"]  as String
                storeFile    = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
            // Fallback: read from CI environment variables when key.properties
            // is absent (e.g. GitHub Actions / Bitrise).
            else {
                keyAlias     = System.getenv("KEY_ALIAS")      ?: ""
                keyPassword  = System.getenv("KEY_PASSWORD")   ?: ""
                storeFile    = file(System.getenv("KEYSTORE_PATH") ?: "keystore.jks")
                storePassword = System.getenv("STORE_PASSWORD") ?: ""
            }
        }
    }

    // ── Build types ──────────────────────────────────────────────────────────
    buildTypes {
        debug {
            // Same applicationId as release so `google-services.json` (package
            // `com.propertypulse`) matches. To use `com.propertypulse.debug`,
            // register that app in Firebase and add a second client in
            // google-services.json.
            versionNameSuffix   = "-debug"
            isDebuggable        = true
            isMinifyEnabled     = false
            isShrinkResources   = false
        }

        release {
            signingConfig     = signingConfigs.getByName("release")
            isDebuggable      = false
            isMinifyEnabled   = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // Upload Dart symbol files so Crashlytics can de-obfuscate stack traces
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                nativeSymbolUploadEnabled = true
                unstrippedNativeLibsDir  = "build/app/intermediates/merged_native_libs"
            }
        }
    }

    // NOTE: Do not enable `splits { abi { ... } }` here — it conflicts with NDK
    // `abiFilters` from the Flutter toolchain. Use Play App Bundle (below); Play
    // still serves per-ABI downloads. For side-loaded per-ABI APKs, configure
    // splits only together with `defaultConfig { ndk { abiFilters.clear() } }`
    // after consulting current AGP + Flutter docs.

    // ── AAB / APK packaging ──────────────────────────────────────────────────
    bundle {
        language { enableSplit = true  }
        density  { enableSplit = true  }
        abi      { enableSplit = true  }
    }

    // Suppress "duplicate file" errors from transitive deps
    packaging {
        resources.excludes += setOf(
            "META-INF/DEPENDENCIES",
            "META-INF/LICENSE",
            "META-INF/LICENSE.txt",
            "META-INF/NOTICE",
            "META-INF/NOTICE.txt",
            "META-INF/*.kotlin_module",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (java.time APIs on older Android)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
