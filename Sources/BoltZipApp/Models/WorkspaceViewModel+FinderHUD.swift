import AppKit
import BoltZipCore
import Foundation

extension WorkspaceViewModel {
    // MARK: - Finder Integration & Home Section Toggles

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

    // MARK: - Default Archive Associations

    func refreshArchiveAssociations() {
        associationStatuses = DefaultArchiveAssociationService.currentStatuses()
    }

    func setArchiveAssociation(groups: [ArchiveAssociationGroup], toBoltZip: Bool) async -> (message: String, isError: Bool) {
        isUpdatingAssociations = true
        defer {
            isUpdatingAssociations = false
            refreshArchiveAssociations()
        }
        if let err = await DefaultArchiveAssociationService.setDefault(for: groups, toBoltZip: toBoltZip) {
            return (err, true)
        }
        statusMessage = l10n.defaultAppUpdatedSuccess
        return (l10n.defaultAppUpdatedSuccess, false)
    }

    func restoreAllHomeSections() {
        showFinderBanner = true
        showFeatureHighlights = true
        showRecentArchives = true
        showSidebarInspector = true
        showStatusBar = true
    }

    // MARK: - HUD Configuration & URL Routing

    func configureHUD() {
        compressWindowController.onDidClose = { [weak self] in
            self?.onCompressWindowDidClose?()
        }
        guard !isHUDConfigured else { return }
        isHUDConfigured = true
        hudWindowController.bind(viewModel: self, hudModel: hudModel)
        hudWindowController.onDidHide = { [weak self] in
            self?.onHUDDidHide?()
        }
    }

    func configureInAppHUD() {
        guard !isInAppHUDConfigured else { return }
        isInAppHUDConfigured = true
        inAppTaskHUD.completionAutoDismissDelay = 1.05
        inAppTaskHUD.cancelledAutoDismissDelay = 0.75
        inAppTaskHUD.onOperationSucceeded = { [weak self] operation, resultURL in
            guard let self else { return }
            switch operation {
            case .compress(_, _, _, let options):
                self.statusMessage = resultURL.lastPathComponent
                let encoding = options.encoding
                let fromHomeOrigin = (self.listing == nil) ? true : self.openedArchiveFromHome
                Task.detached(priority: .userInitiated) {
                    if let refreshed = try? BoltArchiveEngine.inspect(archiveURL: resultURL, encoding: encoding) {
                        await MainActor.run {
                            self.listing = refreshed
                            self.openedArchiveFromHome = fromHomeOrigin
                            self.currentFolder = ""
                            self.selectedEntryIDs.removeAll()
                            self.searchText = ""
                            self.recordRecent(resultURL)
                            self.statusMessage = "\(resultURL.lastPathComponent) · \(self.l10n.itemCount(refreshed.entries.count))"
                        }
                    }
                }
            case .extract(_, _, let options):
                if let pw = options.password, !pw.isEmpty {
                    self.savedPassword = pw
                }
                self.statusMessage = "-> \(resultURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([resultURL])
            }
        }
    }

    static func isHUDOnlyURL(_ url: URL) -> Bool {
        guard url.scheme == "boltzip" else { return false }
        if url.host == "hud" { return true }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let op = comps.queryItems?.first(where: { $0.name == "op" })?.value else {
            return false
        }
        return ["smartExtract", "extractSubfolder", "compressZip", "compressTarZst", "compress7z"].contains(op)
    }

    static func isStandaloneCompressURL(_ url: URL) -> Bool {
        guard url.scheme == "boltzip",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let op = comps.queryItems?.first(where: { $0.name == "op" })?.value else {
            return false
        }
        return op == "compressWizard"
    }

    func handleIncomingURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let schemeURLs = urls.filter { $0.scheme == "boltzip" }
        if !schemeURLs.isEmpty {
            for schemeURL in schemeURLs {
                handleFinderSchemeURL(schemeURL)
            }
            return
        }
        let fileURLs = urls.filter { $0.isFileURL }
        if !fileURLs.isEmpty {
            let startedWithVisibleHome = (listing == nil && hasVisibleMainWindow)
            onRequestShowMainWindow?()
            handleDroppedOrOpenedURLs(fileURLs, fromExternalFinder: !startedWithVisibleHome)
        }
    }

    private func handleFinderSchemeURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        let op = items.first(where: { $0.name == "op" })?.value ?? "openWorkspace"
        let paths = items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }

        switch op {
        case "openWorkspace":
            onRequestShowMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        case "open":
            onRequestShowMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
            if let first = paths.first { openArchive(url: first, fromExternalFinder: true) }
        case "testIntegrity":
            onRequestShowMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
            if let first = paths.first { testIntegrity(archiveURL: first) }
        case "smartExtract":
            if let first = paths.first { quickExtractInHUD(mode: .smart, archiveURL: first) }
        case "extractSubfolder":
            if let first = paths.first { quickExtractInHUD(mode: .subfolder, archiveURL: first) }
        case "compressZip":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .zip, algorithm: .deflate) }
        case "compressTarZst":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .tarZst, algorithm: .zstd) }
        case "compress7z":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .sevenZip, algorithm: .xz) }
        case "compressWizard":
            if !paths.isEmpty {
                presentStandaloneCompressWizard(inputs: paths)
            }
        default:
            break
        }
    }

    func presentStandaloneCompressWizard(inputs: [URL]) {
        guard !inputs.isEmpty else { return }
        configureHUD()
        compressWindowController.show(viewModel: self, inputs: inputs)
    }

    func quickCompressInHUD(inputs: [URL], format: ArchiveFormat, algorithm: CompressionAlgorithm) {
        guard !inputs.isEmpty else { return }
        configureHUD()
        let outputURL = QuickTaskHUDModel.computeQuickCompressDestination(inputs: inputs, format: format)
        let options = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            level: nil,
            encryption: .none,
            password: nil,
            splitVolumeSizeBytes: nil,
            excludeMacJunk: defaultStripMacJunk
        )
        hudModel.enqueue(.compress(inputs: inputs, outputURL: outputURL, options: options))
    }

    func quickExtractInHUD(mode: ExtractMode, archiveURL: URL) {
        configureHUD()
        isPreparingHUDExtract = true
        let destDir = archiveURL.deletingLastPathComponent()
        let options = ExtractOptions(
            destinationURL: destDir,
            mode: mode,
            overwritePolicy: .overwrite,
            password: nil,
            encoding: encodingOption,
            stripMacJunk: defaultStripMacJunk
        )
        Task.detached(priority: .userInitiated) {
            let conflicts = try? BoltArchiveEngine.detectExtractConflicts(archiveURL: archiveURL, options: options)
            await MainActor.run {
                if let conflicts, conflicts.hasConflicts {
                    NSApp.activate(ignoringOtherApps: true)
                    let l = self.l10n
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = l.extractConflictTitle
                    alert.informativeText = l.extractConflictMessage(
                        folder: conflicts.destinationRoot.lastPathComponent,
                        names: conflicts.conflictingNames
                    )
                    alert.addButton(withTitle: l.overwriteExistingBtn)
                    alert.addButton(withTitle: l.keepBothRenameBtn)
                    alert.addButton(withTitle: l.cancel)

                    let response = alert.runModal()
                    self.isPreparingHUDExtract = false
                    switch response {
                    case .alertFirstButtonReturn:
                        self.hudModel.enqueue(.extract(archiveURL: archiveURL, options: options))
                    case .alertSecondButtonReturn:
                        let renamedOpts = ExtractOptions(
                            destinationURL: options.destinationURL,
                            mode: options.mode,
                            overwritePolicy: .rename,
                            password: options.password,
                            encoding: options.encoding,
                            stripMacJunk: options.stripMacJunk
                        )
                        self.hudModel.enqueue(.extract(archiveURL: archiveURL, options: renamedOpts))
                    default:
                        self.onHUDDidHide?()
                    }
                } else {
                    self.isPreparingHUDExtract = false
                    self.hudModel.enqueue(.extract(archiveURL: archiveURL, options: options))
                }
            }
        }
    }

    func handleDroppedOrOpenedURLs(_ urls: [URL], fromExternalFinder: Bool = false) {
        guard let first = urls.first else { return }
        if urls.count == 1, ArchiveFormat.detect(from: first) != nil, !isDirectory(first) {
            openArchive(url: first, fromExternalFinder: fromExternalFinder)
        } else {
            presentStandaloneCompressWizard(inputs: urls)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: - Utilities & History

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

    func recordRecent(_ url: URL) {
        var paths = recentArchivePaths.filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 15 { paths = Array(paths.prefix(15)) }
        recentArchivePaths = paths
        UserDefaults.standard.set(paths, forKey: Keys.recents)
    }

    func openShowcaseWebsite() {
        if let publicURL = URL(string: "https://122.51.112.183/boltzip/") {
            NSWorkspace.shared.open(publicURL)
            return
        }

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
}
