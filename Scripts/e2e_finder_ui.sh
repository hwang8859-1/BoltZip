#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_UNDER_TEST="${1:-$ROOT_DIR/dist/BoltZip.app}"
CLI="$APP_UNDER_TEST/Contents/Helpers/boltzip"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
DIAG_DIR="$HOME/Library/Logs/DiagnosticReports"

if [ ! -d "$APP_UNDER_TEST" ]; then
    echo "FAIL: Missing app bundle at $APP_UNDER_TEST"
    exit 1
fi

HAD_SYSTEM_APP=0
if [ -d "/Applications/BoltZip.app" ] && [ "$APP_UNDER_TEST" != "/Applications/BoltZip.app" ]; then
    HAD_SYSTEM_APP=1
    "$LSREG" -u /Applications/BoltZip.app >/dev/null 2>&1 || true
fi
"$LSREG" -f "$APP_UNDER_TEST" >/dev/null 2>&1 || true

WORK="$(mktemp -d "${TMPDIR:-/tmp}/boltzip-ui-e2e.XXXXXX")"
count_crash_ips() {
    if [ -d "$DIAG_DIR" ]; then
        find "$DIAG_DIR" -maxdepth 1 -name 'BoltZipApp-*.ips' 2>/dev/null | wc -l | tr -d ' '
    else
        echo 0
    fi
}
BEFORE_IPS="$(count_crash_ips)"

cleanup() {
    pkill -x BoltZipApp >/dev/null 2>&1 || true
    rm -rf "$WORK"
    if [ "$HAD_SYSTEM_APP" -eq 1 ]; then
        "$LSREG" -u "$APP_UNDER_TEST" >/dev/null 2>&1 || true
        "$LSREG" -f /Applications/BoltZip.app >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

url_encode() {
    python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

pkill -x BoltZipApp >/dev/null 2>&1 || true
sleep 0.3

mkdir -p "$WORK/src/sub" "$WORK/pair_a" "$WORK/pair_b"
echo "hello ui e2e" > "$WORK/src/hello.txt"
echo "nested" > "$WORK/src/sub/world.txt"
echo "file a" > "$WORK/pair_a/a.txt"
echo "file b" > "$WORK/pair_b/b.txt"
"$CLI" a "$WORK/enc.zip" "$WORK/src" --password 123456 --aes256 >/dev/null

ENC_SRC="$(url_encode "$WORK/src")"
ENC_PAIR_A="$(url_encode "$WORK/pair_a")"
ENC_PAIR_B="$(url_encode "$WORK/pair_b")"
ENC_SRC_ZIP="$(url_encode "$WORK/src.zip")"
ENC_SRC_TZST="$(url_encode "$WORK/src.tar.zst")"
ENC_PACK_SUB="$(url_encode "$WORK/pack_sub.zip")"
ENC_SECRET_ZIP="$(url_encode "$WORK/enc.zip")"

echo "==> [E2E 1/5] HUD quick compress actions (compressZip, compressTarZst, compress7z)..."
for pair in "compressZip|.zip" "compressTarZst|.tar.zst" "compress7z|.7z"; do
    op="${pair%%|*}"
    ext="${pair#*|}"
    rm -f "$WORK/src$ext"
    open -a "$APP_UNDER_TEST" "boltzip://hud?op=${op}&path=${ENC_SRC}"
    sleep 2.8
    test -f "$WORK/src$ext"
    echo "  PASS $op -> src$ext"
    pkill -x BoltZipApp >/dev/null 2>&1 || true
    sleep 0.3
done

echo "==> [E2E 2/5] HUD compressEachZip multi-item queued action..."
open -a "$APP_UNDER_TEST" "boltzip://hud?op=compressEachZip&path=${ENC_PAIR_A}&path=${ENC_PAIR_B}"
sleep 2.8
test -f "$WORK/pair_a.zip" && test -f "$WORK/pair_b.zip"
echo "  PASS compressEachZip -> pair_a.zip & pair_b.zip"
pkill -x BoltZipApp >/dev/null 2>&1 || true
sleep 0.3

echo "==> [E2E 3/5] HUD extract actions (smartExtract, extractSubfolder, encrypted prompt stay-alive)..."
rm -rf "$WORK/src"
open -a "$APP_UNDER_TEST" "boltzip://hud?op=smartExtract&path=${ENC_SRC_ZIP}"
sleep 2.6
grep -q "hello ui e2e" "$WORK/src/hello.txt"
echo "  PASS smartExtract"
pkill -x BoltZipApp >/dev/null 2>&1 || true
sleep 0.3

cp "$WORK/src.zip" "$WORK/pack_sub.zip"
open -a "$APP_UNDER_TEST" "boltzip://hud?op=extractSubfolder&path=${ENC_PACK_SUB}"
sleep 2.6
grep -q "hello ui e2e" "$WORK/pack_sub/src/hello.txt"
echo "  PASS extractSubfolder"
pkill -x BoltZipApp >/dev/null 2>&1 || true
sleep 0.3

open -a "$APP_UNDER_TEST" "boltzip://hud?op=smartExtract&path=${ENC_SECRET_ZIP}"
sleep 1.4
pgrep -x BoltZipApp >/dev/null
echo "  PASS encrypted smartExtract password prompt stayed alive"
pkill -x BoltZipApp >/dev/null 2>&1 || true
sleep 0.3

echo "==> [E2E 4/5] Cold & warm workspace Finder URLs (open, openWorkspace, compressWizard, testIntegrity)..."
for query in \
    "op=open&path=${ENC_SRC_ZIP}" \
    "op=openWorkspace" \
    "op=compressWizard&path=${ENC_SRC}" \
    "op=testIntegrity&path=${ENC_SRC_ZIP}"
do
    pkill -x BoltZipApp >/dev/null 2>&1 || true
    sleep 0.3
    open -a "$APP_UNDER_TEST" "boltzip://finder?${query}"
    sleep 1.6
    pgrep -x BoltZipApp >/dev/null
    echo "  PASS cold ${query%%&*}"
done

open -a "$APP_UNDER_TEST" "boltzip://finder?op=open&path=${ENC_SRC_TZST}"
sleep 1.0
pgrep -x BoltZipApp >/dev/null
echo "  PASS warm op=open"
pkill -x BoltZipApp >/dev/null 2>&1 || true

echo "==> [E2E 5/5] Verifying zero new DiagnosticReports crash files..."
sleep 0.6
AFTER_IPS="$(count_crash_ips)"
if [ "$AFTER_IPS" -gt "$BEFORE_IPS" ]; then
    echo "FAIL: New BoltZipApp crash reports detected ($BEFORE_IPS -> $AFTER_IPS)!"
    find "$DIAG_DIR" -maxdepth 1 -name 'BoltZipApp-*.ips' 2>/dev/null | head -n 5
    exit 1
fi

echo "E2E_FINDER_UI_ALL_OK (ips baseline=$BEFORE_IPS, after=$AFTER_IPS)"
