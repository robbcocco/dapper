#!/usr/bin/env bash
#
# Builds universal (arm64 + x86_64) libmtp + libusb dylibs and stages them
# under `macos/Runner/Frameworks/` so the Xcode Copy Files build phase
# bundles them into `Runner.app/Contents/Frameworks/` for the final app.
#
# Status: scaffold. Run this once the MtpPlugin.swift body is ready to call
# libmtp. The Swift side links the dylibs via FFI (`@_silgen_name` or a thin
# C bridge header); see MtpPlugin.swift for the function map.
#
# Prereqs (Homebrew):
#   brew install autoconf automake libtool pkg-config
#
# Output:
#   macos/Runner/Frameworks/libusb-1.0.0.dylib    (universal binary)
#   macos/Runner/Frameworks/libmtp.9.dylib         (universal binary, links libusb)
#
# After running, you still need to:
#   1. Drag both dylibs into the Xcode "Runner" target's
#      "Frameworks, Libraries, and Embedded Content" section with
#      "Embed & Sign" so they end up in the .app's Frameworks dir.
#   2. Add `com.apple.security.cs.disable-library-validation` to both
#      DebugProfile.entitlements and Release.entitlements (or sign the
#      dylibs with the app's team ID, which is the cleaner path).
#   3. Verify load paths: `otool -L Runner.app/Contents/Frameworks/libmtp.*`.
#      The libusb dependency must resolve via `@rpath/libusb-1.0.0.dylib`;
#      use `install_name_tool -change ... @rpath/...` if it doesn't.
#
# Usage:
#   bash macos/scripts/build_libmtp.sh
#   bash macos/scripts/build_libmtp.sh --clean

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly BUILD_ROOT="${REPO_ROOT}/macos/scripts/.build"
readonly OUT_DIR="${REPO_ROOT}/macos/Runner/Frameworks"

readonly LIBUSB_VERSION="1.0.27"
readonly LIBMTP_VERSION="1.1.21"
readonly LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2"
readonly LIBMTP_URL="https://sourceforge.net/projects/libmtp/files/libmtp/${LIBMTP_VERSION}/libmtp-${LIBMTP_VERSION}.tar.gz/download"

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "${BUILD_ROOT}"
    echo "Cleaned ${BUILD_ROOT}"
    exit 0
fi

mkdir -p "${BUILD_ROOT}" "${OUT_DIR}"

build_for_arch() {
    local arch="$1"
    local prefix="${BUILD_ROOT}/${arch}"
    local host_triple
    case "${arch}" in
        arm64) host_triple="aarch64-apple-darwin" ;;
        x86_64) host_triple="x86_64-apple-darwin" ;;
        *) echo "unknown arch: ${arch}"; exit 1 ;;
    esac

    # ── libusb ────────────────────────────────────────────────────────────
    if [[ ! -f "${prefix}/lib/libusb-1.0.0.dylib" ]]; then
        local src="${BUILD_ROOT}/libusb-${LIBUSB_VERSION}-${arch}"
        if [[ ! -d "${src}" ]]; then
            mkdir -p "${src}"
            curl -fL "${LIBUSB_URL}" | tar -xj -C "${src}" --strip-components=1
        fi
        pushd "${src}" > /dev/null
        ./configure \
            --prefix="${prefix}" \
            --host="${host_triple}" \
            --disable-static \
            CFLAGS="-arch ${arch}" \
            LDFLAGS="-arch ${arch}"
        make -j"$(sysctl -n hw.ncpu)"
        make install
        popd > /dev/null
    fi

    # ── libmtp ────────────────────────────────────────────────────────────
    if [[ ! -f "${prefix}/lib/libmtp.9.dylib" ]]; then
        local src="${BUILD_ROOT}/libmtp-${LIBMTP_VERSION}-${arch}"
        if [[ ! -d "${src}" ]]; then
            mkdir -p "${src}"
            curl -fL "${LIBMTP_URL}" | tar -xz -C "${src}" --strip-components=1
        fi
        pushd "${src}" > /dev/null
        PKG_CONFIG_PATH="${prefix}/lib/pkgconfig" ./configure \
            --prefix="${prefix}" \
            --host="${host_triple}" \
            --disable-static \
            --disable-mtpz \
            CFLAGS="-arch ${arch} -I${prefix}/include/libusb-1.0" \
            LDFLAGS="-arch ${arch} -L${prefix}/lib"
        make -j"$(sysctl -n hw.ncpu)"
        make install
        popd > /dev/null
    fi
}

build_for_arch arm64
build_for_arch x86_64

# ── Stitch universal binaries via lipo ──────────────────────────────────
fuse() {
    local name="$1"
    lipo -create \
        "${BUILD_ROOT}/arm64/lib/${name}" \
        "${BUILD_ROOT}/x86_64/lib/${name}" \
        -output "${OUT_DIR}/${name}"
    install_name_tool -id "@rpath/${name}" "${OUT_DIR}/${name}"
    echo "→ ${OUT_DIR}/${name}"
}

fuse "libusb-1.0.0.dylib"
fuse "libmtp.9.dylib"

# Rewrite libmtp's libusb dependency to @rpath so the bundle's Frameworks
# dir resolves it at runtime.
LIBUSB_ABS=$(otool -L "${OUT_DIR}/libmtp.9.dylib" | awk '/libusb-1\.0\.0/ {print $1; exit}')
if [[ -n "${LIBUSB_ABS}" && "${LIBUSB_ABS}" != "@rpath/libusb-1.0.0.dylib" ]]; then
    install_name_tool -change "${LIBUSB_ABS}" "@rpath/libusb-1.0.0.dylib" \
        "${OUT_DIR}/libmtp.9.dylib"
fi

echo
echo "Done. Dylibs staged at ${OUT_DIR}."
echo "Next: open the Xcode project and embed them in the Runner target's"
echo "      Frameworks/Embedded Content section with 'Embed & Sign'."
