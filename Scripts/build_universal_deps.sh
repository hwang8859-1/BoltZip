#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Vendor/Compression"
INC_DIR="$OUT_DIR/include"
LIB_DIR="$OUT_DIR/lib"
MIN_MACOS="12.0"
SDK_PATH="$(xcrun --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"

ZSTD_VER="1.5.7"
ZSTD_URL="https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz"
ZSTD_SHA256="37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3"

XZ_VER="5.8.4"
XZ_URL="https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz"
XZ_SHA256="0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9"

LZ4_VER="1.11.1"
LZ4_URL="https://github.com/lz4/lz4/archive/refs/tags/v1.11.1.tar.gz"
LZ4_SHA256="683fed08a844ad012196381e40badf80c0bbe4962959761416d41c9e67d77ec7"

LIBARCHIVE_VER="3.7.7"
LIBARCHIVE_URL="https://github.com/libarchive/libarchive/releases/download/v3.7.7/libarchive-3.7.7.tar.gz"
LIBARCHIVE_SHA256="4cc540a3e9a1eebdefa1045d2e4184831100667e6d7d5b315bb1cbc951f8ddff"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boltzip-deps.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

fetch_and_verify() {
    local name="$1"
    local url="$2"
    local expected_sha="$3"
    local dest="$4"

    echo "==> Fetching $name..."
    curl -fsSL "$url" -o "$dest"
    local actual_sha
    actual_sha="$(shasum -a 256 "$dest" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "ERROR: SHA256 mismatch for $name (expected $expected_sha, got $actual_sha)" >&2
        exit 1
    fi
}

rm -rf "$OUT_DIR"
mkdir -p "$INC_DIR" "$LIB_DIR" "$WORK_DIR/src" "$WORK_DIR/stage"

# 1. Zstandard (multithreaded static lib)
fetch_and_verify "zstd-$ZSTD_VER" "$ZSTD_URL" "$ZSTD_SHA256" "$WORK_DIR/zstd.tar.gz"
tar -xzf "$WORK_DIR/zstd.tar.gz" -C "$WORK_DIR/src"
ZSTD_SRC="$WORK_DIR/src/zstd-$ZSTD_VER"

for arch in arm64 x86_64; do
    echo "==> Building zstd ($arch, minOS $MIN_MACOS)..."
    cp -R "$ZSTD_SRC" "$WORK_DIR/zstd-$arch"
    make -C "$WORK_DIR/zstd-$arch/lib" -j"$JOBS" libzstd.a \
        CC="xcrun clang" \
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -isysroot $SDK_PATH -O3 -fPIC" \
        MOREFLAGS="-DZSTD_MULTITHREAD -pthread" \
        HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0
    cp "$WORK_DIR/zstd-$arch/lib/libzstd.a" "$WORK_DIR/stage/libzstd-$arch.a"
done

lipo -create \
    "$WORK_DIR/stage/libzstd-arm64.a" \
    "$WORK_DIR/stage/libzstd-x86_64.a" \
    -output "$LIB_DIR/libzstd.a"
cp "$ZSTD_SRC/lib/zstd.h" "$ZSTD_SRC/lib/zstd_errors.h" "$ZSTD_SRC/lib/zdict.h" "$INC_DIR/"

# 2. XZ Utils / liblzma (POSIX multithreaded static lib)
fetch_and_verify "xz-$XZ_VER" "$XZ_URL" "$XZ_SHA256" "$WORK_DIR/xz.tar.gz"
tar -xzf "$WORK_DIR/xz.tar.gz" -C "$WORK_DIR/src"
XZ_SRC="$WORK_DIR/src/xz-$XZ_VER"

for arch in arm64 x86_64; do
    echo "==> Building xz / liblzma ($arch, minOS $MIN_MACOS)..."
    mkdir -p "$WORK_DIR/xz-build-$arch" "$WORK_DIR/xz-prefix-$arch"
    (
        cd "$WORK_DIR/xz-build-$arch"
        "$XZ_SRC/configure" \
            --host="${arch}-apple-darwin" \
            --prefix="$WORK_DIR/xz-prefix-$arch" \
            --enable-static \
            --disable-shared \
            --disable-xz \
            --disable-xzdec \
            --disable-lzmadec \
            --disable-lzmainfo \
            --disable-scripts \
            --disable-doc \
            --disable-nls \
            --enable-threads=posix \
            CC="xcrun clang -arch $arch -mmacosx-version-min=$MIN_MACOS -isysroot $SDK_PATH" \
            CFLAGS="-O3 -fPIC" >/dev/null
        make -j"$JOBS" install >/dev/null
    )
    cp "$WORK_DIR/xz-prefix-$arch/lib/liblzma.a" "$WORK_DIR/stage/liblzma-$arch.a"
done

lipo -create \
    "$WORK_DIR/stage/liblzma-arm64.a" \
    "$WORK_DIR/stage/liblzma-x86_64.a" \
    -output "$LIB_DIR/liblzma.a"
cp "$WORK_DIR/xz-prefix-arm64/include/lzma.h" "$INC_DIR/"
cp -R "$WORK_DIR/xz-prefix-arm64/include/lzma" "$INC_DIR/"

# 3. LZ4 (static lib)
fetch_and_verify "lz4-$LZ4_VER" "$LZ4_URL" "$LZ4_SHA256" "$WORK_DIR/lz4.tar.gz"
tar -xzf "$WORK_DIR/lz4.tar.gz" -C "$WORK_DIR/src"
LZ4_SRC="$WORK_DIR/src/lz4-$LZ4_VER"

for arch in arm64 x86_64; do
    echo "==> Building lz4 ($arch, minOS $MIN_MACOS)..."
    cp -R "$LZ4_SRC" "$WORK_DIR/lz4-$arch"
    make -C "$WORK_DIR/lz4-$arch/lib" -j"$JOBS" liblz4.a \
        CC="xcrun clang" \
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -isysroot $SDK_PATH -O3 -fPIC"
    cp "$WORK_DIR/lz4-$arch/lib/liblz4.a" "$WORK_DIR/stage/liblz4-$arch.a"
done

lipo -create \
    "$WORK_DIR/stage/liblz4-arm64.a" \
    "$WORK_DIR/stage/liblz4-x86_64.a" \
    -output "$LIB_DIR/liblz4.a"
cp "$LZ4_SRC/lib/lz4.h" "$LZ4_SRC/lib/lz4frame.h" "$LZ4_SRC/lib/lz4hc.h" "$INC_DIR/"

# 4. libarchive (static Universal lib with RAR/RAR5/7z/ISO/CAB/XAR + CommonCrypto AES)
fetch_and_verify "libarchive-$LIBARCHIVE_VER" "$LIBARCHIVE_URL" "$LIBARCHIVE_SHA256" "$WORK_DIR/libarchive.tar.gz"
tar -xzf "$WORK_DIR/libarchive.tar.gz" -C "$WORK_DIR/src"
LIBARCHIVE_SRC="$WORK_DIR/src/libarchive-$LIBARCHIVE_VER"

for arch in arm64 x86_64; do
    echo "==> Building libarchive ($arch, minOS $MIN_MACOS)..."
    mkdir -p "$WORK_DIR/la-build-$arch" "$WORK_DIR/la-prefix-$arch"
    (
        cd "$WORK_DIR/la-build-$arch"
        "$LIBARCHIVE_SRC/configure" \
            --host="${arch}-apple-darwin" \
            --prefix="$WORK_DIR/la-prefix-$arch" \
            --enable-static \
            --disable-shared \
            --disable-bsdtar \
            --disable-bsdcat \
            --disable-bsdcpio \
            --disable-bsdunzip \
            --without-xml2 \
            --without-expat \
            --without-openssl \
            --without-nettle \
            --without-lzo2 \
            --without-libb2 \
            --with-zlib \
            --with-bz2lib \
            --with-lzma \
            --with-zstd \
            --with-lz4 \
            CC="xcrun clang -arch $arch -mmacosx-version-min=$MIN_MACOS -isysroot $SDK_PATH" \
            CPPFLAGS="-I$INC_DIR" \
            CFLAGS="-O3 -fPIC" \
            LDFLAGS="-L$LIB_DIR" >/dev/null
        make -j"$JOBS" install >/dev/null
    )
    cp "$WORK_DIR/la-prefix-$arch/lib/libarchive.a" "$WORK_DIR/stage/libarchive-$arch.a"
done

lipo -create \
    "$WORK_DIR/stage/libarchive-arm64.a" \
    "$WORK_DIR/stage/libarchive-x86_64.a" \
    -output "$LIB_DIR/libarchive.a"
cp "$WORK_DIR/la-prefix-arm64/include/archive.h" "$WORK_DIR/la-prefix-arm64/include/archive_entry.h" "$INC_DIR/"

echo "==> Universal static libraries created in $OUT_DIR:"
lipo -info "$LIB_DIR/libzstd.a" "$LIB_DIR/liblzma.a" "$LIB_DIR/liblz4.a" "$LIB_DIR/libarchive.a"
ls -lh "$LIB_DIR"
