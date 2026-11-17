# Changelog

All notable changes to **BoltZip** will be documented in this file.

## [0.9.0] - 2026-11-17

### Added & Improved
- **macOS 14.0+ & Universal Binary (`arm64` + `x86_64`) Support**:
  - Lowered minimum deployment target from `27.2` to **macOS 14.0 (Sonoma)** for `BoltZip.app`, `boltzip` CLI, and `BoltZipFinderSync.appex`.
  - Added [`Scripts/build_universal_deps.sh`](Scripts/build_universal_deps.sh) to cross-compile Universal (`arm64` + `x86_64`, `minOS 14.0`) static archives (`libzstd.a`, `liblzma.a`, `liblz4.a`) into `Vendor/Compression/`, enabling zero-Homebrew Universal builds for both Apple Silicon and Intel Macs.
  - Updated [`Scripts/build_app.sh`](Scripts/build_app.sh) to produce Universal `BoltZip.app`, Universal `BoltZip-0.9.0-macOS-universal.zip`, clean source archives (`BoltZip-0.9.0-source.tar.gz` / `.zip`), and `SHA256SUMS`.
- **Automatic Liquid Glass Fallback on Older macOS**:
  - Wrapped all `macOS 26.0+` Liquid Glass modifiers (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, `.scrollEdgeEffectStyle`, `.sharedBackgroundVisibility`) and `macOS 15.0+` window modifiers inside `GlassDesignSystem.swift` compatibility helpers.
  - On macOS 14 & 15, glass effects and window translucency are automatically disabled in favor of clean native solid surfaces and standard buttons, and Liquid Glass preference toggles are hidden.
- **Highlighted `.DS_Store` & macOS Junk Auto-Removal**:
  - Promoted automatic `.DS_Store` / `__MACOSX` / `._*` cleanup into the welcome screen feature card, 4-language READMEs, and showcase feature grid.
- **Showcase Fix**:
  - Fixed duplicated `siteI18n` blocks inside `showcase/app.js` and refreshed showcase metadata for `v0.9.0` and Universal `macOS 14.0+`.

## [0.1.0] - 2026-11-17

### Added
- **Open-Source Multi-Codec Core (`CBoltCompression` + `BoltZipCore`)**:
  - Statically linked `zlib` (`1.2.12`), `libzstd` (`1.5.7`), `liblzma` (`5.8.4`), `libbz2` (`1.0.8`), and `liblz4` (`1.11.1`) with zero external runtime dylib dependencies.
  - Pure Swift ZIP/ZIP64 reader & writer, split-volume `.z01/.z02/.../.zip` support, zero-recompression in-place ZIP editing (add, rename, delete, create folder), and hardware-accelerated CRC32 verification.
  - WinZip AE-2 / AE-1 AES-256 encryption (`PBKDF2-HMAC-SHA1` + `AES-256-CTR` + 10-byte `HMAC-SHA1`) and legacy `ZipCrypto` compatibility.
  - USTAR / PAX TAR + `.tar.zst` / `.tar.xz` / `.tar.gz` / `.tar.bz2` / `.tar.lz4`, plus macOS `libarchive` bridge for `.7z` / `.iso` / `.cab` / `.xar`.
  - Automatic CJK filename encoding detection (`GB18030/GBK`, `Big5`, `Shift-JIS`, `EUC-KR`, `UTF-8`), `.DS_Store` / `__MACOSX` / `._*` junk filtering, and Smart Extract.
- **Native macOS 27.3 Liquid Glass Desktop App (`BoltZipApp`)**:
  - Windows-Zip-class archive explorer with folder tree, breadcrumbs, search, sorting, Quick Look preview (`Double-Click` / `Space`), drag-to-add inside ZIPs, full context menus, and About window with project Slogan.
  - Dark / Light / System appearance modes, adjustable Liquid Glass translucency & window opacity slider, modular panel visibility toggles, and compact responsive mini-window mode (`380 × 285`).
  - Idiomatic multi-language UI (`Follow System`, `简体中文`, `繁體中文`, `English`, `日本語`).
- **Top-Level Finder Context Menu (`BoltZipFinderSync.appex`)**:
  - Native sandboxed Finder Sync extension providing top-level **`Bolt ›`** submenu with Smart Extract, Extract to Folder, Open in BoltZip, Verify Integrity, and 1-click ZIP / TAR.ZST / 7z / Encrypted compression.
- **CLI, Showcase & Developer Docs**:
  - `boltzip` CLI (`a`, `x`, `l`, `t`, `bench`, `engines`, `version`), interactive multi-language web showcase (`showcase/index.html`), `AGENTS.md`, and 4-language READMEs.
