import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mainlyb.chabaka"
    compileSdk = flutter.compileSdkVersion

    // NDK : version la plus haute exigée par les plugins (jni 28.2) ; r27c suffit
    // au cross-compile Rust (cargo-ndk), les versions sont rétrocompatibles.
    // Si flutter.ndkVersion (défini par le plugin Flutter) est suffisant, on
    // l'utilise ; sinon on peut le surcharger ici avec une version explicite.
    // Valeur épinglée pour reproductibilité CI (V2-FFI-Rust-spec.md §10 R1).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mainlyb.chabaka"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ABI filters : on aligne exactement sur les targets Rust compilées par
        // tools/build-rust/build_android.sh (V2-FFI-Rust-spec.md §4.3 Android).
        // x86 (32-bit) non supporté (obsolète, non ciblé).
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    // Signature release : clé d'upload Google Play.
    // Source 1 (CI) : variables d'environnement ANDROID_KEYSTORE_PATH,
    //   ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.
    // Source 2 (poste local) : android/key.properties (ignoré par git) avec
    //   storeFile=..., storePassword=..., keyAlias=..., keyPassword=...
    // Sans l'un ni l'autre, on retombe sur la clé debug pour que
    // `flutter run --release` reste possible (AAB non publiable).
    val keyProps = Properties()
    val keyPropsFile = rootProject.file("key.properties")
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { keyProps.load(it) }
    }
    val ksPath: String? =
        System.getenv("ANDROID_KEYSTORE_PATH") ?: keyProps.getProperty("storeFile")
    val hasUploadKey = ksPath != null && file(ksPath).exists()

    signingConfigs {
        if (hasUploadKey && ksPath != null) {
            create("upload") {
                storeFile = file(ksPath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: keyProps.getProperty("storePassword")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    ?: keyProps.getProperty("keyAlias")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                    ?: keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                println("AVERTISSEMENT : pas de clé d'upload, release signée en debug (non publiable).")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Les .so produits par cargo-ndk sont posés dans jniLibs/<ABI>/ par
    // tools/build-rust/build_android.sh. Gradle les packague automatiquement
    // dans l'APK/AAB via le mécanisme jniLibs standard — pas besoin de
    // sourceSets supplémentaires car android/app/src/main/jniLibs/ est le
    // chemin conventionnel déjà reconnu par AGP.
    // dart:ffi côté Dart charge la lib via DynamicLibrary.open("libchabaka_engine.so").
}

flutter {
    source = "../.."
}
