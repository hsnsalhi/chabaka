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
