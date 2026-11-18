# Changelog

All notable changes to **BoltZip** will be documented in this file.

## [0.9.3] - 2026-11-18

### Fixed (`legacy/macos-12` Universal Compatibility Hotfix)
- **Quick Task HUD Layout Recursion Guard**:
  - Removed `NSHostingController.sizingOptions = [.preferredContentSize]` in [`QuickTaskHUDWindowController.swift`](Sources/BoltZipApp/Services/QuickTaskHUDWindowController.swift) so `NSHostingView.windowDidLayout()` never recurses into `updateAnimatedWindowSize(_:)` on borderless HUD panels, driving HUD resize explicitly from [`QuickTaskHUDModel.swift`](Sources/BoltZipApp/Models/QuickTaskHUDModel.swift) `phase` transitions with `ceil`-rounded bounds while preserving `#available(macOS 13.0, *)` / macOS 12 `fittingSize` compatibility.
- **Cold-Launch External URL Auto-Exit Guard**:
  - Removed the blind `excludingWindowID` exclusion in [`BoltZipAppDelegate.swift`](Sources/BoltZipApp/App/BoltZipAppDelegate.swift) so SwiftUI recycling and ordering front a provisional `NSWindow` during cold-launch Finder URL activation (`boltzip://finder?op=open...` / `op=openWorkspace`) is recognized accurately by `window.isVisible` without terminating prematurely.

## [0.9.2] - 2026-11-18

### Fixed (`legacy/macos-12` Universal Compatibility Hotfix)
- **macOS 12 / 13 Startup `SIGTRAP` Fix**:
  - Deferred `NSApp` / `BoltAppIconRenderer.apply` / `pluginkit` status queries out of `WorkspaceViewModel.init()` (which runs during SwiftUI's `@NSApplicationDelegateAdaptor` creation before `NSApp` is populated on macOS 12/13) into `BoltZipAppDelegate.applicationWillFinishLaunching` / `applicationDidFinishLaunching`.
  - Replaced unguarded `NSApp` accesses in [`WorkspaceViewModel.swift`](Sources/BoltZipApp/Models/WorkspaceViewModel.swift), [`MainMenuManager.swift`](Sources/BoltZipApp/App/MainMenuManager.swift), [`AppIconRenderer.swift`](Sources/BoltZipApp/Services/AppIconRenderer.swift), [`ArchiveExplorerView.swift`](Sources/BoltZipApp/Views/Explorer/ArchiveExplorerView.swift), [`AboutView.swift`](Sources/BoltZipApp/Views/Sheets/AboutView.swift), and [`SettingsView.swift`](Sources/BoltZipApp/Views/Sheets/SettingsView.swift) with safe optional casts `(NSApp as NSApplication?)`.
- **macOS 12–15 Compatibility Hardening**:
  - Added `UTImportedTypeDeclarations` for `.7z`, `.zst`/`.tar.zst`, `.xz`/`.tar.xz`, and `.lz4`/`.tar.lz4` in [`Scripts/build_app.sh`](Scripts/build_app.sh) alongside dynamic `UTType(filenameExtension:)` fallback in [`DefaultArchiveAssociationService.swift`](Sources/BoltZipApp/Services/DefaultArchiveAssociationService.swift) so clean macOS 12–15 installations resolve default archive associations cleanly.
  - Added bounds guarding to `QuickLookPreviewController.previewPanel(_:previewItemAt:)`, modifier-key filtering on the `< macOS 14` keyboard monitor in [`ArchiveExplorerView.swift`](Sources/BoltZipApp/Views/Explorer/ArchiveExplorerView.swift), and split SwiftUI `CommandGroup` declarations in [`BoltZipApp.swift`](Sources/BoltZipApp/App/BoltZipApp.swift) for Swift 6 `CommandsBuilder` compatibility.

## [0.9.1] - 2026-11-18

### Added & Improved (`legacy/macos-12` Universal Compatibility Release)
- **DMG Drag-to-Applications Installer**:
  - Added [`Scripts/create_dmg.sh`](Scripts/create_dmg.sh) and [`Scripts/generate_dmg_bg.swift`](Scripts/generate_dmg_bg.swift) to package `BoltZip-0.9.1-macOS-universal.dmg` with a high-DPI Finder drag-to-Applications window and custom volume icon alongside the `.zip` archive.
- **macOS 12.0 Monterey ~ macOS 26+ Universal (`arm64` + `x86_64`)**:
  - Lowered minimum deployment target to **macOS 12.0** across `Package.swift`, `Scripts/build_app.sh`, `BoltZip.app`, `boltzip` CLI, and `BoltZipFinderSync.appex`, preserving native **Intel (`x86_64`)** and **Apple Silicon (`arm64`)** Universal binaries.
  - Cross-compiled Universal `minOS 12.0` static **`libarchive 3.7.7`** alongside `libzstd`, `liblzma`, and `liblz4` inside `Vendor/Compression/` so `.rar` / RAR5 / `.7z` / `.iso` / `.cab` / `.xar` work identically on older macOS systems without outdated system libraries.
  - Replaced macOS 13+/14+ Swift/SwiftUI APIs (`OSAllocatedUnfairLock`, `@Observable`, dual-arg `.onChange`, `Window` scenes, `openWindow`) with `BoltLockedBox`, `ObservableObject`, `AuxiliaryWindowController`, and clean `#available` UI fallbacks while keeping macOS 26+ Liquid Glass intact.
- **RAR / RAR5, Multi-Core Parallelism & Default File Associations**:
  - Added full inspection, integrity test, password unlock, and extraction support for `.rar`, `.r00/.r01`, `.part1.rar`, and RAR5 archives.
  - Added parallel chunked extraction and ZIP/tar preparation (`ParallelExecutor`) across multi-core CPUs.
  - Added default archive file association manager in Settings and streamlined welcome return-on-close & unified system menu bar behavior.

## [0.9.0] - 2026-11-17

### Added & Improved
- **Finder Quick-Action Floating Progress HUD**:
  - Triggering quick compress or extract actions from Finder's top-level **`Bolt ›`** menu (`smartExtract`, `extractSubfolder`, `compressZip`, `compressTarZst`, `compress7z`) now displays a lightweight non-activating floating HUD panel (`QuickTaskHUDWindowController` + `QuickTaskHUDView`) without summoning or raising the main workspace window.
  - Supports **real-time ETA estimation**, byte-level progress & EMA transfer speed, cooperative **Pause / Resume** (`NSCondition` in `ArchiveTaskController` + C codec control callbacks in `CBoltCompression` + `SIGSTOP`/`SIGCONT` for `.7z`), immediate **Stop** with partial-file cleanup, FIFO multi-task queueing, and inline password prompt for encrypted archives.
- **Auto-Exit Lifecycle**:
  - Closing the main workspace window (when no auxiliary windows or active HUD tasks remain) or finishing/dismissing a standalone Finder HUD task automatically terminates `BoltZipApp` cleanly without lingering in the Dock or background.
- **Full 3-Layer Liquid Glass UI & Equal-Height Toolbar**:
  - Replaced the split-view sidebar chrome in [`MainWindowView`](Sources/BoltZipApp/Views/MainWindowView.swift) with a unified 3-layer glass workspace: full-window ambient backdrop (`Layer 1`), floating glass directory tree card + inspector card + translucent non-striped file table (`Layer 2`), and an edge-to-edge uniform-height glass header bar with matching `30pt` navigation & action capsules (`Layer 3`).
  - Upgraded Settings (with custom floating glass tab bar & explicit close controls), Compression Wizard, Extract Options, Benchmark Sheet (with ratio progress bars & fastest-speed highlight), Integrity Report, Entry Properties, Password/Name Prompts, and About window to the unified layered glass architecture, ensuring visible macOS close controls across all windows.
- **macOS 14.0+ Universal (`arm64` + `x86_64`) & Automatic Legacy Fallback**:
  - Lowered minimum deployment target to **macOS 14.0 (Sonoma)** for `BoltZip.app`, `boltzip` CLI, and `BoltZipFinderSync.appex`.
  - Added [`Scripts/build_universal_deps.sh`](Scripts/build_universal_deps.sh) to cross-compile Universal (`arm64` + `x86_64`, `minOS 14.0`) static archives (`libzstd.a`, `liblzma.a`, `liblz4.a`) into `Vendor/Compression/` with zero Homebrew runtime dependencies.
  - Automatic Liquid Glass fallback on macOS 14–15 (or when window translucency is disabled) via [`GlassDesignSystem.swift`](Sources/BoltZipApp/Views/GlassDesignSystem.swift) compatibility helpers.
- **Highlighted `.DS_Store` Cleanup & 7z CJK Fix**:
  - Promoted automatic `.DS_Store` / `__MACOSX` / `._*` junk removal across the welcome card, 4-language READMEs, and showcase site.
  - Fixed UTF-8 locale and `bsdtar` octal escape decoding (`\\NNN`) so `.7z` inspection accurately displays Chinese/Unicode directory trees.
- **Showcase Site, Official Icon & Live Public Deployment**:
  - Completed full 4-language localization (`zh-Hans`, `zh-Hant`, `en`, `ja`) across all interactive simulator labels, toasts, algorithm comparisons, and download cards.
  - Added official BoltZip favicon & brand icon (`showcase/favicon.png`, `showcase/app-icon.png`) exported from [`Scripts/generate_icon.swift`](Scripts/generate_icon.swift).
  - Updated all 4 READMEs and the in-app **Showcase** action to point to the public deployment at `https://122.51.112.183/boltzip/`.

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
