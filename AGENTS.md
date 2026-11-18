# AGENTS.md — Contributor & AI Agent Guide for BoltZip

Welcome! This file gives human contributors and AI coding agents an accurate map of **BoltZip**, its architecture, build/test workflows, and critical engineering invariants.

## 1. Project Overview

**BoltZip (`legacy/macos-12`, v0.9.1)** is an open-source macOS archive manager (targeting **macOS 12.0+ / Universal `arm64` + `x86_64`**, with native Liquid Glass on macOS 26+ and clean non-glass fallback on macOS 12–15) inspired by classic Windows archive tools (7-Zip / WinZip / Bandizip), built with **Swift 6**, **SwiftUI + AppKit**, a pure-Swift/C open-source core (`BoltZipCore` + `CBoltCompression`), a CLI (`boltzip`), and a sandboxed Finder Sync Extension (`BoltZipFinderSync`).

- **Repository**: `https://github.com/hwang8859-1/BoltZip.git`
- **License**: MIT ([LICENSE](LICENSE))
- **Toolchain**: Swift 6.0+, Xcode / Command Line Tools with macOS 26+ / 27.2+ SDK, Universal static `zstd`, `xz` (`liblzma`), `lz4`, `libarchive` in `Vendor/Compression/` (regenerable via `Scripts/build_universal_deps.sh`).

---

## 2. Repository Map

```text
BoltZip/
├── Package.swift                        # SwiftPM manifest (CBoltCompression, BoltZipCore, boltzip, BoltZipApp, tests)
├── Scripts/
│   ├── build_app.sh                     # Release Universal (arm64 + x86_64, minOS 12.0) build -> dist/BoltZip.app + BoltZipFinderSync.appex + AppIcon.icns + codesign
│   ├── build_universal_deps.sh          # Cross-compile Universal (arm64 + x86_64, minOS 12.0) static zstd/xz/lz4/libarchive into Vendor/Compression/
│   └── generate_icon.swift              # CoreGraphics procedural 1024x1024 macOS iconset generator
├── Vendor/Compression/                  # Prebuilt Universal (arm64 + x86_64, minOS 12.0) headers & static libs (zstd, xz, lz4, libarchive)
├── Sources/
│   ├── CBoltCompression/                # C wrapper statically linking zlib, libzstd, liblzma, libbz2, liblz4
│   │   ├── include/bolt_compression.h
│   │   └── bolt_compression.c
│   ├── BoltZipCore/                     # Platform-agnostic Swift archive engine (Sendable)
│   │   ├── Models/
│   │   │   ├── ArchiveModels.swift      # Formats, CompressionAlgorithm, EncryptionMethod, Entry, Options
│   │   │   └── BoltZipError.swift
│   │   ├── Codecs/
│   │   │   ├── CompressionCodec.swift   # Swift bridge over CBoltCompression + CRC32
│   │   │   ├── FilenameEncoding.swift   # Auto-detection for UTF-8, GB18030/GBK, Big5, Shift-JIS, EUC-KR, CP437
│   │   │   └── ZipCrypto.swift          # WinZip AE-2/AE-1 AES-256 (CommonCrypto/CryptoKit) + legacy ZipCrypto
│   │   ├── Formats/
│   │   │   ├── ZipBinary.swift          # Little-endian binary readers/writers, DOS dates, extra fields
│   │   │   ├── ZipReader.swift          # ZIP/ZIP64/split-volume reader, decryption, integrity check
│   │   │   ├── ZipWriter.swift          # ZIP/ZIP64 writer, split volumes (.z01/.zip), zero-recompress editing
│   │   │   ├── TarCodec.swift           # Pure Swift USTAR/PAX tar + .tar.{gz,zst,xz,bz2,lz4} + single-stream
│   │   │   └── ExtendedArchiveDriver.swift # .7z / .iso / .cab / .xar bridge via /usr/bin/tar (libarchive)
│   │   └── Engine/
│   │       ├── BoltArchiveSession.swift # High-level BoltArchiveEngine (inspect, extract, create, editZip, test)
│   │       └── BenchmarkRunner.swift    # Multi-codec local throughput & ratio benchmark
│   ├── BoltZipCLI/
│   │   └── main.swift                   # `boltzip` CLI (a, x, l, t, bench, engines)
│   ├── BoltZipFinderSync/
│   │   ├── FinderSync.swift             # Top-level Finder right-click "Bolt >" menu extension (sandboxed .appex)
│   │   └── FinderSync.entitlements
│   └── BoltZipApp/                      # Native macOS Liquid Glass desktop app
│       ├── BoltZipApp.swift             # App entry, NSApplicationDelegate, URL scheme (`boltzip://`) handler
│       ├── Localization/L10n.swift      # Idiomatic multi-language engine (Follow System / zh-Hans / zh-Hant / en / ja)
│       ├── Models/WorkspaceViewModel.swift
│       ├── Services/
│       │   ├── DropHelper.swift
│       │   ├── QuickActionInstaller.swift # pluginkit + lsregister manager for BoltZipFinderSync.appex
│       │   ├── QuickLookPreviewer.swift
│       │   └── WindowStyleConfigurator.swift # NSWindow translucency & background bridge
│       └── Views/                       # WelcomeDropZoneView, MainWindowView, CreateArchiveSheet, ActionSheets, GlassDesignSystem
├── Tests/BoltZipCoreTests/
│   └── BoltZipCoreTests.swift           # End-to-end XCTest suite
└── showcase/                            # Zero-dependency interactive landing page (index.html, styles.css, app.js)
```

---

## 3. Build, Test, and Packaging Commands

```bash
# Run full unit & interoperability test suite
swift test

# Build CLI and run real local codec benchmark
swift run -c release boltzip engines
swift run -c release boltzip bench

# Build self-contained macOS .app bundle + FinderSync extension + AppIcon
./Scripts/build_app.sh
codesign --verify --deep --strict dist/BoltZip.app
open dist/BoltZip.app
```

### Static Linking Note
`Package.swift` links system `libz` and `libbz2` alongside `libiconv` and the Universal (`arm64` + `x86_64`, `minOS 12.0`) static archives in `Vendor/Compression/lib/lib{archive,zstd,lzma,lz4}.a` (with automatic fallback to `/opt/homebrew` or `/usr/local` if `Vendor/Compression` is absent) so `dist/BoltZip.app` and `boltzip` have **zero Homebrew runtime dylib dependencies**. Run `./Scripts/build_universal_deps.sh` to regenerate `Vendor/Compression` from SHA256-verified upstream sources.

---

## 4. Critical Engineering Invariants (Do Not Break)

1. **Swift 6 Strict Concurrency**: The project compiles under Swift 6 (`swift-tools-version: 6.0`). All UI state lives on `@MainActor` (`WorkspaceViewModel`), while heavy archive I/O runs inside `Task.detached` with `Sendable` models (`ArchiveEntry`, `ArchiveListing`, `CreateArchiveOptions`, `ExtractOptions`).
2. **WinZip AE-2 Specification (`ZipCrypto.swift`)**:
   - PBKDF2-HMAC-SHA1 (`1000` iterations) derives encryption key + auth key + 2-byte password verifier.
   - AES-256-CTR uses a **128-bit little-endian counter starting at `1`** (`[1, 0, ..., 0]`).
   - Authentication uses the first 10 bytes of `HMAC-SHA1(ciphertext)`. AE-2 sets header CRC32 to `0` (`skipCRC32 = true` only when `vendorVersion == 2`).
3. **Split-Volume Boundary Alignment (`ZipWriter.swift` / `ZipReader.swift`)**:
   - Always call `sink.ensureRoomBeforeHeader()` before capturing `localDisk` and `localOffset` for Local File Headers, Central Directory, and ZIP64 EOCD.
   - `ZipVolumeAccessor.readSpanning` handles payloads or headers spanning across `.z01`, `.z02`, ..., `.zip`.
4. **In-Place ZIP Editing (`ZipWriter.editArchive`)**:
   - Untouched entries are copied as raw compressed/encrypted payloads without recompression. Keep it zero-recompress!
5. **Path Traversal Guard (`BoltArchiveEngine.safeDestinationURL`)**:
   - Never allow archive entries containing `..` or absolute paths to write outside the extraction root.
6. **FinderSync Extension Signing & IPC**:
   - `BoltZipFinderSync.appex` runs inside App Sandbox (`FinderSync.entitlements`).
   - In `build_app.sh`, sign `.appex` first **with `--entitlements`**, then sign the outer `BoltZip.app` **without `--deep`** so the extension's sandbox entitlements are not stripped.
   - Finder menu clicks dispatch `boltzip://finder?op=...&path=...` URLs back to `BoltZipApp`, where `WindowGroup.handlesExternalEvents(matching: ["*"])` prevents spawning duplicate windows.
7. **Portability & Localization**:
   - **Never** hardcode local user home paths (`/Users/<someone>/...`) in source code, scripts, or `showcase/`. Always resolve relative to `Bundle.main`, current working directory, or repository root.
   - Keep all user-facing UI strings inside `L10n.swift` across all supported languages (`zh-Hans`, `zh-Hant`, `en`, `ja`) with natural, platform-idiomatic phrasing (avoid literal machine-translated wording).

---

## 5. Verification Checklist Before Committing

1. `swift test` passes with 0 failures.
2. `./Scripts/build_app.sh` builds cleanly and `codesign --verify --deep --strict dist/BoltZip.app` passes.
3. `plutil -lint dist/BoltZip.app/Contents/Info.plist dist/BoltZip.app/Contents/PlugIns/BoltZipFinderSync.appex/Contents/Info.plist` outputs `OK`.
4. Check `git status` and `grep -rn "/Users/" Sources showcase Scripts` to ensure no personal paths or build artifacts leak into git.
