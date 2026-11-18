<div align="center">

# BoltZip ⚡

**Lightning-fast archives. Liquid-clear macOS craft.**

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | **English** | [日本語](README.ja.md)

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B%20(Apple%20Silicon)-0ea5e9?style=flat-square)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-6366f1?style=flat-square)
![Release v1.0.1](https://img.shields.io/badge/release-v1.0.1-facc15?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

</div>

---

**BoltZip** is an open-source archive manager crafted exclusively for **macOS 26.0+ on Apple Silicon (`arm64` / M-series)**. It pairs the productive, desktop-class archive workflows popularized by Windows tools (7-Zip, WinZip, Bandizip) with native **Liquid Glass** craft—so you never have to extract an entire archive just to inspect or edit one file.

> 💡 **Using Intel Mac or macOS 12–15?** Download **v0.9.3 Universal (`arm64` + `x86_64`)** from the [`legacy/macos-12`](../../tree/legacy/macos-12) branch / `v0.9.3` release tag.

> [!IMPORTANT]
> **Active Development: [Repository Default `dev-*` Branch](../../)** · `main` is a protected release-only branch. Please target the active default `dev-*` branch for all pull requests — see [CONTRIBUTING.md](CONTRIBUTING.md).

## ✨ Highlights

- **Auto-Remove `.DS_Store` & macOS Junk**: Automatically strips `.DS_Store`, `__MACOSX`, `._*`, `.Spotlight-V100`, and `.Trashes` during archive creation, in-place ZIP additions, and extraction—keeping archives clean for Windows/Linux recipients and preventing `__MACOSX` from breaking Smart Extract (opt out via `--keep-junk` in CLI or the toggle in UI).
- **Top-Level Finder Context Menu `Bolt ›`**: Powered by a sandboxed native `FinderSync` extension (`BoltZipFinderSync.appex`), quick actions appear directly at the top level of Finder’s right-click menu—never buried under Services:
  - Smart Extract / Extract to Subfolder / Browse in BoltZip / Verify Integrity
  - Instant Compress to `ZIP`, `TAR.ZST (Zstd)`, `7z`, or Encrypted & Split Archive Wizard
- **Browse & Edit Inside Archives**: Double-click or press `Space` to preview entries via macOS Quick Look without full extraction. Navigate folder trees, search/sort, inspect CRC32 & metadata, export selected entries into a new ZIP, and **add, rename, or delete inside ZIP files** with zero recompression of untouched entries.
- **Native Liquid Glass Experience**:
  - On macOS 26+, toggle window translucency and fine-tune background opacity (`25% – 100%`) live;
  - Independently show/hide home modules (Finder setup banner, feature highlights, recent archives), sidebar summary, and status bar;
  - Shrinks cleanly down to a compact `380 × 285` mini drop window (keeping only the core drop zone at minimal height).
- **Idiomatic Multi-Language Support**: Automatically follows your macOS system language or switches live between **简体中文**, **繁體中文**, **English**, and **日本語**.
- **Pure Open-Source Apple Silicon Codec Core**: Statically links `arm64` `zlib`, `libzstd`, `liblzma`, `libbz2`, and `liblz4` (zero Homebrew runtime dylib dependencies), plus system `libarchive` bridging for `.rar`, `.7z`, `.iso`, `.cab`, and `.xar`.
- **Cross-Platform Fidelity**:
  - **WinZip AE-2 AES-256** encryption (`PBKDF2-HMAC-SHA1` + `AES-256-CTR` + 10-byte `HMAC-SHA1`) and legacy `ZipCrypto`;
  - Automatic detection of `GB18030 / GBK`, `Big5`, `Shift-JIS`, and `EUC-KR` filenames in Windows-created ZIPs;
  - Supports `.z01/.z02/.../.zip` split volumes and Smart Extract (avoids nested duplicate folders).

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

- **Live Showcase & Download Page**: Visit [**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/) to explore the live interactive Windows-Zip UI simulator, multi-language switcher, codec benchmarks, and direct downloads for `BoltZip v1.0.1 Apple Silicon` & source archives (sources in [showcase/](showcase/)).
- **Contributor & AI Agent Guide**: See [AGENTS.md](AGENTS.md) for architecture boundaries, static-linking details, and engineering invariants.
- **Release History**: See [CHANGELOG.md](CHANGELOG.md).

## 📄 License

Released under the [MIT License](LICENSE).
