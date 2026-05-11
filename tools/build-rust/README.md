# Build Rust — chabaka_engine

## Pré-requis (à faire une seule fois)

### 1. Installer rustup

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
```

### 2. Installer les targets iOS

```bash
rustup target add aarch64-apple-ios        # device (M-series et Intel)
rustup target add aarch64-apple-ios-sim    # simulator M-series
rustup target add x86_64-apple-ios         # simulator Intel (optionnel, CI legacy)
```

Le fichier `rust/chabaka_engine/rust-toolchain.toml` épingle la toolchain
`stable` et liste toutes les targets pour `rustup` — elles seront installées
automatiquement à la première invocation de `cargo` dans le répertoire.

### 3. Xcode Command Line Tools

```bash
xcode-select --install
```

### 4. (Optionnel — macOS host tests Dart)

```bash
rustup target add aarch64-apple-darwin
```

## Build iOS

```bash
cd /path/to/chabaka
./tools/build-rust/build_ios.sh
```

Le script :
1. Cross-compile `aarch64-apple-ios` (device) et `aarch64-apple-ios-sim` (simulator M).
2. Si x86_64 disponible, crée une fat lib simulator via `lipo`.
3. Invoque `xcodebuild -create-xcframework`.
4. Dépose le résultat dans `ios/Frameworks/chabaka_engine.xcframework`.

Ignorer `x86_64` (CI Linux / Mac M-series) :

```bash
./tools/build-rust/build_ios.sh --skip-sim-x86
```

## Intégration Xcode

Le xcframework est référencé dans le Podfile via `post_install` (voir
`ios/Podfile`). Il sera automatiquement lié au target Runner en
"Embed & Sign" lors du prochain `pod install`.

Si on préfère ajouter manuellement dans Xcode :
- Glisser `ios/Frameworks/chabaka_engine.xcframework` dans le projet.
- Dans le target Runner > General > "Frameworks, Libraries, and Embedded
  Content" : passer en **Embed & Sign**.

## Build Android

### Pré-requis Android supplémentaires

#### 1. Targets Rust Android

```bash
rustup target add aarch64-linux-android    # arm64-v8a — devices modernes
rustup target add armv7-linux-androideabi  # armeabi-v7a — fallback 32-bit
rustup target add x86_64-linux-android    # x86_64 — émulateurs x86
```

#### 2. cargo-ndk

```bash
cargo install cargo-ndk
```

#### 3. Android NDK r27c (ou supérieur)

Via Android Studio SDK Manager ou en ligne de commande :

```bash
# $ANDROID_HOME doit pointer vers ~/Library/Android/sdk (ou votre SDK root)
sdkmanager "ndk;27.2.12479018"
```

Le NDK r27c est la version minimale requise pour `cargo-ndk` avec les targets
Android modernes. La version est épinglée dans `android/app/build.gradle.kts`
(`ndkVersion = "27.2.12479018"`) pour la reproductibilité CI.

### Lancer le build Android

```bash
cd /path/to/chabaka
./tools/build-rust/build_android.sh
```

Le script :
1. Vérifie `cargo`, `rustup`, `cargo-ndk` et `ANDROID_NDK_HOME`.
2. Auto-installe les targets Rust manquantes via `rustup target add`.
3. Lance `cargo ndk build --release` pour les 3 ABI.
4. Copie les `.so` dans `android/app/src/main/jniLibs/<ABI>/libchabaka_engine.so`.

Options disponibles :

```bash
# Build debug (plus rapide, non optimisé)
./tools/build-rust/build_android.sh --debug

# Ne compiler que certains ABI
./tools/build-rust/build_android.sh --abi arm64-v8a,x86_64
```

### Valider l'intégration APK

Après le build Rust puis `flutter build apk --debug` :

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libchabaka_engine
# Doit afficher les 3 entrées :
#   lib/arm64-v8a/libchabaka_engine.so
#   lib/armeabi-v7a/libchabaka_engine.so
#   lib/x86_64/libchabaka_engine.so
```

### Intégration Gradle

`android/app/build.gradle.kts` déclare :
- `ndkVersion = "27.2.12479018"` — version NDK épinglée.
- `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }` — filtre
  les ABIs packagées dans l'APK/AAB (élimine x86 32-bit obsolète).

Les `.so` dans `jniLibs/<ABI>/` sont packagés automatiquement par AGP sans
configuration sourceSets additionnelle. `dart:ffi` côté Dart charge la lib via :
```dart
DynamicLibrary.open("libchabaka_engine.so")
```
Flutter Android résout automatiquement le `.so` depuis le répertoire `lib/<ABI>/`
de l'APK au runtime.

## Note sur rusqlite / bundled

Quand le puzzle agent implémentera la vraie KB, il ajoutera dans Cargo.toml :

```toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
```

La feature `bundled` compile l'amalgamation SQLite directement dans la lib Rust,
évitant de dépendre de la `libsqlite3.dylib` du device (spécificités de version
iOS/Android variables). Cela augmente la taille de ~800 KB par slice ; reste
dans le budget 3 MB delta spec §9 avec LTO.
