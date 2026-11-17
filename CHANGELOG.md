# Changelog

All notable changes to **BoltZip** will be documented in this file.

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
