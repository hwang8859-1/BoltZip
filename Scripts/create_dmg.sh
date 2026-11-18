#!/bin/zsh
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <BoltZip.app> <output.dmg> [volume_name] [version_label]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$1"
OUTPUT_DMG="$2"
VOL_NAME="${3:-BoltZip Installer}"
VERSION_LABEL="${4:-macOS}"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App bundle not found at $APP_PATH" >&2
    exit 1
fi

DMG_WORK="$(mktemp -d "${TMPDIR:-/tmp}/BoltZip-dmg.XXXXXX")"
MOUNT_DIR=""
DEVICE=""
cleanup() {
    if [ -n "$DEVICE" ]; then
        hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
    elif [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$DMG_WORK"
}
trap cleanup EXIT

# Detach any leftover volume with the same name
if [ -d "/Volumes/$VOL_NAME" ]; then
    hdiutil detach "/Volumes/$VOL_NAME" -force >/dev/null 2>&1 || true
fi

STAGE="$DMG_WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP_PATH" "$STAGE/BoltZip.app"
ln -s /Applications "$STAGE/Applications"

swift "$SCRIPT_DIR/generate_dmg_bg.swift" "$STAGE/.background/background.tiff" "$VERSION_LABEL"

if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi

# Calculate image size in MB (bundle size + generous headroom for HFS+ metadata)
APP_KB="$(du -sk "$STAGE" | awk '{print $1}')"
SIZE_MB=$(( (APP_KB / 1024) + 32 ))
RW_DMG="$DMG_WORK/rw.dmg"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    -size "${SIZE_MB}m" \
    "$RW_DMG" >/dev/null

ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(echo "$ATTACH_OUT" | awk 'NR==1 {print $1}')"
MOUNT_DIR="$(echo "$ATTACH_OUT" | awk '/\/Volumes\// { idx=index($0, "/Volumes/"); print substr($0, idx); exit }')"

if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "ERROR: Failed to resolve mount point from hdiutil attach" >&2
    exit 1
fi

# Configure Finder drag-to-Applications window layout & persist .DS_Store
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 0.6
        set w to container window
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        try
            set pathbar visible of w to false
        end try
        try
            set sidebar width of w to 0
        end try
        set viewOptions to the icon view options of w
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 108
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "BoltZip.app" of w to {180, 184}
        set position of item "Applications" of w to {480, 184}
        set bounds of w to {180, 140, 840, 586}
        close
        open
        delay 0.5
        set bounds of container window to {180, 140, 840, 586}
        update without registering applications
        delay 2
        close
        delay 1
    end tell
end tell
EOF

if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if xcrun -f SetFile >/dev/null 2>&1; then
        xcrun SetFile -a C "$MOUNT_DIR" || true
        xcrun SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" || true
    fi
fi

sync
sleep 1

hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force >/dev/null
DEVICE=""
MOUNT_DIR=""

rm -f "$OUTPUT_DMG"
mkdir -p "$(dirname "$OUTPUT_DMG")"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null

echo "==> DMG installer created at: $OUTPUT_DMG"
