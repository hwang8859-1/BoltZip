import AppKit
import BoltZipCore
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class WorkspaceViewModel {
    var listing: ArchiveListing?
    var navigationIndex: ArchiveNavigationIndex?
    var folderTree: FolderTreeNode = FolderTreeNode(id: "", name: "", path: "", children: [], fileCount: 0)
    var visibleEntries: [ArchiveEntry] = []
    var visibleEntryByID: [String: ArchiveEntry] = [:]
    var breadcrumbComponents: [(title: String, path: String)] = []
    var selectedEntriesCache: [ArchiveEntry] = []
    var selectedTotalUncompressedBytes: UInt64 = 0
    @ObservationIgnored var isBatchUpdatingNavigation: Bool = false

    var openedArchiveFromHome: Bool = false
    var currentFolder: String = "" {
        didSet {
            guard !isBatchUpdatingNavigation, oldValue != currentFolder else { return }
            rebuildNavigationViews()
        }
    }
    var folderForwardStack: [String] = []
    var selectedEntryIDs: Set<String> = [] {
        didSet {
            guard !isBatchUpdatingNavigation, oldValue != selectedEntryIDs else { return }
            refreshSelectionCache()
        }
    }
    var searchText: String = "" {
        didSet {
            guard !isBatchUpdatingNavigation, oldValue != searchText else { return }
            refreshVisibleEntries()
        }
    }
    var encodingOption: FilenameEncodingOption = .auto
    var sortColumn: SortColumn = .name {
        didSet {
            guard !isBatchUpdatingNavigation, oldValue != sortColumn else { return }
            refreshVisibleEntries()
        }
    }
    var sortAscending: Bool = true {
        didSet {
            guard !isBatchUpdatingNavigation, oldValue != sortAscending else { return }
            refreshVisibleEntries()
        }
    }
    var columnVisibility: NavigationSplitViewVisibility = .all

    var isBusy: Bool = false
    var progress: OperationProgress?
    var statusMessage: String = ""
    var alertMessage: String?
    var pendingExtractConflict: PendingExtractConflict?
    var pendingBatchArchiveDrop: PendingBatchArchivePrompt?
    var pendingDeleteConfirmation: PendingDeleteConfirmation?
    var pendingRecoverZipURL: URL?
    var activeSheet: ActiveSheet?
    var savedPassword: String?
    var pendingKeychainSaveTargetURL: URL?
    var pendingKeychainSavePassword: String?
    var savedKeychainPasswordCount: Int = 0
    var compressionProfiles: [CompressionProfile] = []
    var preferredZipEditAlgorithm: CompressionAlgorithm = .deflate
    var archiveEditErrorMessage: String?

    var archiveBackStack: [ArchiveNavigationFrame] = []
    var nestedTempDirs: [URL] = []
    var trashAfterSuccessByOpID: [UUID: [URL]] = [:]
    var quickLookRefreshTask: Task<Void, Never>?

    var recentArchivePaths: [String] = []
    var defaultStripMacJunk: Bool = true
    var defaultExtractDestination: DefaultExtractDestination = .sameFolder {
        didSet {
            UserDefaults.standard.set(defaultExtractDestination.rawValue, forKey: Keys.defaultExtractDest)
        }
    }
    var defaultExtractMode: DefaultExtractModePreference = .smart {
        didSet {
            UserDefaults.standard.set(defaultExtractMode.rawValue, forKey: Keys.defaultExtractMode)
        }
    }
    var preserveSymlinksOnCreate: Bool = true {
        didSet {
            UserDefaults.standard.set(preserveSymlinksOnCreate, forKey: Keys.preserveSymlinks)
        }
    }
    var restoreSymlinksOnExtract: Bool = true {
        didSet {
            UserDefaults.standard.set(restoreSymlinksOnExtract, forKey: Keys.restoreSymlinks)
        }
    }
    var autoCheckForUpdates: Bool = true {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: Keys.autoCheckUpdates)
        }
    }
    var skippedUpdateVersion: String = "" {
        didSet {
            UserDefaults.standard.set(skippedUpdateVersion, forKey: Keys.skippedUpdateVersion)
        }
    }
    var lastUpdateCheckTimestamp: TimeInterval = 0 {
        didSet {
            UserDefaults.standard.set(lastUpdateCheckTimestamp, forKey: Keys.lastUpdateCheck)
        }
    }
    var lastUpdateETag: String = "" {
        didSet {
            UserDefaults.standard.set(lastUpdateETag, forKey: Keys.lastUpdateETag)
        }
    }
    var isCheckingUpdates: Bool = false

    var quickActionsInstalled: Bool = false
    var associationStatuses: [ArchiveAssociationStatus] = []
    var isUpdatingAssociations: Bool = false

    // Localization, Window Behavior, Translucency & Modular Panel Visibility Preferences
    var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            onLanguageChanged?()
            rebuildNavigationViews()
        }
    }
    var appTheme: AppTheme = .system {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme)
            (NSApp as NSApplication?)?.appearance = appTheme.nsAppearance
        }
    }
    var isWindowTranslucent: Bool = true {
        didSet {
            UserDefaults.standard.set(isWindowTranslucent, forKey: Keys.windowTranslucent)
        }
    }
    var glassIntensity: Double = 0.75 {
        didSet {
            UserDefaults.standard.set(glassIntensity, forKey: Keys.glassIntensity)
        }
    }
    var windowBackgroundOpacity: Double {
        get { max(0.05, 1.0 - glassIntensity) }
        set { glassIntensity = min(max(1.0 - newValue, 0.0), 1.0) }
    }
    var appBackgroundColor: AppBackgroundColor = .pureWhite {
        didSet {
            UserDefaults.standard.set(appBackgroundColor.rawValue, forKey: Keys.appBackgroundColor)
        }
    }
    var customBackgroundRed: Double = 0.94 {
        didSet { UserDefaults.standard.set(customBackgroundRed, forKey: Keys.customBgR) }
    }
    var customBackgroundGreen: Double = 0.96 {
        didSet { UserDefaults.standard.set(customBackgroundGreen, forKey: Keys.customBgG) }
    }
    var customBackgroundBlue: Double = 0.99 {
        didSet { UserDefaults.standard.set(customBackgroundBlue, forKey: Keys.customBgB) }
    }
    var showFinderBanner: Bool = true {
        didSet {
            UserDefaults.standard.set(showFinderBanner, forKey: Keys.showFinderBanner)
        }
    }
    var showFeatureHighlights: Bool = true {
        didSet {
            UserDefaults.standard.set(showFeatureHighlights, forKey: Keys.showFeatures)
        }
    }
    var showRecentArchives: Bool = true {
        didSet {
            UserDefaults.standard.set(showRecentArchives, forKey: Keys.showRecents)
        }
    }
    var showSidebarInspector: Bool = true {
        didSet {
            UserDefaults.standard.set(showSidebarInspector, forKey: Keys.showInspector)
        }
    }
    var showStatusBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showStatusBar, forKey: Keys.showStatusBar)
        }
    }
    var appIconStyle: AppIconStyle = .system {
        didSet {
            guard oldValue != appIconStyle else { return }
            UserDefaults.standard.set(appIconStyle.rawValue, forKey: Keys.appIconStyle)
            refreshAppIcon()
        }
    }
    var appIconAnimationEnabled = true {
        didSet {
            guard oldValue != appIconAnimationEnabled else { return }
            UserDefaults.standard.set(appIconAnimationEnabled, forKey: Keys.appIconAnimationEnabled)
            refreshAppIcon()
        }
    }

    func refreshAppIcon() {
        guard let app = NSApp as NSApplication? else { return }
        BoltAppIconRenderer.apply(style: appIconStyle, animationEnabled: appIconAnimationEnabled, in: app)
    }

    func effectiveWhiteAppIcon(for colorScheme: ColorScheme) -> Bool {
        switch appIconStyle {
        case .system:
            switch appTheme {
            case .light: return true
            case .dark: return false
            case .system: return colorScheme != .dark
            }
        case .light:
            return true
        case .dark:
            return false
        }
    }
    var multiCorePreference: MultiCorePreference = .auto {
        didSet {
            BoltConcurrency.setPreference(multiCorePreference, persist: true)
            if case .fixed(let count) = multiCorePreference {
                let clamped = min(max(1, count), BoltConcurrency.hardwareCoreCount)
                lastManualCoreCount = clamped
                UserDefaults.standard.set(clamped, forKey: Keys.lastManualCoreCount)
            }
        }
    }
    var lastManualCoreCount: Int = BoltConcurrency.autoWorkerCount

    // HUD & Lifecycle Coordination
    let hudModel = QuickTaskHUDModel()
    let inAppTaskHUD = QuickTaskHUDModel()
    let hudWindowController = QuickTaskHUDWindowController()
    let compressWindowController = CompressWizardWindowController()
    var isHUDConfigured = false
    var isInAppHUDConfigured = false
    var isPreparingHUDExtract: Bool = false

    var onRequestShowMainWindow: (() -> Void)?
    var onHUDDidHide: (() -> Void)?
    var onCompressWindowDidClose: (() -> Void)?
    var onLanguageChanged: (() -> Void)?

    let previewTempRoot: URL
    var activePreviewTempDir: URL?

    enum Keys {
        static let recents = "BoltZip.RecentArchives"
        static let stripJunk = "BoltZip.ExcludeMacJunk"
        static let appLanguage = "BoltZip.AppLanguage"
        static let appTheme = "BoltZip.AppTheme"
        static let windowTranslucent = "BoltZip.IsWindowTranslucent"
        static let glassIntensity = "BoltZip.GlassIntensity"
        static let appBackgroundColor = "BoltZip.AppBackgroundColor"
        static let customBgR = "BoltZip.CustomBgRed"
        static let customBgG = "BoltZip.CustomBgGreen"
        static let customBgB = "BoltZip.CustomBgBlue"
        static let showFinderBanner = "BoltZip.ShowFinderBanner"
        static let showFeatures = "BoltZip.ShowFeatureHighlights"
        static let showRecents = "BoltZip.ShowRecentArchives"
        static let showInspector = "BoltZip.ShowSidebarInspector"
        static let showStatusBar = "BoltZip.ShowStatusBar"
        static let appIconStyle = "BoltZip.AppIconStyle"
        static let appIconAnimationEnabled = "BoltZip.AppIconAnimationEnabled"
        static let whiteAppIcon = "BoltZip.UseWhiteAppIcon"
        static let workerCoreCount = BoltConcurrency.userDefaultsKey
        static let lastManualCoreCount = "BoltZip.LastManualCoreCount"
        static let defaultExtractDest = "BoltZip.DefaultExtractDestination"
        static let defaultExtractMode = "BoltZip.DefaultExtractMode"
        static let preserveSymlinks = "BoltZip.PreserveSymlinks"
        static let restoreSymlinks = "BoltZip.RestoreSymlinks"
        static let autoCheckUpdates = "BoltZip.AutoCheckForUpdates"
        static let skippedUpdateVersion = "BoltZip.SkippedUpdateVersion"
        static let lastUpdateCheck = "BoltZip.LastUpdateCheckTimestamp"
        static let lastUpdateETag = "BoltZip.LastUpdateETag"
    }

    var supportsLiquidGlass: Bool { BoltPlatformCapabilities.supportsLiquidGlass }
    var effectiveWindowTranslucency: Bool { supportsLiquidGlass && isWindowTranslucent }
    var l10n: L10n { L10n(language: appLanguage) }
    var hardwareCoreCount: Int { BoltConcurrency.hardwareCoreCount }
    var autoWorkerCount: Int { BoltConcurrency.autoWorkerCount }
    var effectiveWorkerCount: Int { BoltConcurrency.resolvedWorkerCount() }
    var isMultiCoreAuto: Bool { multiCorePreference.isAuto }
    var selectedManualCoreCount: Int {
        get {
            if case .fixed(let count) = multiCorePreference {
                return min(max(1, count), hardwareCoreCount)
            }
            return min(max(1, lastManualCoreCount), hardwareCoreCount)
        }
        set {
            let clamped = min(max(1, newValue), hardwareCoreCount)
            multiCorePreference = .fixed(clamped)
        }
    }

    func setMultiCoreAuto(_ isAuto: Bool) {
        if isAuto {
            multiCorePreference = .auto
        } else {
            multiCorePreference = .fixed(min(max(1, lastManualCoreCount), hardwareCoreCount))
        }
    }

    func multiCoreStatusSummary(_ l: L10n) -> String {
        isMultiCoreAuto ? l.multiCoreBadgeAuto(autoWorkerCount) : l.multiCoreBadgeManual(effectiveWorkerCount)
    }
    var isHUDWindowVisible: Bool { hudWindowController.isVisible }
    var isCompressWindowVisible: Bool { compressWindowController.isVisible }

    var hasVisibleMainWindow: Bool {
        guard let app = NSApp as NSApplication? else { return false }
        return app.windows.contains { window in
            let id = window.identifier?.rawValue ?? ""
            let isMainID = id == "boltzip.main" || id.hasPrefix("main")
            return isMainID
                && window.isVisible
                && !window.isMiniaturized
                && window.alphaValue > 0.1
        }
    }

    var recentArchiveURLs: [URL] {
        recentArchivePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var customSwiftUIColorBinding: Color {
        Color(red: customBackgroundRed, green: customBackgroundGreen, blue: customBackgroundBlue)
    }

    init() {
        let defaults = UserDefaults.standard
        self.previewTempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoltZipPreview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        self.recentArchivePaths = defaults.stringArray(forKey: Keys.recents) ?? []

        if defaults.object(forKey: Keys.stripJunk) != nil {
            self.defaultStripMacJunk = defaults.bool(forKey: Keys.stripJunk)
        }
        if let rawLang = defaults.string(forKey: Keys.appLanguage), let parsed = AppLanguage(rawValue: rawLang) {
            self.appLanguage = parsed
        }
        if let rawTheme = defaults.string(forKey: Keys.appTheme), let parsedTheme = AppTheme(rawValue: rawTheme) {
            self.appTheme = parsedTheme
        }
        if defaults.object(forKey: Keys.windowTranslucent) != nil {
            self.isWindowTranslucent = defaults.bool(forKey: Keys.windowTranslucent)
        }
        if defaults.object(forKey: Keys.glassIntensity) != nil {
            self.glassIntensity = defaults.double(forKey: Keys.glassIntensity)
        }
        if let rawBg = defaults.string(forKey: Keys.appBackgroundColor),
           let parsedBg = AppBackgroundColor(rawValue: rawBg) {
            self.appBackgroundColor = parsedBg
        }
        if defaults.object(forKey: Keys.customBgR) != nil {
            self.customBackgroundRed = defaults.double(forKey: Keys.customBgR)
            self.customBackgroundGreen = defaults.double(forKey: Keys.customBgG)
            self.customBackgroundBlue = defaults.double(forKey: Keys.customBgB)
        }
        if defaults.object(forKey: Keys.showFinderBanner) != nil {
            self.showFinderBanner = defaults.bool(forKey: Keys.showFinderBanner)
        }
        if defaults.object(forKey: Keys.showFeatures) != nil {
            self.showFeatureHighlights = defaults.bool(forKey: Keys.showFeatures)
        }
        if defaults.object(forKey: Keys.showRecents) != nil {
            self.showRecentArchives = defaults.bool(forKey: Keys.showRecents)
        }
        if defaults.object(forKey: Keys.showInspector) != nil {
            self.showSidebarInspector = defaults.bool(forKey: Keys.showInspector)
        }
        if defaults.object(forKey: Keys.showStatusBar) != nil {
            self.showStatusBar = defaults.bool(forKey: Keys.showStatusBar)
        }
        if let rawIconStyle = defaults.string(forKey: Keys.appIconStyle),
           let parsedIconStyle = AppIconStyle(rawValue: rawIconStyle) {
            self.appIconStyle = parsedIconStyle
        } else if defaults.object(forKey: Keys.whiteAppIcon) != nil, defaults.bool(forKey: Keys.whiteAppIcon) {
            self.appIconStyle = .light
        }
        if defaults.object(forKey: Keys.appIconAnimationEnabled) != nil {
            self.appIconAnimationEnabled = defaults.bool(forKey: Keys.appIconAnimationEnabled)
        }
        let hwCores = BoltConcurrency.hardwareCoreCount
        let savedManual = defaults.integer(forKey: Keys.lastManualCoreCount)
        self.lastManualCoreCount = savedManual >= 1 ? min(savedManual, hwCores) : BoltConcurrency.autoWorkerCount
        if defaults.object(forKey: Keys.workerCoreCount) != nil {
            let rawCores = defaults.integer(forKey: Keys.workerCoreCount)
            let loadedPref = MultiCorePreference(rawStorageValue: rawCores)
            self.multiCorePreference = loadedPref
            BoltConcurrency.setPreference(loadedPref, persist: false)
            if case .fixed(let count) = loadedPref {
                self.lastManualCoreCount = min(max(1, count), hwCores)
            }
        }
        if let rawDest = defaults.string(forKey: Keys.defaultExtractDest),
           let parsedDest = DefaultExtractDestination(rawValue: rawDest) {
            self.defaultExtractDestination = parsedDest
        }
        if let rawMode = defaults.string(forKey: Keys.defaultExtractMode),
           let parsedMode = DefaultExtractModePreference(rawValue: rawMode) {
            self.defaultExtractMode = parsedMode
        }
        if defaults.object(forKey: Keys.preserveSymlinks) != nil {
            self.preserveSymlinksOnCreate = defaults.bool(forKey: Keys.preserveSymlinks)
        }
        if defaults.object(forKey: Keys.restoreSymlinks) != nil {
            self.restoreSymlinksOnExtract = defaults.bool(forKey: Keys.restoreSymlinks)
        }
        if defaults.object(forKey: Keys.autoCheckUpdates) != nil {
            self.autoCheckForUpdates = defaults.bool(forKey: Keys.autoCheckUpdates)
        }
        self.skippedUpdateVersion = defaults.string(forKey: Keys.skippedUpdateVersion) ?? ""
        self.lastUpdateCheckTimestamp = defaults.double(forKey: Keys.lastUpdateCheck)
        self.lastUpdateETag = defaults.string(forKey: Keys.lastUpdateETag) ?? ""
        self.statusMessage = L10n(language: self.appLanguage).readyStatus
    }

    func clearRecents() {
        recentArchivePaths.removeAll()
        UserDefaults.standard.set([String](), forKey: Keys.recents)
    }

    func skipUpdateVersion(_ version: String) {
        skippedUpdateVersion = version
    }

    func resolveDefaultExtractDirectory(for archiveURL: URL) -> URL? {
        switch defaultExtractDestination {
        case .sameFolder:
            return archiveURL.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? archiveURL.deletingLastPathComponent()
        case .ask:
            return nil
        }
    }

    func checkForUpdates(userInitiated: Bool) {
        guard userInitiated || autoCheckForUpdates else { return }
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true

        let force = userInitiated
        let etag = lastUpdateETag
        let skipped = skippedUpdateVersion
        let lastTS = lastUpdateCheckTimestamp

        Task { @MainActor in
            defer { self.isCheckingUpdates = false }
            do {
                let res = try await UpdateCheckerService.checkForUpdates(
                    force: force,
                    savedETag: etag,
                    skippedVersion: skipped,
                    lastCheckTimestamp: lastTS
                )
                if res.didPerformCheck {
                    self.lastUpdateCheckTimestamp = Date().timeIntervalSince1970
                }
                if let newETag = res.newETag {
                    self.lastUpdateETag = newETag
                }
                switch res.outcome {
                case .updateAvailable(let info):
                    self.activeSheet = .updateAvailable(info)
                case .upToDate(let curVer):
                    if userInitiated {
                        self.alertMessage = self.l10n.updateUpToDateMessage(curVer)
                    }
                }
            } catch {
                if userInitiated {
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
    }

    func updateDefaultStripMacJunk(_ value: Bool) {
        defaultStripMacJunk = value
        UserDefaults.standard.set(value, forKey: Keys.stripJunk)
    }

    func resolvedBackgroundNSColor(isDark: Bool) -> NSColor {
        appBackgroundColor.resolvedNSColor(
            isDark: isDark,
            customRed: customBackgroundRed,
            customGreen: customBackgroundGreen,
            customBlue: customBackgroundBlue
        )
    }

    func setCustomBackgroundColor(_ color: Color) {
        if let ns = NSColor(color).usingColorSpace(.deviceRGB) {
            customBackgroundRed = Double(ns.redComponent)
            customBackgroundGreen = Double(ns.greenComponent)
            customBackgroundBlue = Double(ns.blueComponent)
            appBackgroundColor = .custom
        }
    }

    func shouldReturnHomeOnWindowClose() -> Bool {
        listing != nil && openedArchiveFromHome
    }

    func cleanupPreviewTempFiles() {
        quickLookRefreshTask?.cancel()
        quickLookRefreshTask = nil
        activePreviewTempDir = nil
        nestedTempDirs.removeAll()
        try? FileManager.default.removeItem(at: previewTempRoot)
    }

    func applyTrashCleanupIfScheduled(for operationID: UUID) {
        guard let urls = trashAfterSuccessByOpID.removeValue(forKey: operationID), !urls.isEmpty else { return }
        let fm = FileManager.default
        for url in urls where fm.fileExists(atPath: url.path) {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
    }

    // MARK: - Keychain Password & Preset Store Coordination

    func refreshCompressionProfiles() {
        compressionProfiles = CompressionProfileStore.shared.load()
    }

    func refreshKeychainPasswordCount() {
        savedKeychainPasswordCount = ArchiveKeychainService.shared.savedCount()
    }

    func keychainPassword(for archiveURL: URL) -> String? {
        ArchiveKeychainService.shared.password(for: archiveURL)
    }

    func stagePendingKeychainSave(password: String, save: Bool, for archiveURL: URL?) {
        guard save, !password.isEmpty, let archiveURL else {
            clearPendingKeychainSave()
            return
        }
        pendingKeychainSaveTargetURL = archiveURL
        pendingKeychainSavePassword = password
    }

    func commitPendingKeychainSaveIfMatching(password: String?, for archiveURL: URL) {
        guard let password, !password.isEmpty,
              let target = pendingKeychainSaveTargetURL,
              let stagedPw = pendingKeychainSavePassword,
              stagedPw == password,
              ArchiveKeychainService.accountKey(for: target) == ArchiveKeychainService.accountKey(for: archiveURL) else {
            return
        }
        try? ArchiveKeychainService.shared.savePassword(password, for: archiveURL)
        clearPendingKeychainSave()
        refreshKeychainPasswordCount()
    }

    func clearPendingKeychainSave() {
        pendingKeychainSaveTargetURL = nil
        pendingKeychainSavePassword = nil
    }

    func invalidateStaleKeychainPasswordIfNeeded(for archiveURL: URL, attemptedPassword: String?) -> Bool {
        guard let attemptedPassword,
              let stored = ArchiveKeychainService.shared.password(for: archiveURL),
              stored == attemptedPassword else {
            return false
        }
        try? ArchiveKeychainService.shared.removePassword(for: archiveURL)
        refreshKeychainPasswordCount()
        return true
    }

    func clearAllSavedKeychainPasswords() {
        do {
            let count = try ArchiveKeychainService.shared.removeAllPasswords()
            refreshKeychainPasswordCount()
            statusMessage = l10n.savedPasswordsClearedStatus(count)
        } catch {
            alertMessage = l10n.operationErrorMessage(error)
        }
    }
}
