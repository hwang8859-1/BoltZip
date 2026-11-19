# Changelog

All notable changes to **BoltZip** will be documented in this file.

## [1.0.3] - 2026-11-19

### Improved
- Reorganized the welcome screen with a dedicated feature card and a compact window that shows the drop zone with equal margins.
- Added an optional gold sweep for the Dock icon. The selected light or dark icon and gold tip persist after quitting when the app is pinned to the Dock.

### Fixed
- Stage extracted entries before replacement so failed or canceled extraction leaves existing files intact.
- Reject unsupported archive size totals and mismatched ZIP decoded sizes before committing output.
- Build release source archives from a clean commit and tighten release-branch validation and archival safeguards.

## [1.0.2] - 2026-11-19 (`dev-1.0.2`: Streaming Engine, Symlinks, Drag-Out, Updater, Adaptive Icons & Reliability Hardening)

### Core Engine & Format Support
- **Chunked Streaming I/O & Large-File Encryption**: Files `>= 64 MB` stream in `1 MB` chunks across ZIP, WinZip AE-2 (AES-256-CTR + incremental HMAC-SHA1), ZipCrypto, and TAR/TAR.{gz,zst,xz,bz2,lz4} (`bolt_compress_file_workers`, `bolt_decompress_file_ex`, `bolt_verify_file`, `ZipSpanningCursor`, `SplitVolumeSink.writeFile`) to keep peak memory flat on multi-GB archives.
- **Symbolic Link Preservation & Traversal Protection**: Added optional symlink preservation (`preserveSymlinks`) and safe restoration (`restoreSymlinks`) for ZIP, TAR, and 7z, rejecting empty, absolute, or escaping symlink targets and intermediate symlink traversal (`assertNoSymlinkTraversal`, `createSafeSymlink`), plus file-vs-directory `.overwrite` collision protection across extractor and drag-out promises.
- **APFS/HFS+ Hardlink `.7z` Staging & ZIP Comments**: Staged 7z creation via `FileManager.linkItem` (falling back to copy) for near-instant multi-GB staging, plus in-place ZIP archive comment editing (`ZipEditOperation.setComment`).
- **ZIP Container Formats, Bit-3 Edit & Legacy Method Fallback**: Added `.ipa`, `.apk`, `.jar`, `.epub`, and `.whl` recognition, pre-edit password unlock, bit-3 Data Descriptor preservation on in-place legacy ZipCrypto edits, and read-only `libarchive` fallback for ZIP Deflate64 (method 9) and LZMA (method 14).
- **Thread-Safe Multi-Core Control & Boundary Hardening**: Wired user-selectable Auto or fixed worker core counts across ZIP parallel entries and C codec workers (`Zstandard` / `XZ`), added concurrent stdout/stderr pipe draining in `ExtendedArchiveDriver`, empty-buffer `bolt_crc32` preservation, bounded Central Directory allocations, trailing-byte EOCD scan fallback, single-entry disk-streaming extraction (`extractSingleEntryToFile`), and TAR truncated-block detection.

### Desktop App & Liquid Glass UI
- **Finder Drag-Out (`NSFilePromiseProvider`)**: Drag single or multiple files/folders directly out of the archive explorer into Finder or apps, with single batch password prompt and background progress.
- **In-App GitHub Releases Updater**: Added `UpdateCheckerService` (ETag caching, 24h automatic check throttling, `1.x` track isolation, Skip Version persistence, and `SHA256SUMS.txt` DMG verification) and `Check for Updates...` menu bar command.
- **Nested Archive Navigation & Batch Drop**: Double-click archives embedded inside archives to drill in with breadcrumb back-navigation (`archiveBackStack`) and automatic temp cleanup; dropping multiple archives on Welcome offers opening all or batch extraction.
- **Adaptive macOS 26 AppIcon (`Assets.car`) & 17 Per-Format Document Icons**: Compiled Icon Composer `AppIcon.icon` into `Assets.car` + `CFBundleIconName` so Light/Dark Dock & Finder icons switch automatically even when closed, alongside a 3-mode `AppIconStyle` (`System` / `Light` / `Dark`) setting with live `dockTile.display()` refresh and 17 crisp `.icns` document icons.
- **Settings, Quick Look, Sheet Unification & Window Ergonomics**: Added default extraction mode & conflict policy preferences, symlink switches, Trash-source-on-completion toggles, full CJK encodings (`Big5`, `Shift-JIS`, `EUC-KR`, `GB18030`), 128 MB explicit / 50 MB debounced Quick Look streaming previews, `⌘A` / `⌘C` / `Delete` shortcuts with confirmation, unified `BoltSheetFooterBar`, tightened `BoltGlassContainer` / `BoltReadOnlyBadge` consistency, draggable Finder Quick HUD & standalone Compress header (`BoltWindowDragHandle`), and single-window foreground activation (`boltActivateAppToForeground` + per-window delegate proxy).

### CLI, Finder Extension & Release Infra
- **`boltzip` CLI Upgrade**: Added in-place ZIP subcommands (`add`, `rm`, `mkdir`, `mv`), flat extraction (`e`), `--overwrite overwrite|skip|rename`, `--comment`, `--no-symlinks`, `--json` machine-readable output on `l`/`t`/`bench`, and `stderr` TTY progress bar.
- **`BoltZipFinderSync` Extension Upgrade**: Added "Compress Each to ZIP" on multi-selection, "Extract to..." picker action, container extensions, and 4-language localized strings.
- **Release Tooling & CI**: Added `CODESIGN_IDENTITY` / `BOLTZIP_NOTARY_PROFILE` signing and notarization hooks in `Scripts/build_app.sh`, automated `Scripts/verify_release.sh` and `Scripts/e2e_finder_ui.sh`, and extended `.github/workflows/ci.yml`.

## [1.0.1] - 2026-11-18 (`main`: Apple Silicon + macOS 26+ Hotfix & Quality Release)

### Fixed
- **Finder Quick-Action HUD Stack Overflow (`EXC_BAD_ACCESS / SIGSEGV`)**:
  - Removed `hc.sizingOptions = [.preferredContentSize]` in [`QuickTaskHUDWindowController.swift`](Sources/BoltZipApp/Services/QuickTaskHUDWindowController.swift) where macOS 26's `NSHostingView.windowDidLayout() -> updateAnimatedWindowSize(_:)` caused infinite layout recursion inside the borderless `QuickHUDPanel` during Finder right-click compress & extract actions.
  - Added coalesced `scheduleResizeToFit()` triggered by [`QuickTaskHUDModel.swift`](Sources/BoltZipApp/Models/QuickTaskHUDModel.swift) `phase` changes and password focus transitions with `ceil`-rounded bounds.
- **Cold-Launch External URL Auto-Exit**:
  - Removed the blind `excludingWindowID` exclusion in [`BoltZipAppDelegate.swift`](Sources/BoltZipApp/App/BoltZipAppDelegate.swift) so SwiftUI recycling and ordering front an initial `NSWindow` during cold-launch Finder actions (`boltzip://finder?op=open...` / `op=openWorkspace`) stays alive cleanly.
- **macOS Lifecycle, 7z Levels & Split-ZIP Safety**:
  - Deferred `NSApp` initialization out of `WorkspaceViewModel.init()`, fixed `.7z` compression level forwarding, guarded in-place editing of split-volume ZIPs, wired status bar toggle & Quick Look temp-file cleanup, and fixed multi-archive batch extraction & integrity reports.

### Improved
- **Liquid Glass Hierarchy, Localized FinderSync & Centralized Version Metadata**:
  - Aligned toolbar, inspector, and sheet surfaces to native macOS 26 Liquid Glass hierarchy; localized `BoltZipCore` errors/metadata and embedded `.lproj` localization bundles in `BoltZipFinderSync.appex`; centralized `BoltZipVersion` (`1.0.1`) across `BoltZipCore`, `boltzip` CLI, `BoltZipApp`, and `build_app.sh`.

## [0.9.3 (`legacy/macos-12`)] - 2026-11-18

### Fixed
- **Universal LTS HUD Layout & Cold-Launch URL Guards**: Backported the `QuickTaskHUDWindowController` `sizingOptions = []` resize-coalescing fix and the `BoltZipAppDelegate` `willCloseNotification` window-visibility check to `legacy/macos-12` (`v0.9.3` Universal `arm64` + `x86_64`, `minOS 12.0`).

## [1.0.0] - 2026-11-18 (`main`: Apple Silicon + macOS 26+ Exclusive)

### Changed
- **DMG Drag-to-Applications Installer**:
  - Added [`Scripts/create_dmg.sh`](Scripts/create_dmg.sh) and [`Scripts/generate_dmg_bg.swift`](Scripts/generate_dmg_bg.swift) to package `BoltZip-*.dmg` with a high-DPI Finder drag-to-Applications window, custom volume icon, and clean `.DS_Store` layout alongside the portable `.zip` bundle.
- **Apple Silicon (`arm64`) + macOS 26+ Baseline**:
  - Raised deployment target on `main` to **macOS 26.0+** with `swift-tools-version: 6.2` and exclusively targets **Apple Silicon (`arm64` / M-series)** (`Scripts/build_app.sh` and `Scripts/build_universal_deps.sh` drop `x86_64` fat slices for smaller binaries and zero deprecation warnings).
  - Simplified [`WindowBackingViews.swift`](Sources/BoltZipApp/Views/Design/WindowBackingViews.swift) and [`GlassDesignSystem.swift`](Sources/BoltZipApp/Views/Design/GlassDesignSystem.swift) to use native macOS 26 **Liquid Glass** APIs (`GlassEffectContainer`, `.glassEffect`, `NSGlassEffectView`, `.buttonStyle(.glass)`, `.toolbarBackgroundVisibility`, `.sharedBackgroundVisibility(.hidden)`) directly without pre-macOS-26 `#available` fallbacks.
  - Legacy support for **macOS 12 Monterey through macOS 26+ Universal (`arm64` + `x86_64` / Intel)** is maintained on branch [`legacy/macos-12`](../../tree/legacy/macos-12) (latest **`v0.9.2`**).
- **RAR / RAR5, Multi-Core Parallelism & Default File Associations**:
  - Added full inspection, integrity check, password unlock, and extraction for `.rar`, `.r00/.r01`, `.part1.rar`, and RAR5 archives.
  - Added multi-core parallel entry preparation and chunked extraction via `ParallelExecutor`.
  - Added default archive file association management in Settings and return-to-welcome navigation on archive close.

## [0.9.2 (`legacy/macos-12`)] - 2026-11-18

### Fixed
- **macOS 12 / 13 Startup `SIGTRAP` Fix & Compatibility Hardening** (`legacy/macos-12`, also backported to `dev-1.0.1`):
  - Deferred `NSApp.appearance`, `BoltAppIconRenderer.apply`, and `QuickActionInstaller.isExtensionEnabled()` out of `WorkspaceViewModel.init()` into AppKit launch delegates (`applicationWillFinishLaunching` / `applicationDidFinishLaunching`) so macOS 12/13 SwiftUI initialization never force-unwraps `NSApp` while nil.
  - Guarded `(NSApp as NSApplication?)` across lifecycle/menu/window helpers, added bounds checks in `QuickLookPreviewController`, added modifier filtering on the `< macOS 14` explorer keyboard monitor, split 16 `CommandGroup` items into two `.commands` blocks, and added `UTImportedTypeDeclarations` + dynamic extension fallback for clean macOS 12–15 default archive association resolution.

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
