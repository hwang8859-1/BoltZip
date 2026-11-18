import AppKit
import BoltZipCore
import Combine
import Foundation
import SwiftUI

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var listing: ArchiveListing?
    @Published var openedArchiveFromHome: Bool = false
    @Published var currentFolder: String = ""
    @Published var folderForwardStack: [String] = []
    @Published var selectedEntryIDs: Set<String> = []
    @Published var searchText: String = ""
    @Published var encodingOption: FilenameEncodingOption = .auto
    @Published var sortColumn: SortColumn = .name
    @Published var sortAscending: Bool = true
    @Published var isSidebarVisible: Bool = true

    @Published var isBusy: Bool = false
    @Published var progress: OperationProgress?
    @Published var statusMessage: String = ""
    @Published var alertMessage: String?
    @Published var pendingExtractConflict: PendingExtractConflict?
    @Published var activeSheet: ActiveSheet?
    @Published var savedPassword: String?

    @Published var recentArchivePaths: [String] = []
    @Published var defaultStripMacJunk: Bool = true
    @Published var quickActionsInstalled: Bool = false
    @Published var associationStatuses: [ArchiveAssociationStatus] = []
    @Published var isUpdatingAssociations: Bool = false

    // Localization, Window Behavior, Translucency & Modular Panel Visibility Preferences
    @Published var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            onLanguageChanged?()
        }
    }
    @Published var appTheme: AppTheme = .system {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme)
            (NSApp as NSApplication?)?.appearance = appTheme.nsAppearance
        }
    }
    @Published var isWindowTranslucent: Bool = true {
        didSet {
            UserDefaults.standard.set(isWindowTranslucent, forKey: Keys.windowTranslucent)
        }
    }
    @Published var glassIntensity: Double = 0.75 {
        didSet {
            UserDefaults.standard.set(glassIntensity, forKey: Keys.glassIntensity)
        }
    }
    var windowBackgroundOpacity: Double {
        get { max(0.05, 1.0 - glassIntensity) }
        set { glassIntensity = min(max(1.0 - newValue, 0.0), 1.0) }
    }
    @Published var appBackgroundColor: AppBackgroundColor = .pureWhite {
        didSet {
            UserDefaults.standard.set(appBackgroundColor.rawValue, forKey: Keys.appBackgroundColor)
        }
    }
    @Published var customBackgroundRed: Double = 0.94 {
        didSet { UserDefaults.standard.set(customBackgroundRed, forKey: Keys.customBgR) }
    }
    @Published var customBackgroundGreen: Double = 0.96 {
        didSet { UserDefaults.standard.set(customBackgroundGreen, forKey: Keys.customBgG) }
    }
    @Published var customBackgroundBlue: Double = 0.99 {
        didSet { UserDefaults.standard.set(customBackgroundBlue, forKey: Keys.customBgB) }
    }
    @Published var showFinderBanner: Bool = true {
        didSet {
            UserDefaults.standard.set(showFinderBanner, forKey: Keys.showFinderBanner)
        }
    }
    @Published var showFeatureHighlights: Bool = true {
        didSet {
            UserDefaults.standard.set(showFeatureHighlights, forKey: Keys.showFeatures)
        }
    }
    @Published var showRecentArchives: Bool = true {
        didSet {
            UserDefaults.standard.set(showRecentArchives, forKey: Keys.showRecents)
        }
    }
    @Published var showSidebarInspector: Bool = true {
        didSet {
            UserDefaults.standard.set(showSidebarInspector, forKey: Keys.showInspector)
        }
    }
    @Published var showStatusBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showStatusBar, forKey: Keys.showStatusBar)
        }
    }
    @Published var useWhiteAppIcon: Bool = false {
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
    @Published var isPreparingHUDExtract: Bool = false

    var onRequestShowMainWindow: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?
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
