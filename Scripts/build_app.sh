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
DOCK_PLUGIN_DIR="$CONTENTS/PlugIns/BoltZipDockTile.plugin"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/showcase" "$CONTENTS/Helpers" "$APPEX_DIR/Contents/MacOS" "$DOCK_PLUGIN_DIR/Contents/MacOS"

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
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>en</string>
        <string>ja</string>
    </array>
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

echo "==> Building BoltZip Dock tile plug-in..."
xcrun clang -O2 -fobjc-arc -bundle -arch arm64 -mmacosx-version-min="$MIN_MACOS" \
    -isysroot "$SDK_PATH" -framework AppKit \
    "$ROOT_DIR/Sources/BoltZipDockTile/BoltZipDockTile.m" \
    -o "$DOCK_PLUGIN_DIR/Contents/MacOS/BoltZipDockTile"

cat <<DOCK_PLIST > "$DOCK_PLUGIN_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BoltZipDockTile</string>
    <key>CFBundleIdentifier</key>
    <string>dev.boltzip.macos.DockTile</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>NSPrincipalClass</key>
    <string>BoltZipDockTile</string>
</dict>
</plist>
DOCK_PLIST

echo "==> Generating bundle localization resources (.lproj)..."
for lang in zh-Hans zh-Hant en ja; do
    mkdir -p "$CONTENTS/Resources/${lang}.lproj" "$APPEX_DIR/Contents/Resources/${lang}.lproj"
done

cat <<'STR_ZH_HANS' > "$APPEX_DIR/Contents/Resources/zh-Hans.lproj/Localizable.strings"
"finder.compressFolderZip" = "将当前文件夹压缩为 ZIP";
"finder.compressFolderTarZst" = "将当前文件夹压缩为 TAR.ZST";
"finder.openWorkspace" = "打开 BoltZip 工作台";
"finder.smartExtract" = "智能解压到当前位置";
"finder.extractSubfolder" = "解压到同名文件夹";
"finder.extractTo" = "解压到指定文件夹...";
"finder.openInBoltZip" = "在 BoltZip 中打开浏览";
"finder.verifyIntegrity" = "校验压缩包完整性";
"finder.compressZip" = "压缩为 ZIP";
"finder.compressEachZip" = "分别压缩为独立 ZIP";
"finder.compressTarZst" = "压缩为 TAR.ZST (Zstd)";
"finder.compress7z" = "压缩为 7z";
"finder.encryptSplitCompress" = "加密 / 分卷高级压缩...";
"finder.repackEncryptCompress" = "重新打包 / 加密压缩...";
STR_ZH_HANS

cat <<'STR_ZH_HANT' > "$APPEX_DIR/Contents/Resources/zh-Hant.lproj/Localizable.strings"
"finder.compressFolderZip" = "將目前資料夾壓縮為 ZIP";
"finder.compressFolderTarZst" = "將目前資料夾壓縮為 TAR.ZST";
"finder.openWorkspace" = "開啟 BoltZip 工作台";
"finder.smartExtract" = "智慧解壓至目前位置";
"finder.extractSubfolder" = "解壓至同名資料夾";
"finder.extractTo" = "解壓至指定資料夾...";
"finder.openInBoltZip" = "在 BoltZip 中開啟瀏覽";
"finder.verifyIntegrity" = "驗證封存檔完整性";
"finder.compressZip" = "壓縮為 ZIP";
"finder.compressEachZip" = "分別壓縮為獨立 ZIP";
"finder.compressTarZst" = "壓縮為 TAR.ZST (Zstd)";
"finder.compress7z" = "壓縮為 7z";
"finder.encryptSplitCompress" = "加密 / 分卷進階壓縮...";
"finder.repackEncryptCompress" = "重新打包 / 加密壓縮...";
STR_ZH_HANT

cat <<'STR_EN' > "$APPEX_DIR/Contents/Resources/en.lproj/Localizable.strings"
"finder.compressFolderZip" = "Compress Folder as ZIP";
"finder.compressFolderTarZst" = "Compress Folder as TAR.ZST";
"finder.openWorkspace" = "Open BoltZip Workspace";
"finder.smartExtract" = "Smart Extract Here";
"finder.extractSubfolder" = "Extract to Subfolder";
"finder.extractTo" = "Extract To...";
"finder.openInBoltZip" = "Open in BoltZip";
"finder.verifyIntegrity" = "Verify Archive Integrity";
"finder.compressZip" = "Compress to ZIP";
"finder.compressEachZip" = "Compress Each to ZIP";
"finder.compressTarZst" = "Compress to TAR.ZST (Zstd)";
"finder.compress7z" = "Compress to 7z";
"finder.encryptSplitCompress" = "Encrypt & Split Archive...";
"finder.repackEncryptCompress" = "Repack / Encrypt Archive...";
STR_EN

cat <<'STR_JA' > "$APPEX_DIR/Contents/Resources/ja.lproj/Localizable.strings"
"finder.compressFolderZip" = "現在のフォルダを ZIP に圧縮";
"finder.compressFolderTarZst" = "現在のフォルダを TAR.ZST に圧縮";
"finder.openWorkspace" = "BoltZip ワークスペースを開く";
"finder.smartExtract" = "ここにスマート展開";
"finder.extractSubfolder" = "同名フォルダへ展開";
"finder.extractTo" = "場所を指定して展開...";
"finder.openInBoltZip" = "BoltZip で開く";
"finder.verifyIntegrity" = "書庫の整合性を検証";
"finder.compressZip" = "ZIP に圧縮";
"finder.compressEachZip" = "個別に ZIP へ圧縮";
"finder.compressTarZst" = "TAR.ZST (Zstd) に圧縮";
"finder.compress7z" = "7z に圧縮";
"finder.encryptSplitCompress" = "暗号化・分割して圧縮...";
"finder.repackEncryptCompress" = "再圧縮・暗号化...";
STR_JA

echo "==> Generating macOS AppIcon and per-format Document icons (.icns)..."
ICON_GEN_BIN="$DIST_DIR/bolt-icongen"
rm -f "$ICON_GEN_BIN"
swiftc -O -parse-as-library \
    -target "arm64-apple-macosx$MIN_MACOS" \
    -sdk "$SDK_PATH" \
    "$ROOT_DIR/Sources/BoltZipCore/Icons/"*.swift \
    "$ROOT_DIR/Scripts/generate_icon.swift" \
    -framework AppKit -framework CoreGraphics \
    -o "$ICON_GEN_BIN"
"$ICON_GEN_BIN" --resources "$CONTENTS/Resources"

cat <<PLIST > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>en</string>
        <string>ja</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>BoltZipApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>NSDockTilePlugIn</key>
    <string>BoltZipDockTile.plugin</string>
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
            <key>CFBundleTypeIconFile</key>
            <string>DocZip</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.zip-archive</string>
                <string>com.pkware.zip-archive</string>
                <string>com.winzip.zipx-archive</string>
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
            <key>CFBundleTypeIconFile</key>
            <string>DocRar</string>
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
            <key>CFBundleTypeIconFile</key>
            <string>Doc7z</string>
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
            <key>CFBundleTypeIconFile</key>
            <string>DocTar</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.tar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tar</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR + Gzip Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocTgz</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.gnu.gnu-zip-tar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tgz</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR + Zstandard Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocTzst</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.facebook.zstandard-tar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tzst</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR + XZ Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocTxz</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.tukaani.tar-xz-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txz</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR + Bzip2 Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocTbz2</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.tar-bzip2-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tbz2</string>
                <string>tbz</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>TAR + LZ4 Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocTlz4</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.lz4-tar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>tlz4</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Gzip Compressed Stream</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocGz</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.gnu.gnu-zip-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>gz</string>
                <string>gzip</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Zstandard Compressed Stream</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocZst</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.facebook.zstandard-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>zst</string>
                <string>zstd</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>XZ / LZMA Compressed Stream</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocXz</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.tukaani.xz-archive</string>
                <string>org.tukaani.lzma-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>xz</string>
                <string>lzma</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Bzip2 Compressed Stream</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocBz2</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.bzip2-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>bz2</string>
                <string>bzip2</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>LZ4 Compressed Stream</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocLz4</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.lz4.lz4-archive</string>
                <string>public.lz4-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>lz4</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Windows Cabinet Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocCab</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.microsoft.cab</string>
                <string>com.microsoft.cab-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>cab</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>XAR Archive</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocXar</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.apple.xar-archive</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>xar</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>ISO Disk Image</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocIso</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.iso-image</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>iso</string>
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
            <key>UTTypeIconFile</key>
            <string>DocRar</string>
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
            <key>UTTypeIconFile</key>
            <string>Doc7z</string>
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
            <string>com.winzip.zipx-archive</string>
            <key>UTTypeDescription</key>
            <string>Extended ZIP Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocZip</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.zip-archive</string>
                <string>public.archive</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>zipx</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.facebook.zstandard-archive</string>
            <key>UTTypeDescription</key>
            <string>Zstandard Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocZst</string>
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
            <key>UTTypeIconFile</key>
            <string>DocTzst</string>
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
            <string>XZ Compressed Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocXz</string>
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
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.tukaani.lzma-archive</string>
            <key>UTTypeDescription</key>
            <string>LZMA Compressed Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocXz</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>lzma</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.tukaani.tar-xz-archive</string>
            <key>UTTypeDescription</key>
            <string>TAR + XZ Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocTxz</string>
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
            <key>UTTypeIconFile</key>
            <string>DocLz4</string>
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
            <key>UTTypeIconFile</key>
            <string>DocTlz4</string>
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
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.microsoft.cab</string>
            <key>UTTypeDescription</key>
            <string>Windows Cabinet Archive</string>
            <key>UTTypeIconFile</key>
            <string>DocCab</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>cab</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Versioning document icon resources by content..."
"$ICON_GEN_BIN" --version-document-icons "$CONTENTS/Resources" "$CONTENTS/Info.plist"
rm -f "$ICON_GEN_BIN"

SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${BOLTZIP_NOTARY_PROFILE:-}"

echo "==> Code signing helpers, FinderSync.appex, and BoltZip.app (identity: $SIGN_IDENTITY)..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$CONTENTS/Helpers/boltzip"
    codesign --force --sign - --entitlements "$ROOT_DIR/Sources/BoltZipFinderSync/FinderSync.entitlements" "$APPEX_DIR"
    codesign --force --sign - "$DOCK_PLUGIN_DIR"
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$CONTENTS/Helpers/boltzip"
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
