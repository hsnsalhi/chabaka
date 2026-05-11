#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tools/build-rust/build_android.sh
# Cross-compile chabaka_engine pour Android via cargo-ndk.
# Produit libchabaka_engine.so pour arm64-v8a, armeabi-v7a, x86_64.
#
# Usage :
#   ./tools/build-rust/build_android.sh [--debug] [--abi arm64-v8a,armeabi-v7a,x86_64]
#
# Pré-requis (à installer une seule fois) :
#   1. rustup + toolchain stable  → https://rustup.rs
#      rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#
#   2. cargo-ndk
#      cargo install cargo-ndk
#
#   3. Android NDK r25c ou supérieur via sdkmanager :
#      sdkmanager "ndk;27.2.12479018"
#      (ou toute autre version ≥ r25 ; la variable ANDROID_NDK_HOME doit pointer dessus)
#
# Output :
#   android/app/src/main/jniLibs/arm64-v8a/libchabaka_engine.so
#   android/app/src/main/jniLibs/armeabi-v7a/libchabaka_engine.so
#   android/app/src/main/jniLibs/x86_64/libchabaka_engine.so
#
# La présence de ces fichiers dans jniLibs/ suffit pour que Flutter/Gradle
# les packague dans l'APK/AAB — aucune configuration Gradle supplémentaire
# n'est nécessaire pour le chargement via dart:ffi DynamicLibrary.open().
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CRATE_DIR="${REPO_ROOT}/rust/chabaka_engine"
JNILIBS_DIR="${REPO_ROOT}/android/app/src/main/jniLibs"

# --- couleurs terminal -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[build_android]${NC} $*"; }
warn()    { echo -e "${YELLOW}[build_android]${NC} $*"; }
die()     { echo -e "${RED}[build_android] ERROR${NC} $*" >&2; exit 1; }
step()    { echo -e "${CYAN}[build_android]${NC} ── $*"; }

# --- options -----------------------------------------------------------------
BUILD_MODE="release"
ABIS="arm64-v8a armeabi-v7a x86_64"

for arg in "$@"; do
    case $arg in
        --debug)
            BUILD_MODE="debug"
            ;;
        --abi)
            shift
            ABIS="${1//,/ }"
            ;;
    esac
done

# Mapping ABI Android → target Rust
abi_to_rust_target() {
    case "$1" in
        arm64-v8a)   echo "aarch64-linux-android" ;;
        armeabi-v7a) echo "armv7-linux-androideabi" ;;
        x86_64)      echo "x86_64-linux-android" ;;
        *)           die "ABI inconnue : $1" ;;
    esac
}

# --- vérifications pré-requis ------------------------------------------------
step "Vérification des pré-requis..."

command -v cargo >/dev/null 2>&1 || die "cargo introuvable. Installer rustup : https://rustup.rs"
command -v rustup >/dev/null 2>&1 || die "rustup introuvable."
command -v cargo-ndk >/dev/null 2>&1 || die "cargo-ndk introuvable. Lancer : cargo install cargo-ndk"

# Résoudre le chemin NDK
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    # Tenter de déduire depuis ANDROID_HOME / SDK standard macOS
    ANDROID_SDK_ROOT="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
    if [ -d "${ANDROID_SDK_ROOT}/ndk" ]; then
        # Prendre la version NDK la plus récente installée
        NDK_VER=$(ls -1 "${ANDROID_SDK_ROOT}/ndk" | sort -V | tail -1)
        if [ -n "${NDK_VER}" ]; then
            ANDROID_NDK_HOME="${ANDROID_SDK_ROOT}/ndk/${NDK_VER}"
            warn "ANDROID_NDK_HOME non défini — utilisation de ${ANDROID_NDK_HOME}"
        fi
    fi
fi

[ -n "${ANDROID_NDK_HOME:-}" ] || die "NDK introuvable. Exporter ANDROID_NDK_HOME ou installer via : sdkmanager \"ndk;27.2.12479018\""
[ -d "${ANDROID_NDK_HOME}" ]   || die "ANDROID_NDK_HOME=${ANDROID_NDK_HOME} n'existe pas."

export ANDROID_NDK_HOME
info "NDK : ${ANDROID_NDK_HOME}"

# Vérifier / installer les targets Rust requises
check_rust_target() {
    local target="$1"
    if ! rustup target list --installed | grep -q "^${target}$"; then
        warn "Target Rust ${target} non installée. Installation..."
        rustup target add "${target}"
    fi
}

info "Vérification des targets Rust..."
for abi in ${ABIS}; do
    check_rust_target "$(abi_to_rust_target "${abi}")"
done

# --- build -------------------------------------------------------------------
cd "${CRATE_DIR}"

info "Build mode : ${BUILD_MODE}"
info "ABIs cibles : ${ABIS}"
echo ""

CARGO_NDK_ARGS=(--target-dir "$(pwd)/target")
if [ "${BUILD_MODE}" = "release" ]; then
    CARGO_NDK_ARGS+=(--release)
fi

# Construire la liste des flags --target pour cargo-ndk
NDK_TARGET_FLAGS=()
for abi in ${ABIS}; do
    NDK_TARGET_FLAGS+=(--target "$(abi_to_rust_target "${abi}")")
done

step "cargo-ndk build (${BUILD_MODE})..."
cargo ndk \
    "${NDK_TARGET_FLAGS[@]}" \
    "${CARGO_NDK_ARGS[@]}" \
    build 2>&1

# --- copie vers jniLibs ------------------------------------------------------
step "Copie des .so vers android/app/src/main/jniLibs/..."

# ABI → répertoire .so dans l'arbre cargo
so_path_for_abi() {
    local abi="$1"
    local target
    target="$(abi_to_rust_target "${abi}")"
    echo "${CRATE_DIR}/target/${target}/${BUILD_MODE}/libchabaka_engine.so"
}

for abi in ${ABIS}; do
    SO_SRC="$(so_path_for_abi "${abi}")"
    SO_DST_DIR="${JNILIBS_DIR}/${abi}"
    SO_DST="${SO_DST_DIR}/libchabaka_engine.so"

    [ -f "${SO_SRC}" ] || die ".so manquant pour ${abi} : ${SO_SRC}"

    mkdir -p "${SO_DST_DIR}"
    cp "${SO_SRC}" "${SO_DST}"

    SIZE=$(du -sh "${SO_DST}" | cut -f1)
    info "  ${abi}: ${SO_DST} (${SIZE})"
done

# --- résumé ------------------------------------------------------------------
echo ""
info "Terminé. Fichiers produits dans jniLibs/ :"
for abi in ${ABIS}; do
    SO="${JNILIBS_DIR}/${abi}/libchabaka_engine.so"
    if [ -f "${SO}" ]; then
        SIZE=$(ls -lh "${SO}" | awk '{print $5}')
        echo "  ${abi}  →  ${SIZE}"
    fi
done

echo ""
info "Validation APK : flutter build apk --debug puis :"
info "  unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libchabaka_engine"
info ""
info "Prochain : flutter build apk --debug"
