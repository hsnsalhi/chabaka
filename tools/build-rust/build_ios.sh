#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tools/build-rust/build_ios.sh
# Cross-compile chabaka_engine pour iOS et produit le xcframework.
#
# Usage :
#   ./tools/build-rust/build_ios.sh [--skip-sim-x86]
#
# Pré-requis (voir README dans ce répertoire) :
#   - rustup + toolchain stable (rust-toolchain.toml épingle la version)
#   - Targets installées :
#       rustup target add aarch64-apple-ios
#       rustup target add aarch64-apple-ios-sim
#       rustup target add x86_64-apple-ios     (optionnel, Intel simulators)
#   - Xcode Command Line Tools : xcode-select --install
#
# Output : ios/Frameworks/chabaka_engine.xcframework
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CRATE_DIR="${REPO_ROOT}/rust/chabaka_engine"
OUT_FRAMEWORKS="${REPO_ROOT}/ios/Frameworks"

# --- options ----------------------------------------------------------------
SKIP_X86_SIM=false
for arg in "$@"; do
    case $arg in
        --skip-sim-x86) SKIP_X86_SIM=true ;;
    esac
done

# --- couleurs terminal -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[build_ios]${NC} $*"; }
warn()    { echo -e "${YELLOW}[build_ios]${NC} $*"; }
die()     { echo -e "${RED}[build_ios] ERROR${NC} $*" >&2; exit 1; }

# --- vérifications pré-requis -----------------------------------------------
command -v cargo   >/dev/null 2>&1 || die "cargo introuvable. Installer rustup : https://rustup.rs"
command -v rustup  >/dev/null 2>&1 || die "rustup introuvable."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild introuvable. Installer Xcode Command Line Tools."
command -v xcrun   >/dev/null 2>&1 || die "xcrun introuvable."

# Vérifie les targets nécessaires
check_target() {
    local target="$1"
    if ! rustup target list --installed | grep -q "^${target}$"; then
        warn "Target ${target} non installée. Installation..."
        rustup target add "${target}"
    fi
}

check_target aarch64-apple-ios
check_target aarch64-apple-ios-sim
if [ "${SKIP_X86_SIM}" = false ]; then
    check_target x86_64-apple-ios
fi

# --- build ------------------------------------------------------------------
cd "${CRATE_DIR}"

info "Compilation aarch64-apple-ios (device)..."
cargo build --release --target aarch64-apple-ios

info "Compilation aarch64-apple-ios-sim (simulator M-series)..."
cargo build --release --target aarch64-apple-ios-sim

DEVICE_LIB="${CRATE_DIR}/target/aarch64-apple-ios/release/libchabaka_engine.a"
SIM_ARM_LIB="${CRATE_DIR}/target/aarch64-apple-ios-sim/release/libchabaka_engine.a"

# Tailles
info "Tailles binaires :"
ls -lh "${DEVICE_LIB}"
ls -lh "${SIM_ARM_LIB}"

# --- slice simulator : fat lib si x86_64 demandé ----------------------------
# Sur M-series : Xcode accepte un xcframework avec slice sim arm64 seul.
# Pour supporter Intel simulators (legacy CI), on crée une fat lib arm64+x86_64.
SIM_LIB="${SIM_ARM_LIB}"

if [ "${SKIP_X86_SIM}" = false ]; then
    info "Compilation x86_64-apple-ios (simulator Intel, optionnel)..."
    cargo build --release --target x86_64-apple-ios || {
        warn "x86_64-apple-ios a échoué — on continue sans (simulator M-series suffira)."
        SKIP_X86_SIM=true
    }

    if [ "${SKIP_X86_SIM}" = false ]; then
        X86_SIM_LIB="${CRATE_DIR}/target/x86_64-apple-ios/release/libchabaka_engine.a"
        FAT_SIM_DIR="${CRATE_DIR}/target/ios-sim-fat/release"
        mkdir -p "${FAT_SIM_DIR}"
        SIM_LIB="${FAT_SIM_DIR}/libchabaka_engine.a"

        info "lipo — fat lib simulator (arm64 + x86_64)..."
        lipo -create "${SIM_ARM_LIB}" "${X86_SIM_LIB}" -output "${SIM_LIB}"
        info "Fat lib simulator :"
        lipo -info "${SIM_LIB}"
        ls -lh "${SIM_LIB}"
    fi
fi

# --- xcframework ------------------------------------------------------------
XCFW_OUT="${OUT_FRAMEWORKS}/chabaka_engine.xcframework"

# Supprime un xcframework précédent
rm -rf "${XCFW_OUT}"
mkdir -p "${OUT_FRAMEWORKS}"

info "xcodebuild -create-xcframework..."

# Note : pour une staticlib, xcodebuild attend le header .h.
# On génère un header minimal de la surface FFI C ABI.
HEADERS_DIR="${CRATE_DIR}/include"
mkdir -p "${HEADERS_DIR}"
cat > "${HEADERS_DIR}/chabaka_engine.h" << 'CHEADER'
// chabaka_engine.h — surface C ABI générée par build_ios.sh
// Ne pas éditer manuellement : synchroniser avec rust/chabaka_engine/src/lib.rs
#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ChabakaEngine ChabakaEngine;
typedef int32_t ChabakaStatus;

#define CHABAKA_STATUS_OK              0
#define CHABAKA_STATUS_NO_SOLUTION     1
#define CHABAKA_STATUS_INVALID_INPUT   2
#define CHABAKA_STATUS_KB_OPEN_FAILED  3
#define CHABAKA_STATUS_INTERNAL_PANIC  4
#define CHABAKA_STATUS_HANDLE_INVALID  5

ChabakaEngine* engine_create(const char* kb_path_utf8);
void           engine_destroy(ChabakaEngine* engine);

ChabakaStatus  engine_solve(
    ChabakaEngine*  engine,
    const uint8_t*  input_msgpack,
    uintptr_t       input_len,
    uint8_t**       out_ptr,
    uintptr_t*      out_len);

void           engine_free_buffer(uint8_t* ptr, uintptr_t len);
const char*    engine_last_error(void);
const char*    engine_version(void);
int32_t        engine_ping(void);

#ifdef __cplusplus
}
#endif
CHEADER

info "Header généré dans ${HEADERS_DIR}/chabaka_engine.h"

xcodebuild -create-xcframework \
    -library "${DEVICE_LIB}" \
    -headers "${HEADERS_DIR}" \
    -library "${SIM_LIB}" \
    -headers "${HEADERS_DIR}" \
    -output "${XCFW_OUT}"

# --- résumé -----------------------------------------------------------------
info "xcframework produit : ${XCFW_OUT}"
info "Contenu :"
find "${XCFW_OUT}" -type f | sort

info ""
info "Tailles par slice :"
du -sh "${XCFW_OUT}"/*/libchabaka_engine.a 2>/dev/null || du -sh "${XCFW_OUT}"/*/*/libchabaka_engine.a 2>/dev/null || true

info ""
info "Terminé. Prochain : flutter build ios --config-only --simulator"
