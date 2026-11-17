#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building BoltZipApp and boltzip CLI (release, arm64)..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/BoltZip.app"
CONTENTS="$APP_DIR/Contents"
APPEX_DIR="$CONTENTS/PlugIns/BoltZipFinderSync.appex"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/showcase" "$CONTENTS/Helpers" "$APPEX_DIR/Contents/MacOS"

cp "$BIN_DIR/BoltZipApp" "$CONTENTS/MacOS/BoltZipApp"
cp "$BIN_DIR/boltzip" "$CONTENTS/Helpers/boltzip"
cp -R "$ROOT_DIR/showcase/." "$CONTENTS/Resources/showcase/"

echo "==> Building BoltZipFinderSync.appex (Finder top-level 'Bolt >' menu)..."
swiftc -O -parse-as-library \
    -target arm64-apple-macosx27.2 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation -framework AppKit -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.swift" \
    -o "$APPEX_DIR/Contents/MacOS/BoltZipFinderSync"

cat <<'APPEX_PLIST' > "$APPEX_DIR/Contents/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.2</string>
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

cat <<'PLIST' > "$CONTENTS/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.2</string>
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
            <string>Archive File</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>zip</string>
                <string>zipx</string>
                <string>z01</string>
                <string>7z</string>
                <string>tar</string>
                <string>gz</string>
                <string>tgz</string>
                <string>zst</string>
                <string>tzst</string>
                <string>xz</string>
                <string>txz</string>
                <string>bz2</string>
                <string>tbz2</string>
                <string>lz4</string>
                <string>iso</string>
                <string>cab</string>
                <string>xar</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
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
                    <string>tzst</string>
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
                    <string>tlz4</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing FinderSync.appex and BoltZip.app..."
codesign --force --sign - --entitlements "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.entitlements" "$APPEX_DIR"
codesign --force --sign - "$APP_DIR"

echo "==> Registering BoltZip.app and FinderSync extension..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
pluginkit -a "$APPEX_DIR" || true
pluginkit -e use -i dev.boltzip.macos.FinderSync || true

# Clean up legacy Services workflows so BoltZip only appears in top-level "Bolt >"
if [ -d "$HOME/Library/Services" ]; then
    rm -rf "$HOME/Library/Services"/BoltZip*.workflow 2>/dev/null || true
    /System/Library/CoreServices/pbs -update || true
fi

echo "==> Done! App bundle created at: $APP_DIR"
