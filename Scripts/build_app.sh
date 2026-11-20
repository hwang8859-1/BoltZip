#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_ONLY=0
REGISTER_LOCAL=1
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        --no-register) REGISTER_LOCAL=0 ;;
        -h|--help)
            echo "Usage: ./Scripts/build_app.sh [--app-only] [--no-register]"
            echo "Full release packaging requires a clean Git checkout."
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$APP_ONLY" -eq 0 ]; then
    if [ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$ROOT_DIR" ]; then
        echo "Error: Release packaging requires a Git checkout. Use --app-only to build from a source archive." >&2
        exit 1
    fi
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "Error: Commit tracked changes before packaging a release. Use --app-only for local builds." >&2
        exit 1
    fi
    SOURCE_REV="$(git rev-parse --verify HEAD)"
    if [ -n "$(git ls-tree --name-only "$SOURCE_REV" -- .workbuddy design doc marketing dist)" ]; then
        echo "Error: Release source contains tracked local-only directories." >&2
        exit 1
    fi
fi

VERSION_FILE="$ROOT_DIR/Sources/BoltZipCore/Models/BoltZipVersion.swift"
APP_VERSION="$(sed -n 's/.*public static let current = "\([^"]*\)".*/\1/p' "$VERSION_FILE" | head -n 1)"
APP_BUILD="$(sed -n 's/.*public static let build = "\([^"]*\)".*/\1/p' "$VERSION_FILE" | head -n 1)"
if [ -z "$APP_VERSION" ] || [ -z "$APP_BUILD" ]; then
    echo "Error: Failed to read BoltZipVersion from $VERSION_FILE" >&2
    exit 1
fi
MIN_MACOS="26.0"
VENDOR_LIB_DIR="$ROOT_DIR/Vendor/Compression/lib"
SEVEN_ZIP_DIR="$ROOT_DIR/Vendor/SevenZip"

(
    cd "$SEVEN_ZIP_DIR"
    shasum -a 256 --check 7zz.sha256
)

if [ ! -f "$VENDOR_LIB_DIR/libzstd.a" ] || [ ! -f "$VENDOR_LIB_DIR/liblzma.a" ] || [ ! -f "$VENDOR_LIB_DIR/liblz4.a" ]; then
    echo "==> Building Apple Silicon (arm64) compression static libraries..."
    "$ROOT_DIR/Scripts/build_universal_deps.sh"
fi

BUNDLE_RESOURCES="$ROOT_DIR/Scripts/BundleResources"

render_bundle_plist() {
    local bundle="$1"
    local output="$2"
    sed -e "s|@APP_VERSION@|$APP_VERSION|g" \
        -e "s|@APP_BUILD@|$APP_BUILD|g" \
        -e "s|@MIN_MACOS@|$MIN_MACOS|g" \
        "$BUNDLE_RESOURCES/$bundle/Info.plist" > "$output"
}

echo "==> Building BoltZipApp and boltzip CLI (release, arm64, minOS $MIN_MACOS)..."
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/BoltZip.app"
CONTENTS="$APP_DIR/Contents"
APPEX_DIR="$CONTENTS/PlugIns/BoltZipFinderSync.appex"
DOCK_PLUGIN_DIR="$CONTENTS/PlugIns/BoltZipDockTile.plugin"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/showcase" "$CONTENTS/Helpers" "$APPEX_DIR/Contents/MacOS" "$DOCK_PLUGIN_DIR/Contents/MacOS"

cp "$BIN_DIR/BoltZipApp" "$CONTENTS/MacOS/BoltZipApp"
cp "$BIN_DIR/boltzip" "$CONTENTS/Helpers/boltzip"
cp "$SEVEN_ZIP_DIR/7zz" "$CONTENTS/Helpers/7zz"
mkdir -p "$CONTENTS/Resources/Licenses/7-Zip"
cp "$SEVEN_ZIP_DIR/License.txt" "$SEVEN_ZIP_DIR/LGPL-2.1.txt" "$SEVEN_ZIP_DIR/UPSTREAM.txt" "$CONTENTS/Resources/Licenses/7-Zip/"
cp -R "$ROOT_DIR/showcase/." "$CONTENTS/Resources/showcase/"

# Strip local symbols only in the shipped copies, keeping the build products and matching dSYMs.
xcrun strip -x "$CONTENTS/MacOS/BoltZipApp" "$CONTENTS/Helpers/boltzip"

echo "==> Building BoltZipFinderSync.appex (arm64, minOS $MIN_MACOS)..."
SDK_PATH="$(xcrun --show-sdk-path)"

swiftc -O -parse-as-library \
    -target "arm64-apple-macosx$MIN_MACOS" \
    -sdk "$SDK_PATH" \
    -framework Foundation -framework AppKit -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.swift" \
    -o "$APPEX_DIR/Contents/MacOS/BoltZipFinderSync"

render_bundle_plist "BoltZipFinderSync" "$APPEX_DIR/Contents/Info.plist"

echo "==> Building BoltZip Dock tile plug-in..."
xcrun clang -O2 -fobjc-arc -bundle -arch arm64 -mmacosx-version-min="$MIN_MACOS" \
    -isysroot "$SDK_PATH" -framework AppKit \
    "$ROOT_DIR/Sources/BoltZipDockTile/BoltZipDockTile.m" \
    -o "$DOCK_PLUGIN_DIR/Contents/MacOS/BoltZipDockTile"

render_bundle_plist "BoltZipDockTile" "$DOCK_PLUGIN_DIR/Contents/Info.plist"

echo "==> Generating bundle localization resources (.lproj)..."
for lang in zh-Hans zh-Hant en ja; do
    mkdir -p "$CONTENTS/Resources/${lang}.lproj" "$APPEX_DIR/Contents/Resources/${lang}.lproj"
    cp "$BUNDLE_RESOURCES/BoltZipFinderSync/${lang}.lproj/Localizable.strings" "$APPEX_DIR/Contents/Resources/${lang}.lproj/"
done

echo "==> Generating macOS AppIcon and per-format Document icons (.icns)..."
ICON_GEN_BIN="$DIST_DIR/bolt-icongen"
rm -f "$ICON_GEN_BIN"
swiftc -O -parse-as-library \
    -target "arm64-apple-macosx$MIN_MACOS" \
    -sdk "$SDK_PATH" \
    "$ROOT_DIR/Sources/BoltZipCore/Icons/"*.swift \
    "$ROOT_DIR/Scripts/generate_icon.swift" \
    "$ROOT_DIR/Scripts/IconResourceCompression.swift" \
    -framework AppKit -framework CoreGraphics \
    -o "$ICON_GEN_BIN"
"$ICON_GEN_BIN" --resources "$CONTENTS/Resources"

render_bundle_plist "BoltZipApp" "$CONTENTS/Info.plist"

echo "==> Versioning document icon resources by content..."
"$ICON_GEN_BIN" --version-document-icons "$CONTENTS/Resources" "$CONTENTS/Info.plist"
rm -f "$ICON_GEN_BIN"

SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${BOLTZIP_NOTARY_PROFILE:-}"

echo "==> Code signing helpers, FinderSync.appex, and BoltZip.app (identity: $SIGN_IDENTITY)..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$CONTENTS/Helpers/boltzip"
    codesign --force --sign - "$CONTENTS/Helpers/7zz"
    codesign --force --sign - --entitlements "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.entitlements" "$APPEX_DIR"
    codesign --force --sign - "$DOCK_PLUGIN_DIR"
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$CONTENTS/Helpers/boltzip"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$CONTENTS/Helpers/7zz"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.entitlements" "$APPEX_DIR"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$DOCK_PLUGIN_DIR"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

if [ "$REGISTER_LOCAL" -eq 1 ]; then
    echo "==> Registering BoltZip.app and FinderSync extension..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
    pluginkit -a "$APPEX_DIR" || true
    pluginkit -e use -i dev.boltzip.macos.FinderSync || true

    # Clean up legacy Services workflows so BoltZip only appears in top-level "Bolt >"
    if [ -d "$HOME/Library/Services" ]; then
        find "$HOME/Library/Services" -maxdepth 1 -name "BoltZip*.workflow" -exec rm -rf {} + 2>/dev/null || true
        /System/Library/CoreServices/pbs -update || true
    fi
fi

if [ "$APP_ONLY" -eq 1 ]; then
    echo "==> Done! App bundle created at: $APP_DIR"
    exit 0
fi

RELEASE_DMG="$DIST_DIR/BoltZip-${APP_VERSION}-macOS-arm64.dmg"
RELEASE_ZIP="$DIST_DIR/BoltZip-${APP_VERSION}-macOS-arm64.zip"
SOURCE_TAR="$DIST_DIR/BoltZip-${APP_VERSION}-source.tar.gz"
SOURCE_ZIP="$DIST_DIR/BoltZip-${APP_VERSION}-source.zip"
SUMS_FILE="$DIST_DIR/BoltZip-${APP_VERSION}-SHA256SUMS.txt"

rm -f "$RELEASE_DMG" "$RELEASE_ZIP" "$SOURCE_TAR" "$SOURCE_ZIP" "$SUMS_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_ZIP"

echo "==> Creating drag-to-Applications installer DMG ($RELEASE_DMG)..."
"$ROOT_DIR/Scripts/create_dmg.sh" "$APP_DIR" "$RELEASE_DMG" "BoltZip" "v${APP_VERSION} · Apple Silicon"

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$RELEASE_DMG"
    if [ -n "$NOTARY_PROFILE" ]; then
        echo "==> Submitting DMG for Apple notarization (profile: $NOTARY_PROFILE)..."
        xcrun notarytool submit "$RELEASE_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP_DIR"
        xcrun stapler staple "$RELEASE_DMG"
        rm -f "$RELEASE_ZIP"
        ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_ZIP"
    fi
fi

echo "==> Creating source archives from Git commit $SOURCE_REV ($APP_VERSION)..."
git archive --format=tar.gz --prefix="BoltZip-${APP_VERSION}/" -o "$SOURCE_TAR" "$SOURCE_REV"
git archive --format=zip --prefix="BoltZip-${APP_VERSION}/" -o "$SOURCE_ZIP" "$SOURCE_REV"

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$RELEASE_DMG")" "$(basename "$RELEASE_ZIP")" "$(basename "$SOURCE_TAR")" "$(basename "$SOURCE_ZIP")" > "$SUMS_FILE"
)

echo "==> Done! App bundle created at: $APP_DIR"
echo "==> DMG installer created at: $RELEASE_DMG"
echo "==> App archive created at: $RELEASE_ZIP"
echo "==> Source archives created at: $SOURCE_TAR , $SOURCE_ZIP"
echo "==> Checksums written to: $SUMS_FILE"
