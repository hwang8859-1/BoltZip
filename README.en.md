<div align="center">

# BoltZip ⚡

**Lightning-fast archives. Liquid-clear macOS craft.**

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | **English** | [日本語](README.ja.md)

![macOS 27.3+](https://img.shields.io/badge/macOS-27.3%2B%20(arm64)-0ea5e9?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6.0-6366f1?style=flat-square)
![Release v0.1.0](https://img.shields.io/badge/release-v0.1.0-facc15?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

</div>

---

**BoltZip** is an open-source archive manager built natively for **macOS 27.3 (Apple Silicon)**. It pairs the productive, desktop-class archive workflows popularized by Windows tools (7-Zip, WinZip, Bandizip) with macOS’s **Liquid Glass** aesthetic—no more extracting an entire archive just to inspect or edit one file.

## ✨ Highlights

- **Top-Level Finder Context Menu `Bolt ›`**: Powered by a sandboxed native `FinderSync` extension (`BoltZipFinderSync.appex`), quick actions appear directly at the top level of Finder’s right-click menu—never buried under Services:
  - Smart Extract / Extract to Subfolder / Browse in BoltZip / Verify Integrity
  - Instant Compress to `ZIP`, `TAR.ZST (Zstd)`, `7z`, or Encrypted & Split Archive Wizard
- **Browse & Edit Inside Archives**: Double-click or press `Space` to preview entries via macOS Quick Look without full extraction. Navigate folder trees, search/sort, inspect CRC32 & metadata, export selected entries into a new ZIP, and **add, rename, or delete inside ZIP files** with zero recompression of untouched entries.
- **Liquid Glass & Modular UI**:
  - Toggle window translucency and fine-tune background opacity (`25% – 100%`) live from the toolbar or Settings;
  - Independently show/hide home modules (Finder setup banner, feature highlights, recent archives), sidebar summary, and status bar;
  - Shrinks cleanly down to a compact `380 × 285` mini drop window (keeping only the core drop zone at minimal height).
- **Idiomatic Multi-Language Support**: Automatically follows your macOS system language or switches live between **简体中文**, **繁體中文**, **English**, and **日本語**.
- **Pure Open-Source Codec Core**: Statically links `zlib`, `libzstd`, `liblzma`, `libbz2`, and `liblz4` (zero Homebrew runtime dylib dependencies), plus system `libarchive` bridging for `.7z`, `.iso`, `.cab`, and `.xar`.
- **Cross-Platform Fidelity**:
  - **WinZip AE-2 AES-256** encryption (`PBKDF2-HMAC-SHA1` + `AES-256-CTR` + 10-byte `HMAC-SHA1`) and legacy `ZipCrypto`;
  - Automatic detection of `GB18030 / GBK`, `Big5`, `Shift-JIS`, and `EUC-KR` filenames in Windows-created ZIPs;
  - Strips `.DS_Store`, `__MACOSX`, and `._*` metadata by default; supports `.z01/.z02/.../.zip` split volumes and Smart Extract (avoids nested duplicate folders).

## 🚀 Quick Start

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. Run all unit & interoperability tests
swift test

# 2. Build BoltZip.app (includes FinderSync extension, CLI & release zip)
./Scripts/build_app.sh
open dist/BoltZip.app
```

### CLI Usage (`boltzip`)

```bash
swift run -c release boltzip engines
swift run -c release boltzip bench
swift run -c release boltzip a release.zip ./src --algo zstd --aes256 --password YourPassword
swift run -c release boltzip t release.zip --password YourPassword
swift run -c release boltzip x release.zip ./out --mode smart
```

## 🧩 Interactive Showcase & Developer Docs

- **Interactive Showcase Page**: Open [showcase/index.html](showcase/index.html) in any browser to explore the interactive Windows-Zip UI simulator, multi-language switcher, and codec comparisons.
- **Contributor & AI Agent Guide**: See [AGENTS.md](AGENTS.md) for architecture boundaries, static-linking details, and engineering invariants.
- **Release History**: See [CHANGELOG.md](CHANGELOG.md).

## 📄 License

Released under the [MIT License](LICENSE).
