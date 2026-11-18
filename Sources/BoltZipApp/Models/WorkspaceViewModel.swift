import AppKit
import BoltZipCore
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class WorkspaceViewModel {
    var listing: ArchiveListing?
    var openedArchiveFromHome: Bool = false
    var currentFolder: String = ""
    var folderForwardStack: [String] = []
    var selectedEntryIDs: Set<String> = []
    var searchText: String = ""
    var encodingOption: FilenameEncodingOption = .auto
    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var columnVisibility: NavigationSplitViewVisibility = .all

    var isBusy: Bool = false
    var progress: OperationProgress?
    var statusMessage: String = ""
    var alertMessage: String?
    var pendingExtractConflict: PendingExtractConflict?
    var activeSheet: ActiveSheet?
    var savedPassword: String?

    var recentArchivePaths: [String] = []
    var defaultStripMacJunk: Bool = true
    var quickActionsInstalled: Bool = false
    var associationStatuses: [ArchiveAssociationStatus] = []
    var isUpdatingAssociations: Bool = false

    // Localization, Window Behavior, Translucency & Modular Panel Visibility Preferences
    var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            onLanguageChanged?()
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
    var useWhiteAppIcon: Bool = false {
        didSet {
            UserDefaults.standard.set(useWhiteAppIcon, forKey: Keys.whiteAppIcon)
            BoltAppIconRenderer.apply(whiteBackground: useWhiteAppIcon)
        }
    }

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
        static let whiteAppIcon = "BoltZip.UseWhiteAppIcon"
    }

    var supportsLiquidGlass: Bool { BoltPlatformCapabilities.supportsLiquidGlass }
    var effectiveWindowTranslucency: Bool { supportsLiquidGlass && isWindowTranslucent }
    var l10n: L10n { L10n(language: appLanguage) }
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
        if defaults.object(forKey: Keys.whiteAppIcon) != nil {
            self.useWhiteAppIcon = defaults.bool(forKey: Keys.whiteAppIcon)
        }
        self.statusMessage = L10n(language: self.appLanguage).readyStatus
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
}
