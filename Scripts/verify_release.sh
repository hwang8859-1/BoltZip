#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CANDIDATE=0
if [ "${1:-}" = "--candidate" ]; then
    CANDIDATE=1
    shift
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: ./Scripts/verify_release.sh [--candidate]" >&2
    exit 2
fi

APP_VERSION="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/BoltZipCore/Models/BoltZipVersion.swift | head -n1)"
APP_BUILD="$(sed -n 's/.*build = "\(.*\)".*/\1/p' Sources/BoltZipCore/Models/BoltZipVersion.swift | head -n1)"
DIST_DIR="$ROOT_DIR/dist"
DMG="$DIST_DIR/BoltZip-${APP_VERSION}-macOS-arm64.dmg"
SUMS="$DIST_DIR/BoltZip-${APP_VERSION}-SHA256SUMS.txt"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boltzip-verify.XXXXXX")"
MOUNT_DIR="$VERIFY_DIR/package"
mkdir "$MOUNT_DIR" "$VERIFY_DIR/regression"
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null || return
    fi
    rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

echo "==> [1/6] Verifying and mounting the delivery DMG..."
test -n "$APP_VERSION" && test -n "$APP_BUILD"
test -f "$DMG" && test -f "$SUMS"
awk -v dmg="$(basename "$DMG")" '$2 == dmg { found++ } END { exit found != 1 }' "$SUMS"
(cd "$DIST_DIR" && shasum -a 256 -c "$(basename "$SUMS")")
hdiutil verify "$DMG"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" "$DMG" >/dev/null
MOUNTED=1

APP_DIR="$MOUNT_DIR/BoltZip.app"
CLI="$APP_DIR/Contents/Helpers/boltzip"
SEVEN_ZIP="$APP_DIR/Contents/Helpers/7zz"
DOCK_PLUGIN="$APP_DIR/Contents/PlugIns/BoltZipDockTile.plugin"

echo "==> [2/6] Verifying mounted bundle version, signature, entitlements & Info.plist..."
codesign --verify --deep --strict "$APP_DIR"
codesign -d --entitlements - "$APP_DIR/Contents/PlugIns/BoltZipFinderSync.appex" 2>&1 | grep -q "com.apple.security.app-sandbox"
plutil -lint \
    "$APP_DIR/Contents/Info.plist" \
    "$APP_DIR/Contents/PlugIns/BoltZipFinderSync.appex/Contents/Info.plist" \
    "$DOCK_PLUGIN/Contents/Info.plist"
for PLIST in "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/PlugIns/BoltZipFinderSync.appex/Contents/Info.plist" "$DOCK_PLUGIN/Contents/Info.plist"; do
    if [ "$(plutil -extract CFBundleVersion raw "$PLIST")" != "$APP_BUILD" ]; then
        echo "FAIL: The mounted DMG contains an unexpected application version or build: $PLIST" >&2
        exit 1
    fi
done
# The Dock tile bundle publishes a build number only.
for PLIST in "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/PlugIns/BoltZipFinderSync.appex/Contents/Info.plist"; do
    if [ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" != "$APP_VERSION" ]; then
        echo "FAIL: The mounted DMG contains an unexpected application version or build: $PLIST" >&2
        exit 1
    fi
done
test "$(plutil -extract NSDockTilePlugIn raw "$APP_DIR/Contents/Info.plist")" = "$(basename "$DOCK_PLUGIN")"
test -x "$DOCK_PLUGIN/Contents/MacOS/BoltZipDockTile"
test -x "$SEVEN_ZIP"
codesign --verify --strict "$SEVEN_ZIP"
test -s "$APP_DIR/Contents/Resources/Licenses/7-Zip/License.txt"
test -s "$APP_DIR/Contents/Resources/Licenses/7-Zip/LGPL-2.1.txt"
test -s "$APP_DIR/Contents/Resources/Licenses/7-Zip/UPSTREAM.txt"
test -s "$APP_DIR/Contents/Resources/BoltZipDockLight.png"
test -s "$APP_DIR/Contents/Resources/BoltZipDockDark.png"

echo "==> [3/6] Verifying zero third-party Homebrew dylib dependencies..."
for BIN in "$APP_DIR/Contents/MacOS/BoltZipApp" "$CLI" "$SEVEN_ZIP"; do
    if otool -L "$BIN" | grep -qE "homebrew|/usr/local/(opt|lib)"; then
        echo "FAIL: Non-system dylib dependency found in $BIN"
        otool -L "$BIN"
        exit 1
    fi
done

echo "==> [4/6] Running packaged CLI regression (engines, threads, AES-256 ZIP and 7z, .DS_Store, symlinks, in-place zip edit, flat extract, json)..."
TMP_CLI="$VERIFY_DIR/regression"

mkdir -p "$TMP_CLI/src/sub"
echo "boltzip v${APP_VERSION} cli regression" > "$TMP_CLI/src/sub/hello.txt"
echo "extra doc" > "$TMP_CLI/extra.txt"
ln -s "sub/hello.txt" "$TMP_CLI/src/hello_link"
touch "$TMP_CLI/src/.DS_Store"

"$CLI" version | grep -q "$APP_VERSION"
"$CLI" engines >/dev/null
"$CLI" bench --threads 2 --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["results"]) >= 5'

"$CLI" a "$TMP_CLI/test.zip" "$TMP_CLI/src" --comment "Verified ${APP_VERSION}" --threads 2
if "$CLI" a "$TMP_CLI/rejected.zip" "$TMP_CLI/extra.txt" --split 18446744073709551615 > "$TMP_CLI/split-error.txt" 2>&1; then
    echo "FAIL: An out-of-range split size was accepted" >&2
    exit 1
fi
grep -q 'Invalid --split size' "$TMP_CLI/split-error.txt"
test ! -e "$TMP_CLI/rejected.zip"
"$CLI" a "$TMP_CLI/test.tar.zst" "$TMP_CLI/src" --algo zstd
"$CLI" a "$TMP_CLI/test.7z" "$TMP_CLI/src" --algo xz
"$CLI" a "$TMP_CLI/enc.zip" "$TMP_CLI/src" --password "secret!${APP_VERSION}" --aes256
"$CLI" a "$TMP_CLI/enc.7z" "$TMP_CLI/src" --password "secret!${APP_VERSION}" --encrypt-filenames
if "$CLI" l "$TMP_CLI/enc.7z" > "$TMP_CLI/locked.txt" 2>&1 || grep -q "hello.txt" "$TMP_CLI/locked.txt"; then
    echo "FAIL: 7z encrypted file names were accessible without a password"
    exit 1
fi
"$CLI" l "$TMP_CLI/enc.7z" --password "secret!${APP_VERSION}" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert any(e["path"] == "src/sub/hello.txt" for e in d["entries"])'
"$CLI" t "$TMP_CLI/enc.7z" --password "secret!${APP_VERSION}" >/dev/null
"$CLI" x "$TMP_CLI/enc.7z" "$TMP_CLI/unlocked" --mode here --password "secret!${APP_VERSION}"
cmp "$TMP_CLI/src/sub/hello.txt" "$TMP_CLI/unlocked/src/sub/hello.txt"
test -L "$TMP_CLI/unlocked/src/hello_link"

"$CLI" add "$TMP_CLI/test.zip" "$TMP_CLI/extra.txt"
"$CLI" mkdir "$TMP_CLI/test.zip" "docs/"
"$CLI" mv "$TMP_CLI/test.zip" "extra.txt" "docs/extra_moved.txt"
"$CLI" l "$TMP_CLI/test.zip" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["comment"].startswith("Verified "); assert any(e["path"]=="docs/extra_moved.txt" for e in d["entries"])'
"$CLI" rm "$TMP_CLI/test.zip" "docs/extra_moved.txt"
"$CLI" t "$TMP_CLI/test.zip" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["failedCount"]==0'
"$CLI" t "$TMP_CLI/enc.zip" --password "secret!${APP_VERSION}" >/dev/null
if "$CLI" t "$TMP_CLI/enc.zip" --json > "$TMP_CLI/unverified.json"; then
    echo "FAIL: An encrypted ZIP returned success without a password" >&2
    exit 1
fi
python3 - "$TMP_CLI/unverified.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    assert json.load(stream)["skippedEncryptedCount"] > 0
PY

cp "$TMP_CLI/test.zip" "$TMP_CLI/standalone.z01"
"$CLI" t "$TMP_CLI/standalone.z01" >/dev/null
mkdir "$TMP_CLI/self-source"
echo "nested archive name" > "$TMP_CLI/self-source/self.zip"
"$CLI" a "$TMP_CLI/self.zip" "$TMP_CLI/self-source/self.zip"
cp "$TMP_CLI/self.zip" "$TMP_CLI/self-before"
if "$CLI" x "$TMP_CLI/self.zip" "$TMP_CLI" --mode here; then
    echo "FAIL: Extraction would replace its own input" >&2
    exit 1
fi
cmp "$TMP_CLI/self.zip" "$TMP_CLI/self-before"

"$CLI" x "$TMP_CLI/test.zip" "$TMP_CLI/out" --mode smart --overwrite overwrite
grep -q "boltzip v${APP_VERSION} cli regression" "$TMP_CLI/out/test/src/sub/hello.txt"
test ! -e "$TMP_CLI/out/test/src/.DS_Store"
test -L "$TMP_CLI/out/test/src/hello_link"

"$CLI" e "$TMP_CLI/test.tar.zst" "$TMP_CLI/flat" --overwrite rename
grep -q "boltzip v${APP_VERSION} cli regression" "$TMP_CLI/flat/hello.txt"

python3 -c 'import os,sys; open(sys.argv[1],"wb").write(os.urandom(1536 * 1024))' "$TMP_CLI/split_payload.bin"
"$CLI" a "$TMP_CLI/split7z.7z" "$TMP_CLI/split_payload.bin" --algo store --split 1 --password "secret!${APP_VERSION}" --encrypt-filenames
test -f "$TMP_CLI/split7z.7z.001" && test -f "$TMP_CLI/split7z.7z.002"
"$CLI" l "$TMP_CLI/split7z.7z.002" --password "secret!${APP_VERSION}" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["isSplitVolume"] and any(e["path"] == "split_payload.bin" for e in d["entries"])'
"$CLI" t "$TMP_CLI/split7z.7z.001" --password "secret!${APP_VERSION}" >/dev/null
"$SEVEN_ZIP" t -bso0 -bse2 -bsp0 -p"secret!${APP_VERSION}" -- "$TMP_CLI/split7z.7z.001"
"$CLI" x "$TMP_CLI/split7z.7z.001" "$TMP_CLI/split7z_out" --mode here --password "secret!${APP_VERSION}"
cmp "$TMP_CLI/split_payload.bin" "$TMP_CLI/split7z_out/split_payload.bin"
mv "$TMP_CLI/split7z.7z.002" "$TMP_CLI/split7z.7z.002.bak"
if "$CLI" l "$TMP_CLI/split7z.7z.001" --password "secret!${APP_VERSION}" > "$TMP_CLI/split7z-missing.txt" 2>&1; then
    echo "FAIL: Incomplete split 7z succeeded with missing volume" >&2
    exit 1
fi
grep -q 'split7z.7z.002' "$TMP_CLI/split7z-missing.txt"

# Standalone .gz / .xz streams, --password-stdin, --exclude, 7z edit, recover, convert, and isolated preset store
echo "standalone payload ${APP_VERSION}" > "$TMP_CLI/single.txt"
"$CLI" a "$TMP_CLI/single.txt.gz" "$TMP_CLI/single.txt" --level 6
"$CLI" a "$TMP_CLI/single.txt.xz" "$TMP_CLI/single.txt" --level 4 --threads 2
"$CLI" t "$TMP_CLI/single.txt.gz" >/dev/null
"$CLI" t "$TMP_CLI/single.txt.xz" >/dev/null
"$CLI" x "$TMP_CLI/single.txt.gz" "$TMP_CLI/gz_out" --mode here
cmp "$TMP_CLI/single.txt" "$TMP_CLI/gz_out/single.txt"

mkdir -p "$TMP_CLI/ex_src/.git" "$TMP_CLI/ex_src/sub"
echo "keep" > "$TMP_CLI/ex_src/sub/keep.txt"
echo "skip" > "$TMP_CLI/ex_src/skip.tmp"
echo "gitcfg" > "$TMP_CLI/ex_src/.git/config"
printf "stdin!secret\n" | "$CLI" a "$TMP_CLI/stdin_enc.zip" "$TMP_CLI/ex_src" --exclude "*.tmp,.git" --password-stdin --aes256
printf "stdin!secret\n" | "$CLI" l "$TMP_CLI/stdin_enc.zip" --password-stdin --json | python3 -c 'import json,sys; p={e["path"] for e in json.load(sys.stdin)["entries"]}; assert "ex_src/sub/keep.txt" in p and "ex_src/skip.tmp" not in p and "ex_src/.git/config" not in p'

"$CLI" add "$TMP_CLI/test.7z" "$TMP_CLI/extra.txt"
"$CLI" mkdir "$TMP_CLI/test.7z" "docs7z/"
"$CLI" mv "$TMP_CLI/test.7z" "extra.txt" "docs7z/moved.txt"
"$CLI" l "$TMP_CLI/test.7z" --json | python3 -c 'import json,sys; p={e["path"] for e in json.load(sys.stdin)["entries"]}; assert "docs7z/moved.txt" in p'
"$CLI" rm "$TMP_CLI/test.7z" "docs7z/moved.txt"
"$CLI" t "$TMP_CLI/test.7z" >/dev/null

python3 - "$TMP_CLI/test.zip" "$TMP_CLI/damaged_no_cd.zip" <<'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
cd = data.find(b"PK\x01\x02")
assert cd > 0
pathlib.Path(sys.argv[2]).write_bytes(data[:cd])
PY
"$CLI" recover "$TMP_CLI/damaged_no_cd.zip" "$TMP_CLI/recovered_cli.zip" >/dev/null
"$CLI" t "$TMP_CLI/recovered_cli.zip" >/dev/null

mkdir -p "$TMP_CLI/converted_cli" "$TMP_CLI/fake_home"
"$CLI" convert "$TMP_CLI/test.zip" --to "$TMP_CLI/converted_cli" --format tar.zst --name-pattern "{name}_conv" >/dev/null
test -f "$TMP_CLI/converted_cli/test_conv.tar.zst"
"$CLI" t "$TMP_CLI/converted_cli/test_conv.tar.zst" >/dev/null

HOME="$TMP_CLI/fake_home" "$CLI" preset save "ci-zstd" --format tar.zst --algo zstd --level 5 --exclude "*.tmp" --name-pattern "{name}_{date}" --quick >/dev/null
HOME="$TMP_CLI/fake_home" "$CLI" preset list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d)==1 and d[0]["name"]=="ci-zstd"'
HOME="$TMP_CLI/fake_home" "$CLI" preset rm "ci-zstd" >/dev/null

echo "==> [5/6] Validating showcase JS syntax, 4-language i18n keys & download references..."
if command -v node >/dev/null 2>&1; then
    node --check showcase/app.js
elif [ -x /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc ]; then
    if /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -e "load('showcase/app.js');" 2>&1 | grep -qi "SyntaxError"; then
        echo "FAIL: showcase/app.js syntax error"
        exit 1
    fi
fi

python3 - "$APP_VERSION" "$CANDIDATE" <<'PY'
import pathlib, re, sys

ver = sys.argv[1]
candidate = sys.argv[2] == "1"
html = pathlib.Path("showcase/index.html").read_text(encoding="utf-8")
js = pathlib.Path("showcase/app.js").read_text(encoding="utf-8")

keys = set(re.findall(r'data-i18n(?:-html|-placeholder)?="([^"]+)"', html))
langs = ["zh-Hans", "zh-Hant", "en", "ja"]
for i, lang in enumerate(langs):
    start = js.index(f'"{lang}": {{')
    end = js.index(f'"{langs[i + 1]}": {{') if i + 1 < len(langs) else js.index("let currentLang")
    block = js[start:end]
    missing = [k for k in sorted(keys) if f"{k}:" not in block]
    assert not missing, f"Missing showcase i18n keys in {lang}: {missing}"

downloads = set(re.findall(r'href="\./downloads/([^"]+)"', html))
current_assets = {d for d in downloads if ver in d}
assert candidate or current_assets, f"No downloads referencing v{ver} found in showcase/index.html"
for asset in sorted(current_assets):
    p = pathlib.Path("dist") / asset
    assert p.is_file(), f"Missing referenced v{ver} artifact in dist/: {p}"
print(f"SHOWCASE_VERIFIED_OK ({len(keys)} keys x 4 langs, {len(current_assets)} v{ver} assets)")
PY

echo "==> [6/6] Scanning Sources, showcase, Scripts for personal path leaks..."
LEAK_NEEDLE="/Us""ers/"
if grep -rn "$LEAK_NEEDLE" Sources showcase Scripts; then
    echo "FAIL: Personal path leak detected!"
    exit 1
fi

echo "VERIFY_RELEASE_ALL_OK (v${APP_VERSION})"
