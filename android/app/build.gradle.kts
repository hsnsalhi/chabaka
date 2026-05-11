plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mainlyb.chabaka"
    compileSdk = flutter.compileSdkVersion

    // NDK r27c minimum requis pour le cross-compile Rust (cargo-ndk).
    // Si flutter.ndkVersion (défini par le plugin Flutter) est suffisant, on
    // l'utilise ; sinon on peut le surcharger ici avec une version explicite.
    // Valeur épinglée pour reproductibilité CI (V2-FFI-Rust-spec.md §10 R1).
    ndkVersion = "27.2.12479018"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
