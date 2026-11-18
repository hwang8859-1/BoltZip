#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="1.0.0"
APP_BUILD="11"
MIN_MACOS="26.0"
VENDOR_LIB_DIR="$ROOT_DIR/Vendor/Compression/lib"

if [ ! -f "$VENDOR_LIB_DIR/libzstd.a" ] || [ ! -f "$VENDOR_LIB_DIR/liblzma.a" ] || [ ! -f "$VENDOR_LIB_DIR/liblz4.a" ]; then
    echo "==> Building Apple Silicon (arm64) compression static libraries..."
    "$ROOT_DIR/Scripts/build_universal_deps.sh"
fi

echo "==> Building BoltZipApp and boltzip CLI (release, arm64, minOS $MIN_MACOS)..."
swift build -c release --arch arm64

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/BoltZip.app"
CONTENTS="$APP_DIR/Contents"
APPEX_DIR="$CONTENTS/PlugIns/BoltZipFinderSync.appex"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/showcase" "$CONTENTS/Helpers" "$APPEX_DIR/Contents/MacOS"

cp "$BIN_DIR/BoltZipApp" "$CONTENTS/MacOS/BoltZipApp"
cp "$BIN_DIR/boltzip" "$CONTENTS/Helpers/boltzip"
cp -R "$ROOT_DIR/showcase/." "$CONTENTS/Resources/showcase/"

echo "==> Building BoltZipFinderSync.appex (arm64, minOS $MIN_MACOS)..."
SDK_PATH="$(xcrun --show-sdk-path)"

swiftc -O -parse-as-library \
    -target "arm64-apple-macosx$MIN_MACOS" \
    -sdk "$SDK_PATH" \
    -framework Foundation -framework AppKit -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.swift" \
    -o "$APPEX_DIR/Contents/MacOS/BoltZipFinderSync"

cat <<APPEX_PLIST > "$APPEX_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Bolt</string>
    <key>CFBundleExecutable</key>
    <string>BoltZipFinderSync</string>
    <key>CFBundleIdentifier</key>
    <string>dev.boltzip.macos.FinderSync</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Bolt</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict/>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>FinderSync</string>
    </dict>
</dict>
</plist>
APPEX_PLIST

echo "==> Generating macOS AppIcon.icns..."
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat <<PLIST > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>BoltZipApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.boltzip.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BoltZip</string>
    <key>CFBundleDisplayName</key>
    <string>BoltZip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>dev.boltzip.macos.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>boltzip</string>
            </array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>ZIP Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.zip-archive</string>
                <string>com.pkware.zip-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>zip</string>
                <string>zipx</string>
                <string>z01</string>
                <string>cbz</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>RAR Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.rarlab.rar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>rar</string>
                <string>r00</string>
                <string>r01</string>
                <string>cbr</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>7-Zip Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.7-zip.7-zip-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>7z</string>
                <string>cb7</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.tar-archive</string>
                <string>org.gnu.gnu-zip-tar-archive</string>
                <string>com.facebook.zstandard-tar-archive</string>
                <string>org.tukaani.tar-xz-archive</string>
                <string>public.tar-bzip2-archive</string>
                <string>public.lz4-tar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tar</string>
                <string>tgz</string>
                <string>tzst</string>
                <string>txz</string>
                <string>tbz2</string>
                <string>tbz</string>
                <string>tlz4</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Compressed Stream Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.gnu.gnu-zip-archive</string>
                <string>com.facebook.zstandard-archive</string>
                <string>org.tukaani.xz-archive</string>
                <string>public.bzip2-archive</string>
                <string>org.lz4.lz4-archive</string>
                <string>public.lz4-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>gz</string>
                <string>gzip</string>
                <string>zst</string>
                <string>zstd</string>
                <string>xz</string>
                <string>lzma</string>
                <string>bz2</string>
                <string>bzip2</string>
                <string>lz4</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Disk Image &amp; Package Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.iso-image</string>
                <string>com.microsoft.cab</string>
                <string>com.microsoft.cab-archive</string>
                <string>com.apple.xar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>iso</string>
                <string>cab</string>
                <string>xar</string>
                <string>pkg</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.rarlab.rar-archive</string>
            <key>UTTypeDescription</key>
            <string>RAR Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>rar</string>
                    <string>r00</string>
                    <string>r01</string>
                    <string>cbr</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.7-zip.7-zip-archive</string>
            <key>UTTypeDescription</key>
            <string>7-Zip Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>7z</string>
                    <string>cb7</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.facebook.zstandard-archive</string>
            <key>UTTypeDescription</key>
            <string>Zstandard Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>zst</string>
                    <string>zstd</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.facebook.zstandard-tar-archive</string>
            <key>UTTypeDescription</key>
            <string>TAR + Zstandard Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>tzst</string>
                    <string>tar.zst</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.tukaani.xz-archive</string>
            <key>UTTypeDescription</key>
            <string>XZ / LZMA Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>xz</string>
                    <string>lzma</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.tukaani.tar-xz-archive</string>
            <key>UTTypeDescription</key>
            <string>TAR + XZ Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>txz</string>
                    <string>tar.xz</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.lz4.lz4-archive</string>
            <key>UTTypeDescription</key>
            <string>LZ4 Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>lz4</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>public.lz4-tar-archive</string>
            <key>UTTypeDescription</key>
            <string>TAR + LZ4 Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>tlz4</string>
                    <string>tar.lz4</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing helpers, FinderSync.appex, and BoltZip.app..."
codesign --force --sign - "$CONTENTS/Helpers/boltzip"
codesign --force --sign - --entitlements "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.entitlements" "$APPEX_DIR"
codesign --force --sign - "$APP_DIR"

echo "==> Registering BoltZip.app and FinderSync extension..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
pluginkit -a "$APPEX_DIR" || true
pluginkit -e use -i dev.boltzip.macos.FinderSync || true

# Clean up legacy Services workflows so BoltZip only appears in top-level "Bolt >"
if [ -d "$HOME/Library/Services" ]; then
    find "$HOME/Library/Services" -maxdepth 1 -name "BoltZip*.workflow" -exec rm -rf {} + 2>/dev/null || true
    /System/Library/CoreServices/pbs -update || true
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

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -z "$(git status --porcelain --untracked-files=no)" ]; then
    echo "==> Creating clean source archives from git HEAD ($APP_VERSION)..."
    git archive --format=tar.gz --prefix="BoltZip-${APP_VERSION}/" -o "$SOURCE_TAR" HEAD
    git archive --format=zip --prefix="BoltZip-${APP_VERSION}/" -o "$SOURCE_ZIP" HEAD
else
    echo "==> Creating clean source archives from workspace ($APP_VERSION)..."
    STAGE_SRC="$(mktemp -d "${TMPDIR:-/tmp}/BoltZip-src.XXXXXX")"
    trap 'rm -rf "$STAGE_SRC"' EXIT
    mkdir -p "$STAGE_SRC/BoltZip-${APP_VERSION}"
    COPYFILE_DISABLE=1 rsync -a \
        --exclude='.git' \
        --exclude='.build' \
        --exclude='.swiftpm' \
        --exclude='DerivedData' \
        --exclude='dist' \
        --exclude='.workbuddy' \
        --exclude='marketing' \
        --exclude='.DS_Store' \
        --exclude='._*' \
        "$ROOT_DIR/" "$STAGE_SRC/BoltZip-${APP_VERSION}/"
    COPYFILE_DISABLE=1 tar -czf "$SOURCE_TAR" -C "$STAGE_SRC" "BoltZip-${APP_VERSION}"
    ditto -c -k --sequesterRsrc --keepParent "$STAGE_SRC/BoltZip-${APP_VERSION}" "$SOURCE_ZIP"
fi

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$RELEASE_DMG")" "$(basename "$RELEASE_ZIP")" "$(basename "$SOURCE_TAR")" "$(basename "$SOURCE_ZIP")" > "$SUMS_FILE"
)

echo "==> Done! App bundle created at: $APP_DIR"
echo "==> DMG installer created at: $RELEASE_DMG"
echo "==> App archive created at: $RELEASE_ZIP"
echo "==> Source archives created at: $SOURCE_TAR , $SOURCE_ZIP"
echo "==> Checksums written to: $SUMS_FILE"
