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
        hudModel.onOperationSucceeded = { [weak self] operation, _ in
            guard let self else { return }
            self.applyTrashCleanupIfScheduled(for: operation.id)
        }
    }

    func configureInAppHUD() {
        guard !isInAppHUDConfigured else { return }
        isInAppHUDConfigured = true
        inAppTaskHUD.completionAutoDismissDelay = 1.05
        inAppTaskHUD.cancelledAutoDismissDelay = 0.75
        inAppTaskHUD.onOperationSucceeded = { [weak self] operation, resultURL in
            guard let self else { return }
            self.applyTrashCleanupIfScheduled(for: operation.id)
            switch operation {
            case .compress(_, _, _, let options):
                if self.inAppTaskHUD.pendingQueue.isEmpty {
                    self.openArchive(
                        url: resultURL,
                        password: options.encryption == .none ? nil : options.password,
                        encoding: options.encoding
                    )
                } else {
                    self.statusMessage = "-> \(resultURL.lastPathComponent)"
                }
            case .extract(_, let archiveURL, let options):
                if archiveURL == self.listing?.archiveURL, let pw = options.password, !pw.isEmpty {
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
        return ["smartExtract", "extractSubfolder", "compressZip", "compressEachZip", "compressTarZst", "compress7z", "compressQuickPreset"].contains(op)
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
            boltActivateAppToForeground()
        case "open":
            onRequestShowMainWindow?()
            boltActivateAppToForeground()
            if let first = BoltArchiveEngine.filterArchiveURLs(paths).first ?? paths.first {
                openArchive(url: first, fromExternalFinder: true)
            }
        case "testIntegrity":
            let archives = BoltArchiveEngine.filterArchiveURLs(paths)
            if !archives.isEmpty {
                onRequestShowMainWindow?()
                boltActivateAppToForeground()
                testIntegrityBatch(archiveURLs: archives)
            }
        case "smartExtract":
            let archives = BoltArchiveEngine.filterArchiveURLs(paths)
            if !archives.isEmpty { quickExtractBatchInHUD(mode: .smart, archiveURLs: archives) }
        case "extractSubfolder":
            let archives = BoltArchiveEngine.filterArchiveURLs(paths)
            if !archives.isEmpty { quickExtractBatchInHUD(mode: .subfolder, archiveURLs: archives) }
        case "extractTo":
            let archives = BoltArchiveEngine.filterArchiveURLs(paths)
            if !archives.isEmpty {
                boltActivateAppToForeground()
                let panel = NSOpenPanel()
                panel.title = l10n.selectExtractDestTitle
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let dest = panel.url {
                    quickExtractBatchInHUD(mode: defaultExtractMode.extractMode, archiveURLs: archives, destinationOverride: dest)
                }
            }
        case "compressZip":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .zip, algorithm: .deflate) }
        case "compressEachZip":
            if !paths.isEmpty { quickCompressEachToZipInHUD(inputs: paths) }
        case "compressTarZst":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .tarZst, algorithm: .zstd) }
        case "compress7z":
            if !paths.isEmpty { quickCompressInHUD(inputs: paths, format: .sevenZip, algorithm: .xz) }
        case "recoverZip":
            let archives = BoltArchiveEngine.filterArchiveURLs(paths)
            if let first = archives.first ?? paths.first {
                onRequestShowMainWindow?()
                boltActivateAppToForeground()
                openRecoverZipPanel(sourceURL: first)
            }
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
            excludeMacJunk: defaultStripMacJunk,
            preserveSymlinks: preserveSymlinksOnCreate
        )
        hudModel.enqueue(.compress(inputs: inputs, outputURL: outputURL, options: options))
    }

    func quickCompressEachToZipInHUD(inputs: [URL]) {
        guard !inputs.isEmpty else { return }
        configureHUD()
        let options = CreateArchiveOptions(
            format: .zip,
            algorithm: .deflate,
            level: nil,
            encryption: .none,
            password: nil,
            splitVolumeSizeBytes: nil,
            excludeMacJunk: defaultStripMacJunk,
            preserveSymlinks: preserveSymlinksOnCreate
        )
        for item in inputs {
            let outURL = QuickTaskHUDModel.computeQuickCompressDestination(inputs: [item], format: .zip)
            hudModel.enqueue(.compress(inputs: [item], outputURL: outURL, options: options))
        }
    }

    func quickExtractInHUD(mode: ExtractMode, archiveURL: URL) {
        quickExtractBatchInHUD(mode: mode, archiveURLs: [archiveURL])
    }

    func quickExtractBatchInHUD(mode: ExtractMode, archiveURLs: [URL], destinationOverride: URL? = nil, useInAppHUD: Bool = false) {
        guard !archiveURLs.isEmpty else { return }
        if useInAppHUD {
            configureInAppHUD()
        } else {
            configureHUD()
            isPreparingHUDExtract = true
        }
        let initialPlans: [(archiveURL: URL, options: ExtractOptions)] = archiveURLs.map { archiveURL in
            let dest = destinationOverride ?? archiveURL.deletingLastPathComponent()
            return (archiveURL, makeQuickExtractOptions(destination: dest, mode: mode, password: nil))
        }

        Task.detached(priority: .userInitiated) {
            var checked: [(archiveURL: URL, options: ExtractOptions, conflicts: ExtractConflictSummary?)] = []
            checked.reserveCapacity(initialPlans.count)
            var seenArchives: Set<String> = []
            var protectedSources: [URL] = []
            for plan in initialPlans {
                var options = plan.options
                let sources = (try? BoltArchiveEngine.extractionSourceURLs(archiveURL: plan.archiveURL)) ?? [plan.archiveURL]
                let key = Self.batchExtractionPathKey(sources.first ?? plan.archiveURL)
                guard seenArchives.insert(key).inserted else { continue }
                protectedSources.append(contentsOf: sources)
                let summary: ExtractConflictSummary?
                do {
                    summary = try BoltArchiveEngine.detectExtractConflicts(archiveURL: plan.archiveURL, options: options)
                } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                    // The HUD retries after unlocking; without a conflict check keep both files.
                    options.overwritePolicy = .rename
                    summary = nil
                } catch {
                    summary = nil
                }
                checked.append((plan.archiveURL, options, summary))
            }

            let extractionPlans = checked
            let inputArchives = protectedSources
            await MainActor.run {
                let conflicting = extractionPlans.filter { $0.conflicts?.hasConflicts == true }
                var chosenOverwritePolicy: OverwritePolicy = .overwrite

                if !conflicting.isEmpty {
                    boltActivateAppToForeground()
                    let l = self.l10n
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = l.extractConflictTitle
                    if conflicting.count == 1, let single = conflicting.first, let summary = single.conflicts {
                        alert.informativeText = l.extractConflictMessage(
                            folder: summary.destinationRoot.lastPathComponent,
                            names: summary.conflictingNames
                        )
                    } else {
                        let summaryPairs = conflicting.compactMap { item -> (archiveName: String, conflictingNames: [String])? in
                            guard let summary = item.conflicts else { return nil }
                            return (item.archiveURL.lastPathComponent, summary.conflictingNames)
                        }
                        alert.informativeText = l.batchExtractConflictMessage(archives: summaryPairs)
                    }
                    alert.addButton(withTitle: l.overwriteExistingBtn)
                    alert.addButton(withTitle: l.keepBothRenameBtn)
                    alert.addButton(withTitle: l.cancel)

                    let response = alert.runModal()
                    if !useInAppHUD { self.isPreparingHUDExtract = false }
                    switch response {
                    case .alertFirstButtonReturn:
                        chosenOverwritePolicy = .overwrite
                    case .alertSecondButtonReturn:
                        chosenOverwritePolicy = .rename
                    default:
                        if !useInAppHUD && self.hudModel.phase == .idle && !self.hasVisibleMainWindow {
                            self.onHUDDidHide?()
                        }
                        return
                    }
                } else {
                    if !useInAppHUD { self.isPreparingHUDExtract = false }
                }

                let targetHUD = useInAppHUD ? self.inAppTaskHUD : self.hudModel
                let policies = Self.batchExtractionPolicies(
                    for: extractionPlans.map { ($0.options, $0.conflicts) }, requestedPolicy: chosenOverwritePolicy
                )
                for (item, policy) in zip(extractionPlans, policies) {
                    var finalOpts = item.options
                    finalOpts.protectedArchiveURLs = inputArchives
                    finalOpts.overwritePolicy = policy
                    targetHUD.enqueue(.extract(archiveURL: item.archiveURL, options: finalOpts))
                }
            }
        }
    }

    nonisolated static func batchExtractionPolicies(
        for jobs: [(options: ExtractOptions, conflicts: ExtractConflictSummary?)], requestedPolicy: OverwritePolicy
    ) -> [OverwritePolicy] {
        var previousOutputs: Set<String> = []
        var uninspectedDestinations: Set<String> = []
        return jobs.map { job in
            let destination = batchExtractionPathKey(job.options.destinationURL)
            let outputs = job.conflicts?.outputLocations.map(batchExtractionPathKey) ?? []
            let overlapsEarlierOutput = outputs.contains { path in
                previousOutputs.contains { prior in path == prior || path.hasPrefix(prior + "/") || prior.hasPrefix(path + "/") }
            }
            let mayOverwrite = job.conflicts?.hasConflicts == true && requestedPolicy == .overwrite &&
                !overlapsEarlierOutput && !uninspectedDestinations.contains(destination)
            if job.conflicts == nil { uninspectedDestinations.insert(destination) }
            previousOutputs.formUnion(outputs)
            return mayOverwrite ? .overwrite : .rename
        }
    }

    func handleDroppedOrOpenedURLs(_ urls: [URL], fromExternalFinder: Bool = false) {
        guard let first = urls.first else { return }
        Task.detached(priority: .userInitiated) {
            let areArchives = BoltArchiveEngine.filterArchiveURLs(urls).count == urls.count
            await MainActor.run {
                if areArchives && urls.count == 1 {
                    self.openArchive(url: first, fromExternalFinder: fromExternalFinder)
                } else if areArchives {
                    self.pendingBatchArchiveDrop = PendingBatchArchivePrompt(urls: urls)
                } else {
                    self.presentStandaloneCompressWizard(inputs: urls)
                }
            }
        }
    }

    func executeBatchArchiveDropAction(urls: [URL], mode: ExtractMode) {
        guard let first = urls.first, let dest = selectExtractDestination(for: first) else { return }
        quickExtractBatchInHUD(mode: mode, archiveURLs: urls, destinationOverride: dest, useInAppHUD: true)
    }

    private nonisolated static func batchExtractionPathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
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
