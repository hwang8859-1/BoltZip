import AppKit
import BoltZipCore
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct FolderTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    var children: [FolderTreeNode]
    let fileCount: Int
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func title(_ l: L10n) -> String {
        switch self {
        case .system: return l.themeSystem
        case .light: return l.themeLight
        case .dark: return l.themeDark
        }
    }
}

enum SortColumn: String, CaseIterable, Identifiable {
    case name
    case uncompressedSize
    case compressedSize
    case ratio
    case method
    case modifiedDate

    var id: String { rawValue }
}

enum ActiveSheet: Identifiable {
    case createArchive([URL])
    case extractOptions(ExtractMode)
    case integrityReport(IntegrityReport)
    case benchmark
    case passwordPrompt(PasswordPurpose)
    case createFolder(parentFolder: String)
    case renamePath(oldPath: String, currentName: String)
    case entryProperties(ArchiveEntry)

    var id: String {
        switch self {
        case .createArchive: return "createArchive"
        case .extractOptions: return "extractOptions"
        case .integrityReport: return "integrityReport"
        case .benchmark: return "benchmark"
        case .passwordPrompt: return "passwordPrompt"
        case .createFolder(let parent): return "createFolder-\(parent)"
        case .renamePath(let oldPath, _): return "rename-\(oldPath)"
        case .entryProperties(let e): return "props-\(e.id)"
        }
    }
}

enum PasswordPurpose {
    case preview(ArchiveEntry)
    case extract(archiveURL: URL, options: ExtractOptions)
    case testIntegrity(archiveURL: URL)
}

@Observable
@MainActor
final class WorkspaceViewModel {
    var listing: ArchiveListing?
    var currentFolder: String = ""
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
    var activeSheet: ActiveSheet?
    var savedPassword: String?

    var recentArchivePaths: [String] = []
    var defaultStripMacJunk: Bool = true
    var quickActionsInstalled: Bool = QuickActionInstaller.isExtensionEnabled()

    // Localization, Translucency & Modular Panel Visibility Preferences
    var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage)
        }
    }
    var appTheme: AppTheme = .system {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme)
            NSApp.appearance = appTheme.nsAppearance
        }
    }
    var isWindowTranslucent: Bool = true {
        didSet {
            UserDefaults.standard.set(isWindowTranslucent, forKey: Keys.windowTranslucent)
        }
    }
    var windowBackgroundOpacity: Double = 0.72 {
        didSet {
            UserDefaults.standard.set(windowBackgroundOpacity, forKey: Keys.windowOpacity)
        }
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

    var l10n: L10n { L10n(language: appLanguage) }

    private enum Keys {
        static let recents = "BoltZip.RecentArchives"
        static let stripJunk = "BoltZip.ExcludeMacJunk"
        static let appLanguage = "BoltZip.AppLanguage"
        static let appTheme = "BoltZip.AppTheme"
        static let windowTranslucent = "BoltZip.IsWindowTranslucent"
        static let windowOpacity = "BoltZip.WindowOpacity"
        static let showFinderBanner = "BoltZip.ShowFinderBanner"
        static let showFeatures = "BoltZip.ShowFeatureHighlights"
        static let showRecents = "BoltZip.ShowRecentArchives"
        static let showInspector = "BoltZip.ShowSidebarInspector"
        static let showStatusBar = "BoltZip.ShowStatusBar"
    }

    private let previewTempRoot: URL

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
        NSApp.appearance = self.appTheme.nsAppearance
        if defaults.object(forKey: Keys.windowTranslucent) != nil {
            self.isWindowTranslucent = defaults.bool(forKey: Keys.windowTranslucent)
        }
        if defaults.object(forKey: Keys.windowOpacity) != nil {
            self.windowBackgroundOpacity = defaults.double(forKey: Keys.windowOpacity)
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
        self.statusMessage = L10n(language: self.appLanguage).readyStatus
    }

    var recentArchiveURLs: [URL] {
        recentArchivePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func updateDefaultStripMacJunk(_ value: Bool) {
        defaultStripMacJunk = value
        UserDefaults.standard.set(value, forKey: Keys.stripJunk)
    }

    func refreshQuickActionsStatus() {
        quickActionsInstalled = QuickActionInstaller.isExtensionEnabled()
    }

    func installFinderQuickActions() -> String {
        do {
            let enabled = try QuickActionInstaller.installTopLevelFinderMenu()
            refreshQuickActionsStatus()
            if enabled {
                statusMessage = l10n.finderBannerEnabledTitle
                return l10n.finderBannerEnabledTitle
            } else {
                QuickActionInstaller.openSystemExtensionSettings()
                return l10n.finderDisabledSummary
            }
        } catch {
            return error.localizedDescription
        }
    }

    func openFinderExtensionSettings() {
        QuickActionInstaller.openSystemExtensionSettings()
    }

    func uninstallFinderQuickActions() {
        QuickActionInstaller.disableTopLevelFinderMenu()
        try? QuickActionInstaller.uninstallLegacyWorkflows()
        refreshQuickActionsStatus()
        statusMessage = l10n.finderDisabledSummary
    }

    func restoreAllHomeSections() {
        showFinderBanner = true
        showFeatureHighlights = true
        showRecentArchives = true
        showSidebarInspector = true
        showStatusBar = true
    }

    // MARK: - Breadcrumbs & Folder Tree

    var breadcrumbComponents: [(title: String, path: String)] {
        var crumbs: [(String, String)] = [(l10n.rootLabel, "")]
        let parts = currentFolder.split(separator: "/").map(String.init)
        var acc = ""
        for p in parts {
            acc += p + "/"
            crumbs.append((p, acc))
        }
        return crumbs
    }

    var canNavigateUp: Bool { !currentFolder.isEmpty }

    func navigateUp() {
        guard canNavigateUp else { return }
        let trimmed = currentFolder.hasSuffix("/") ? String(currentFolder.dropLast()) : currentFolder
        if let idx = trimmed.lastIndex(of: "/") {
            currentFolder = String(trimmed[..<idx]) + "/"
        } else {
            currentFolder = ""
        }
        selectedEntryIDs.removeAll()
    }

    var folderTree: FolderTreeNode {
        guard let entries = listing?.entries else {
            return FolderTreeNode(id: "", name: l10n.rootLabel, path: "", children: [], fileCount: 0)
        }

        var allFolders: Set<String> = [""]
        var directFileCount: [String: Int] = [:]

        for entry in entries {
            let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = clean.split(separator: "/").map(String.init)
            if entry.isDirectory {
                var acc = ""
                for p in parts {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
            } else {
                var acc = ""
                for p in parts.dropLast() {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
                directFileCount[acc, default: 0] += 1
            }
        }

        func buildNode(path: String, name: String) -> FolderTreeNode {
            let directChildren = allFolders
                .filter { candidate in
                    guard candidate != path, candidate.hasPrefix(path) else { return false }
                    let rem = String(candidate.dropFirst(path.count))
                    let parts = rem.split(separator: "/")
                    return parts.count == 1
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { childPath -> FolderTreeNode in
                    let trimmed = childPath.hasSuffix("/") ? String(childPath.dropLast()) : childPath
                    let childName = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
                    return buildNode(path: childPath, name: childName)
                }
            return FolderTreeNode(
                id: path,
                name: name,
                path: path,
                children: directChildren,
                fileCount: directFileCount[path, default: 0]
            )
        }

        return buildNode(path: "", name: listing?.archiveURL.lastPathComponent ?? l10n.rootLabel)
    }

    var visibleEntries: [ArchiveEntry] {
        guard let entries = listing?.entries else { return [] }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [ArchiveEntry]

        if !query.isEmpty {
            items = entries.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }
        } else {
            let prefix = currentFolder
            var directByPath: [String: ArchiveEntry] = [:]

            for entry in entries where entry.path.hasPrefix(prefix) && entry.path != prefix {
                let remainder = String(entry.path.dropFirst(prefix.count))
                let parts = remainder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard let first = parts.first else { continue }
                if parts.count == 1 && !entry.isDirectory {
                    directByPath[entry.path] = entry
                } else {
                    let folderPath = prefix + first + "/"
                    if directByPath[folderPath] == nil {
                        directByPath[folderPath] = ArchiveEntry(
                            path: folderPath,
                            isDirectory: true,
                            uncompressedSize: 0,
                            compressedSize: 0,
                            compressionMethodName: "Folder",
                            crc32: 0,
                            modifiedDate: entry.modifiedDate,
                            permissions: 0o755
                        )
                    }
                }
            }
            items = Array(directByPath.values)
        }

        items.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            let cmp: Bool
            switch sortColumn {
            case .name:
                cmp = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .uncompressedSize:
                cmp = lhs.uncompressedSize < rhs.uncompressedSize
            case .compressedSize:
                cmp = lhs.compressedSize < rhs.compressedSize
            case .ratio:
                cmp = lhs.compressionRatioPercent < rhs.compressionRatioPercent
            case .method:
                cmp = lhs.compressionMethodName < rhs.compressionMethodName
            case .modifiedDate:
                cmp = lhs.modifiedDate < rhs.modifiedDate
            }
            return sortAscending ? cmp : !cmp
        }

        return items
    }

    var selectedEntries: [ArchiveEntry] {
        visibleEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    // MARK: - Archive Lifecycle & Actions

    func handleIncomingURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1, let first = urls.first, first.scheme == "boltzip" {
            handleFinderSchemeURL(first)
        } else {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                handleDroppedOrOpenedURLs(fileURLs)
            }
        }
    }

    private func handleFinderSchemeURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        let op = items.first(where: { $0.name == "op" })?.value ?? "openWorkspace"
        let paths = items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }

        switch op {
        case "openWorkspace":
            NSApp.activate(ignoringOtherApps: true)
        case "open":
            if let first = paths.first { openArchive(url: first) }
        case "testIntegrity":
            if let first = paths.first { testIntegrity(archiveURL: first) }
        case "smartExtract":
            if let first = paths.first { quickExtract(mode: .smart, archiveURL: first) }
        case "extractSubfolder":
            if let first = paths.first { quickExtract(mode: .subfolder, archiveURL: first) }
        case "compressZip":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .zip, algorithm: .deflate) }
        case "compressTarZst":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .tarZst, algorithm: .zstd) }
        case "compress7z":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .sevenZip, algorithm: .xz) }
        case "compressWizard":
            if !paths.isEmpty { activeSheet = .createArchive(paths) }
        default:
            break
        }
    }

    func compressImmediate(inputs: [URL], format: ArchiveFormat, algorithm: CompressionAlgorithm) {
        guard let first = inputs.first else { return }
        let parentDir = first.deletingLastPathComponent()
        let baseName = inputs.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let stem = (inputs.count == 1 && isDirectory(first)) ? first.lastPathComponent : baseName
        var candidate = parentDir.appendingPathComponent("\(stem).\(format.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentDir.appendingPathComponent("\(stem) (\(counter)).\(format.fileExtension)")
            counter += 1
        }
        let opts = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            excludeMacJunk: defaultStripMacJunk
        )
        createArchive(inputs: inputs, outputURL: candidate, options: opts)
    }

    func handleDroppedOrOpenedURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if urls.count == 1, ArchiveFormat.detect(from: first) != nil, !isDirectory(first) {
            openArchive(url: first)
        } else {
            activeSheet = .createArchive(urls)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = l10n.openArchive
        if panel.runModal() == .OK, let url = panel.url {
            openArchive(url: url)
        }
    }

    func startNewArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = l10n.newArchive
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            activeSheet = .createArchive(panel.urls)
        }
    }

    func openArchive(url: URL) {
        let encoding = encodingOption
        isBusy = true
        statusMessage = "\(url.lastPathComponent)..."
        Task.detached(priority: .userInitiated) {
            do {
                let result = try BoltArchiveEngine.inspect(archiveURL: url, encoding: encoding)
                await MainActor.run {
                    self.listing = result
                    self.currentFolder = ""
                    self.selectedEntryIDs.removeAll()
                    self.searchText = ""
                    self.savedPassword = nil
                    self.isBusy = false
                    self.recordRecent(url)
                    self.statusMessage = "\(url.lastPathComponent) · \(self.l10n.itemCount(result.entries.count))"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func reloadWithEncoding(_ newEncoding: FilenameEncodingOption) {
        encodingOption = newEncoding
        guard let url = listing?.archiveURL else { return }
        openArchive(url: url)
    }

    func closeArchive() {
        listing = nil
        currentFolder = ""
        selectedEntryIDs.removeAll()
        searchText = ""
        savedPassword = nil
        statusMessage = l10n.readyStatus
    }

    func createArchive(inputs: [URL], outputURL: URL, options: CreateArchiveOptions) {
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: outputURL.lastPathComponent)
        statusMessage = "\(outputURL.lastPathComponent)..."

        Task.detached(priority: .userInitiated) {
            do {
                let created = try BoltArchiveEngine.createArchive(from: inputs, to: outputURL, options: options) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                let mainCreated = created.last ?? outputURL
                let refreshed = try BoltArchiveEngine.inspect(archiveURL: mainCreated, encoding: options.encoding)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.listing = refreshed
                    self.currentFolder = ""
                    self.selectedEntryIDs.removeAll()
                    self.recordRecent(mainCreated)
                    self.statusMessage = created.map(\.lastPathComponent).joined(separator: ", ")
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func quickExtract(mode: ExtractMode, archiveURL overrideURL: URL? = nil) {
        guard let targetArchive = overrideURL ?? listing?.archiveURL else { return }
        let dest = targetArchive.deletingLastPathComponent()
        let opts = ExtractOptions(
            destinationURL: dest,
            mode: mode,
            overwritePolicy: .overwrite,
            password: savedPassword,
            encoding: encodingOption,
            stripMacJunk: defaultStripMacJunk
        )
        runExtract(options: opts, archiveURL: targetArchive)
    }

    func triggerSmartExtractNow() {
        quickExtract(mode: .smart)
    }

    func runExtract(options: ExtractOptions, archiveURL overrideURL: URL? = nil) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: archiveURL.lastPathComponent)
        statusMessage = "\(archiveURL.lastPathComponent)..."

        Task.detached(priority: .userInitiated) {
            do {
                let outDir = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: options) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if let pw = options.password, !pw.isEmpty {
                        self.savedPassword = pw
                    }
                    self.statusMessage = "-> \(outDir.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([outDir])
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.activeSheet = .passwordPrompt(.extract(archiveURL: archiveURL, options: options))
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func exportSelectedAsNewZip(entryIDs: Set<String>) {
        guard let sourceArchive = listing?.archiveURL, !entryIDs.isEmpty else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = "Selected_Export.zip"
        guard savePanel.runModal() == .OK, let destZip = savePanel.url else { return }

        let pw = savedPassword
        let enc = encodingOption
        let strip = defaultStripMacJunk
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0.1, currentItem: destZip.lastPathComponent)

        Task.detached(priority: .userInitiated) {
            let tempStage = FileManager.default.temporaryDirectory
                .appendingPathComponent("BoltZipExport-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempStage) }
            do {
                let extOpts = ExtractOptions(
                    destinationURL: tempStage,
                    mode: .selected(entryIDs),
                    overwritePolicy: .overwrite,
                    password: pw,
                    encoding: enc,
                    stripMacJunk: strip
                )
                _ = try BoltArchiveEngine.extract(archiveURL: sourceArchive, options: extOpts)
                let children = try FileManager.default.contentsOfDirectory(at: tempStage, includingPropertiesForKeys: nil)
                let createOpts = CreateArchiveOptions(format: .zip, algorithm: .deflate, excludeMacJunk: strip)
                _ = try BoltArchiveEngine.createArchive(from: children, to: destZip, options: createOpts)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.statusMessage = destZip.lastPathComponent
                    NSWorkspace.shared.activateFileViewerSelecting([destZip])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func testIntegrity(password: String? = nil, archiveURL overrideURL: URL? = nil) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: "CRC32 / HMAC...")

        Task.detached(priority: .userInitiated) {
            do {
                let report = try BoltArchiveEngine.testIntegrity(archiveURL: archiveURL, password: pw, encoding: enc) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if report.skippedEncryptedCount > 0 && pw == nil {
                        self.activeSheet = .passwordPrompt(.testIntegrity(archiveURL: archiveURL))
                    } else {
                        if let pw, !pw.isEmpty { self.savedPassword = pw }
                        self.activeSheet = .integrityReport(report)
                        self.statusMessage = "\(report.passedCount)/\(report.totalEntries)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func previewOrOpenEntry(_ entry: ArchiveEntry, password: String? = nil) {
        if entry.isDirectory {
            currentFolder = entry.path
            selectedEntryIDs.removeAll()
            return
        }
        guard let archiveURL = listing?.archiveURL else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot

        isBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                let data = try BoltArchiveEngine.readEntryData(
                    archiveURL: archiveURL,
                    entryPath: entry.path,
                    password: pw,
                    encoding: enc
                )
                let subDir = previewRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
                let fileURL = subDir.appendingPathComponent(entry.name)
                try data.write(to: fileURL, options: .atomic)

                await MainActor.run {
                    self.isBusy = false
                    if let pw, !pw.isEmpty { self.savedPassword = pw }
                    self.statusMessage = entry.name
                    QuickLookPreviewController.shared.preview(url: fileURL)
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = .passwordPrompt(.preview(entry))
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - In-Place ZIP Editing

    func addItemsToCurrentZipPanel(targetFolder: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.title = l10n.ctxAddHere
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let folder = targetFolder ?? currentFolder
            editCurrentZip([.addItems(urls: panel.urls, targetFolder: folder)])
        }
    }

    func addItemsToCurrentZip(_ urls: [URL], targetFolder: String? = nil) {
        editCurrentZip([.addItems(urls: urls, targetFolder: targetFolder ?? currentFolder)])
    }

    func createFolderInZip(parentFolder: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
        guard !trimmed.isEmpty else { return }
        editCurrentZip([.createFolder(path: parentFolder + trimmed + "/")])
    }

    func renamePath(_ oldPath: String, to newName: String) {
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
        guard !cleanNew.isEmpty else { return }
        let isDir = oldPath.hasSuffix("/")
        let trimmedOld = isDir ? String(oldPath.dropLast()) : oldPath
        let parentPrefix: String
        if let idx = trimmedOld.lastIndex(of: "/") {
            parentPrefix = String(trimmedOld[..<idx]) + "/"
        } else {
            parentPrefix = ""
        }
        let newPath = parentPrefix + cleanNew + (isDir ? "/" : "")
        editCurrentZip([.renamePath(oldPath: oldPath, newPath: newPath)])
    }

    func deletePaths(_ targets: Set<String>) {
        guard !targets.isEmpty else { return }
        editCurrentZip([.deletePaths(targets)])
    }

    func deleteSelectedEntries() {
        deletePaths(Set(selectedEntries.map(\.path)))
    }

    private func editCurrentZip(_ ops: [ZipEditOperation]) {
        guard let listing, listing.format.supportsInPlaceEditing else { return }
        let url = listing.archiveURL
        let enc = encodingOption
        let opts = CreateArchiveOptions(
            format: .zip,
            algorithm: .deflate,
            encryption: savedPassword == nil ? .none : .aes256,
            password: savedPassword,
            excludeMacJunk: defaultStripMacJunk
        )
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: url.lastPathComponent)

        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.editZip(at: url, operations: ops, options: opts, encoding: enc) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                let updated = try BoltArchiveEngine.inspect(archiveURL: url, encoding: enc)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.listing = updated
                    self.selectedEntryIDs.removeAll()
                    self.statusMessage = "\(updated.archiveURL.lastPathComponent) · \(self.l10n.itemCount(updated.entries.count))"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Utilities

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = text
    }

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeRecent(_ url: URL) {
        recentArchivePaths.removeAll { $0 == url.path }
        UserDefaults.standard.set(recentArchivePaths, forKey: Keys.recents)
    }

    func openShowcaseWebsite() {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("showcase/index.html"),
           FileManager.default.fileExists(atPath: bundled.path) {
            NSWorkspace.shared.open(bundled)
            return
        }

        // Dynamic ancestor lookup (zero hardcoded local paths)
        let roots = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]
        for base in roots {
            var cur = base
            for _ in 0..<6 {
                let candidate = cur.appendingPathComponent("showcase/index.html")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    NSWorkspace.shared.open(candidate)
                    return
                }
                let parent = cur.deletingLastPathComponent()
                if parent.path == cur.path { break }
                cur = parent
            }
        }

        if let repoURL = URL(string: "https://github.com/hwang8859-1/BoltZip") {
            NSWorkspace.shared.open(repoURL)
        }
    }

    private func recordRecent(_ url: URL) {
        var paths = recentArchivePaths.filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 8 { paths = Array(paths.prefix(8)) }
        recentArchivePaths = paths
        UserDefaults.standard.set(paths, forKey: Keys.recents)
    }
}
