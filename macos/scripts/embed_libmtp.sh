#!/usr/bin/env bash
#
# Embeds libmtp + libusb into a built dapper.app so the binary doesn't
# depend on Homebrew at runtime.
#
# Usage:
#   bash macos/scripts/embed_libmtp.sh \
#     build/macos/Build/Products/Debug/dapper.app
#
# Or hook it into a build phase / CI step. The script is idempotent — safe
# to re-run.
#
# Steps:
#   1. Copy libmtp.9.dylib + libusb-1.0.0.dylib from Homebrew into the
#      app's Contents/Frameworks/.
#   2. Rewrite their install_name to @rpath/<name> so the dynamic linker
#      resolves them via the app's rpath (which already includes
#      @executable_path/../Frameworks via the Xcode build settings).
#   3. Rewrite the Runner binary's libmtp / libusb references to @rpath
#      so it loads the embedded copies instead of /opt/homebrew/lib.
#   4. Codesign the embedded dylibs ad-hoc so the hardened runtime can
#      load them. (For App Store / notarised builds, replace `-` with
#      your Developer ID.)
#
# Required entitlement (already added):
#   com.apple.security.cs.disable-library-validation
#
# Verification:
#   otool -L "$APP/Contents/MacOS/dapper" | grep -E 'mtp|usb'
#     → should show @rpath/libmtp.9.dylib + @rpath/libusb-1.0.0.dylib
#   codesign --verify --deep --strict --verbose=2 "$APP"

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-dapper.app>"
    exit 1
fi

readonly APP="$1"

if [[ ! -d "$APP" ]]; then
    echo "Not a directory: $APP"
    exit 1
fi

readonly FRAMEWORKS="$APP/Contents/Frameworks"
readonly BIN="$APP/Contents/MacOS/dapper"

# Resolve Homebrew dylib paths via brew prefix so this works on Intel +
# Apple Silicon machines.
readonly LIBMTP_PREFIX="$(brew --prefix libmtp 2>/dev/null || echo /opt/homebrew/opt/libmtp)"
readonly LIBUSB_PREFIX="$(brew --prefix libusb 2>/dev/null || echo /opt/homebrew/opt/libusb)"
readonly LIBMTP_SRC="$LIBMTP_PREFIX/lib/libmtp.9.dylib"
readonly LIBUSB_SRC="$LIBUSB_PREFIX/lib/libusb-1.0.0.dylib"

if [[ ! -f "$LIBMTP_SRC" ]]; then
    echo "libmtp not found at $LIBMTP_SRC — run 'brew install libmtp' first"
    exit 1
fi
if [[ ! -f "$LIBUSB_SRC" ]]; then
    echo "libusb not found at $LIBUSB_SRC — run 'brew install libusb' first"
    exit 1
fi

mkdir -p "$FRAMEWORKS"

# 1. Copy
cp -f "$LIBMTP_SRC" "$FRAMEWORKS/libmtp.9.dylib"
cp -f "$LIBUSB_SRC" "$FRAMEWORKS/libusb-1.0.0.dylib"
chmod u+w "$FRAMEWORKS/libmtp.9.dylib" "$FRAMEWORKS/libusb-1.0.0.dylib"

# 2. Rewrite install_names of the embedded dylibs
install_name_tool -id "@rpath/libmtp.9.dylib" "$FRAMEWORKS/libmtp.9.dylib"
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$FRAMEWORKS/libusb-1.0.0.dylib"

# Make libmtp resolve its libusb dependency via @rpath
LIBUSB_REF=$(otool -L "$FRAMEWORKS/libmtp.9.dylib" | awk '/libusb/ {print $1; exit}')
if [[ -n "$LIBUSB_REF" && "$LIBUSB_REF" != "@rpath/libusb-1.0.0.dylib" ]]; then
    install_name_tool -change "$LIBUSB_REF" "@rpath/libusb-1.0.0.dylib" \
        "$FRAMEWORKS/libmtp.9.dylib"
fi

# 3. Rewrite references in every Mach-O the linker may have produced
#    pointing to the Homebrew dylibs. Flutter's macOS build emits multiple
#    binaries depending on profile/debug/release shape:
#      - Contents/MacOS/<product>             (stub binary, AOT release)
#      - Contents/MacOS/<product>.debug.dylib (debug)
#      - Contents/MacOS/__preview.dylib       (debug)
#      - App.framework/App                    (some configurations)
#    Sweep every reachable Mach-O and rewrite any libmtp/libusb load
#    command. Skip the embedded dylibs themselves; their install_name was
#    already fixed above.
rewrite_refs() {
    local target="$1"
    while IFS= read -r ref; do
        case "$ref" in
            *libmtp.9.dylib)
                install_name_tool -change "$ref" "@rpath/libmtp.9.dylib" "$target" 2>/dev/null || true
                ;;
            *libusb-1.0.0.dylib)
                install_name_tool -change "$ref" "@rpath/libusb-1.0.0.dylib" "$target" 2>/dev/null || true
                ;;
        esac
    done < <(otool -L "$target" 2>/dev/null | awk '/(libmtp|libusb)/ {print $1}')
}

while IFS= read -r -d '' target; do
    case "$target" in
        "$FRAMEWORKS/libmtp.9.dylib"|"$FRAMEWORKS/libusb-1.0.0.dylib")
            continue ;;
    esac
    # Skip non-Mach-O entries (resources, JSON, etc.)
    file -b "$target" | grep -q 'Mach-O' || continue
    rewrite_refs "$target"
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Frameworks" \
              -type f \( -perm -u+x -o -name '*.dylib' \) -print0 2>/dev/null)

# 4. Codesign every binary we modified, bottom-up. Without re-signing,
#    dyld refuses to load Mach-Os whose hash no longer matches the embedded
#    signature.
#
#    Hardened runtime (`--options runtime`) only applies in release builds —
#    Debug builds need to load arbitrary dylibs (Flutter's debug VM service,
#    DartDevc, etc.) without library validation, and Xcode's Debug
#    configuration omits hardened runtime by default. We mirror that here.
#
#    For release / notarisation set RELEASE_CODESIGN=1 and CODESIGN_IDENTITY
#    to your Developer ID.
SIGN_ID="${CODESIGN_IDENTITY:--}"
RUNTIME_OPT=""
if [[ "${RELEASE_CODESIGN:-0}" == "1" ]]; then
    RUNTIME_OPT="--options runtime"
fi

# Sign embedded dylibs (their hash changed via install_name_tool).
codesign --force --sign "$SIGN_ID" $RUNTIME_OPT --timestamp=none \
    "$FRAMEWORKS/libusb-1.0.0.dylib"
codesign --force --sign "$SIGN_ID" $RUNTIME_OPT --timestamp=none \
    "$FRAMEWORKS/libmtp.9.dylib"

# Sign every other Mach-O we rewrote refs in (dapper.debug.dylib, etc.).
# Use --preserve-metadata so entitlements + Info.plist hashes carried over
# from Xcode's original sign survive — `--deep --force` strips them.
while IFS= read -r -d '' target; do
    case "$target" in
        "$FRAMEWORKS/libmtp.9.dylib"|"$FRAMEWORKS/libusb-1.0.0.dylib")
            continue ;;
    esac
    file -b "$target" | grep -q 'Mach-O' || continue
    # Only re-sign Mach-Os we actually touched (those that referenced
    # libmtp or libusb before our rewrite — easiest test: does the file
    # already have a signature pointing at @rpath/lib{mtp,usb}?).
    if otool -L "$target" 2>/dev/null | grep -qE '@rpath/lib(mtp|usb)'; then
        codesign --force --sign "$SIGN_ID" $RUNTIME_OPT --timestamp=none \
            --preserve-metadata=entitlements,requirements,flags \
            "$target" 2>/dev/null || true
    fi
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Frameworks" \
              -type f \( -perm -u+x -o -name '*.dylib' \) -print0 2>/dev/null)

# Finally re-seal the outer app so Sealed Resources list catches up.
# `--deep` propagates through every child Mach-O that wasn't already
# signed. We preserve entitlements so disable-library-validation survives.
codesign --force --sign "$SIGN_ID" $RUNTIME_OPT --timestamp=none --deep \
    --preserve-metadata=entitlements,requirements,flags "$APP"

echo
echo "Embedded:"
echo "  $FRAMEWORKS/libmtp.9.dylib"
echo "  $FRAMEWORKS/libusb-1.0.0.dylib"
echo
echo "Mach-O references (should all be @rpath/...):"
while IFS= read -r -d '' t; do
    file -b "$t" | grep -q 'Mach-O' || continue
    refs=$(otool -L "$t" 2>/dev/null | awk '/(libmtp|libusb)/ {print $1}')
    if [[ -n "$refs" ]]; then
        echo "  $(basename "$t"):"
        echo "$refs" | sed 's/^/    /'
    fi
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Frameworks" \
              -type f \( -perm -u+x -o -name '*.dylib' \) -print0 2>/dev/null)
