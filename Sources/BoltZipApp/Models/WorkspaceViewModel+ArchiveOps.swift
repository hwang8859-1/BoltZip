import AppKit
import BoltZipCore
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

extension WorkspaceViewModel {
    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.title = l10n.openArchive
        if panel.runModal() == .OK, let url = panel.url {
            openArchive(url: url, fromExternalFinder: false)
        }
    }

    func startNewArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = l10n.newArchive
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            presentStandaloneCompressWizard(inputs: panel.urls)
        }
    }

    func openArchive(
        url: URL,
        fromExternalFinder: Bool = false,
        password: String? = nil,
        isNestedOpening: Bool = false,
        initialFolder: String = ""
    ) {
        let encoding = encodingOption
        let fromHomeOrigin: Bool = {
            if isNestedOpening { return openedArchiveFromHome }
            if fromExternalFinder { return false }
            if listing == nil { return true }
            return openedArchiveFromHome
        }()

        isBusy = true
        statusMessage = "\(url.lastPathComponent)..."
        Task.detached(priority: .userInitiated) {
            do {
                let result = try BoltArchiveEngine.inspect(archiveURL: url, encoding: encoding, password: password)
                let detectedAlgo = Self.dominantZipAlgorithm(from: result)
                let navIndex = ArchiveNavigationIndex.build(from: result, rootTitle: result.archiveURL.lastPathComponent)
                await MainActor.run {
                    if !isNestedOpening {
                        self.archiveBackStack.removeAll()
                        if self.listing?.archiveURL != url {
                            self.cleanupPreviewTempFiles()
                        }
                    } else {
                        self.activePreviewTempDir = nil
                    }
                    self.applyLoadedListing(
                        result,
                        prebuiltIndex: navIndex,
                        openedFromHome: fromHomeOrigin,
                        initialFolder: initialFolder
                    )
                    self.preferredZipEditAlgorithm = detectedAlgo
                    if let password, !password.isEmpty {
                        self.savedPassword = password
                    } else {
                        self.savedPassword = nil
                    }
                    self.isBusy = false
                    if !isNestedOpening {
                        self.recordRecent(url)
                    }
                    self.statusMessage = "\(url.lastPathComponent) · \(self.l10n.itemCount(result.entries.count))"
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = .passwordPrompt(.openArchive(url: url, fromExternalFinder: fromExternalFinder))
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
    }

    private nonisolated static func dominantZipAlgorithm(from listing: ArchiveListing) -> CompressionAlgorithm {
        var counts: [CompressionAlgorithm: Int] = [:]
        for entry in listing.entries where !entry.isDirectory && !entry.isSymbolicLink {
            let name = entry.compressionMethodName
            let algo: CompressionAlgorithm?
            switch name {
            case "DEFLATE": algo = .deflate
            case "Zstandard": algo = .zstd
            case "Bzip2": algo = .bzip2
            case "Store": algo = .store
            default: algo = nil
            }
            if let algo {
                counts[algo, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .deflate
    }

    func reloadWithEncoding(_ newEncoding: FilenameEncodingOption) {
        encodingOption = newEncoding
        guard let url = listing?.archiveURL else { return }
        openArchive(
            url: url,
            password: savedPassword,
            isNestedOpening: !archiveBackStack.isEmpty,
            initialFolder: currentFolder
        )
    }

    func closeArchive() {
        cleanupPreviewTempFiles()
        archiveBackStack.removeAll()
        applyLoadedListing(nil, openedFromHome: false)
        savedPassword = nil
        statusMessage = l10n.readyStatus
    }

    func navigateBackFromNestedArchive() {
        guard let frame = archiveBackStack.popLast() else { return }
        if let dir = frame.nestedTempDirToCleanup {
            nestedTempDirs.removeAll { $0 == dir }
            try? FileManager.default.removeItem(at: dir)
        }
        encodingOption = frame.encoding
        openArchive(
            url: frame.archiveURL,
            fromExternalFinder: !frame.openedFromHome,
            password: frame.savedPassword,
            isNestedOpening: true,
            initialFolder: frame.currentFolder
        )
    }

    func createArchive(
        inputs: [URL],
        outputURL: URL,
        options: CreateArchiveOptions,
        useFloatingHUD: Bool = false,
        trashSourcesOnCompletion: Bool = false
    ) {
        statusMessage = "\(outputURL.lastPathComponent)..."
        let op = QuickTaskHUDModel.Operation.compress(inputs: inputs, outputURL: outputURL, options: options)
        if trashSourcesOnCompletion {
            trashAfterSuccessByOpID[op.id] = inputs
        }
        if useFloatingHUD {
            configureHUD()
            hudModel.enqueue(op)
        } else {
            configureInAppHUD()
            inAppTaskHUD.enqueue(op)
        }
    }

    func quickExtract(mode: ExtractMode, archiveURL overrideURL: URL? = nil) {
        guard let targetArchive = overrideURL ?? listing?.archiveURL else { return }
        let dest: URL
        if let resolved = resolveDefaultExtractDirectory(for: targetArchive) {
            dest = resolved
        } else {
            let panel = NSOpenPanel()
            panel.title = l10n.selectExtractDestTitle
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            dest = chosen
        }
        let opts = ExtractOptions(
            destinationURL: dest,
            mode: mode,
            overwritePolicy: .overwrite,
            password: savedPassword,
            encoding: encodingOption,
            stripMacJunk: defaultStripMacJunk,
            restoreSymlinks: restoreSymlinksOnExtract
        )
        runExtract(options: opts, archiveURL: targetArchive)
    }

    func triggerSmartExtractNow() {
        quickExtract(mode: defaultExtractMode.extractMode)
    }

    func runExtract(
        options: ExtractOptions,
        archiveURL overrideURL: URL? = nil,
        skipConflictCheck: Bool = false,
        trashArchiveOnCompletion: Bool = false
    ) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        if !skipConflictCheck && options.overwritePolicy == .overwrite {
            Task.detached(priority: .userInitiated) {
                let conflicts = try? BoltArchiveEngine.detectExtractConflicts(archiveURL: archiveURL, options: options)
                await MainActor.run {
                    if let conflicts, conflicts.hasConflicts {
                        self.pendingExtractConflict = PendingExtractConflict(
                            archiveURL: archiveURL,
                            options: options,
                            destinationRoot: conflicts.destinationRoot,
                            conflictingNames: conflicts.conflictingNames,
                            trashArchiveOnCompletion: trashArchiveOnCompletion
                        )
                    } else {
                        self.enqueueInAppExtract(
                            archiveURL: archiveURL,
                            options: options,
                            trashArchiveOnCompletion: trashArchiveOnCompletion
                        )
                    }
                }
            }
            return
        }
        enqueueInAppExtract(archiveURL: archiveURL, options: options, trashArchiveOnCompletion: trashArchiveOnCompletion)
    }

    func enqueueInAppExtract(archiveURL: URL, options: ExtractOptions, trashArchiveOnCompletion: Bool = false) {
        configureInAppHUD()
        statusMessage = "\(archiveURL.lastPathComponent)..."
        let op = QuickTaskHUDModel.Operation.extract(archiveURL: archiveURL, options: options)
        if trashArchiveOnCompletion {
            trashAfterSuccessByOpID[op.id] = [archiveURL]
        }
        inAppTaskHUD.enqueue(op)
    }

    func confirmExtractOverwrite() {
        guard let conflict = pendingExtractConflict else { return }
        pendingExtractConflict = nil
        enqueueInAppExtract(
            archiveURL: conflict.archiveURL,
            options: conflict.options,
            trashArchiveOnCompletion: conflict.trashArchiveOnCompletion
        )
    }

    func confirmExtractRename() {
        guard let conflict = pendingExtractConflict else { return }
        pendingExtractConflict = nil
        let renamedOpts = ExtractOptions(
            destinationURL: conflict.options.destinationURL,
            mode: conflict.options.mode,
            overwritePolicy: .rename,
            password: conflict.options.password,
            encoding: conflict.options.encoding,
            stripMacJunk: conflict.options.stripMacJunk,
            workerCount: conflict.options.workerCount,
            restoreSymlinks: conflict.options.restoreSymlinks
        )
        enqueueInAppExtract(
            archiveURL: conflict.archiveURL,
            options: renamedOpts,
            trashArchiveOnCompletion: conflict.trashArchiveOnCompletion
        )
    }

    func cancelExtractConflict() {
        pendingExtractConflict = nil
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
                    self.alertMessage = self.l10n.operationErrorMessage(error)
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
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
    }

    func testIntegrityBatch(archiveURLs: [URL]) {
        let archives = BoltArchiveEngine.filterArchiveURLs(archiveURLs)
        guard !archives.isEmpty else { return }
        if archives.count == 1 {
            testIntegrity(archiveURL: archives[0])
            return
        }

        let pw = savedPassword
        let enc = encodingOption
        let title = l10n.batchArchivesTitle(archives.count)
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: archives[0].lastPathComponent)

        Task.detached(priority: .userInitiated) {
            let report = BoltArchiveEngine.testIntegrityBatch(
                archiveURLs: archives,
                password: pw,
                encoding: enc,
                batchTitle: title
            ) { prog in
                Task { @MainActor in
                    self.progress = prog
                }
            }
            await MainActor.run {
                self.isBusy = false
                self.progress = nil
                self.activeSheet = .integrityReport(report)
                self.statusMessage = "\(report.passedCount)/\(report.totalEntries)"
            }
        }
    }

    func previewOrOpenEntry(_ entry: ArchiveEntry, password: String? = nil) {
        if entry.isDirectory {
            searchText = ""
            navigateToFolder(entry.path)
            return
        }
        if !entry.isSymbolicLink,
           ArchiveFormat.detect(from: URL(fileURLWithPath: entry.name)) != nil {
            openNestedArchiveEntry(entry, password: password)
            return
        }
        guard let archiveURL = listing?.archiveURL else { return }
        let maxPreviewBytes: UInt64 = 128 * 1024 * 1024
        if entry.uncompressedSize > maxPreviewBytes {
            statusMessage = l10n.quickLookTooLargeStatus(entry.name)
            alertMessage = l10n.quickLookTooLargeStatus(entry.name)
            return
        }
        let pw = password ?? savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot

        isBusy = true
        Task.detached(priority: .userInitiated) {
            let subDir = previewRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                let fileURL = subDir.appendingPathComponent(entry.name)
                try BoltArchiveEngine.extractSingleEntryToFile(
                    archiveURL: archiveURL,
                    entryPath: entry.path,
                    destinationFileURL: fileURL,
                    password: pw,
                    encoding: enc
                )

                await MainActor.run {
                    self.isBusy = false
                    if let pw, !pw.isEmpty { self.savedPassword = pw }
                    self.statusMessage = entry.name
                    QuickLookPreviewController.shared.preview(url: fileURL)
                    let previousDir = self.activePreviewTempDir
                    self.activePreviewTempDir = subDir
                    if let previousDir, previousDir != subDir {
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            try? FileManager.default.removeItem(at: previousDir)
                        }
                    }
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                try? FileManager.default.removeItem(at: subDir)
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = .passwordPrompt(.preview(entry))
                }
            } catch {
                try? FileManager.default.removeItem(at: subDir)
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
    }

    func openNestedArchiveEntry(_ entry: ArchiveEntry, password: String? = nil) {
        guard let parentListing = listing else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot

        isBusy = true
        statusMessage = "\(entry.name)..."
        Task.detached(priority: .userInitiated) {
            let nestedDir = previewRoot.appendingPathComponent("Nested-\(UUID().uuidString)", isDirectory: true)
            do {
                let nestedURL = nestedDir.appendingPathComponent(entry.name)
                try BoltArchiveEngine.extractSingleEntryToFile(
                    archiveURL: parentListing.archiveURL,
                    entryPath: entry.path,
                    destinationFileURL: nestedURL,
                    password: pw,
                    encoding: enc
                )

                let inspectedNested = try BoltArchiveEngine.inspect(archiveURL: nestedURL, encoding: enc)
                let detectedAlgo = Self.dominantZipAlgorithm(from: inspectedNested)
                let nestedIndex = ArchiveNavigationIndex.build(from: inspectedNested, rootTitle: inspectedNested.archiveURL.lastPathComponent)
                await MainActor.run {
                    self.isBusy = false
                    if let pw, !pw.isEmpty { self.savedPassword = pw }
                    let backFrame = ArchiveNavigationFrame(
                        archiveURL: parentListing.archiveURL,
                        savedPassword: self.savedPassword,
                        encoding: self.encodingOption,
                        currentFolder: self.currentFolder,
                        openedFromHome: self.openedArchiveFromHome,
                        nestedTempDirToCleanup: nestedDir
                    )
                    self.archiveBackStack.append(backFrame)
                    self.nestedTempDirs.append(nestedDir)
                    self.applyLoadedListing(
                        inspectedNested,
                        prebuiltIndex: nestedIndex,
                        initialFolder: ""
                    )
                    self.savedPassword = nil
                    self.preferredZipEditAlgorithm = detectedAlgo
                    self.statusMessage = "\(nestedURL.lastPathComponent) · \(self.l10n.itemCount(inspectedNested.entries.count))"
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                try? FileManager.default.removeItem(at: nestedDir)
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = .passwordPrompt(.openNested(entry))
                }
            } catch {
                try? FileManager.default.removeItem(at: nestedDir)
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
    }

    func scheduleDebouncedQuickLookUpdateIfVisible() {
        quickLookRefreshTask?.cancel()
        quickLookRefreshTask = nil

        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return
        }
        guard selectedEntryIDs.count == 1,
              let entry = selectedEntries.first,
              !entry.isDirectory,
              !entry.isSymbolicLink,
              ArchiveFormat.detect(from: URL(fileURLWithPath: entry.name)) == nil,
              let archiveURL = listing?.archiveURL else {
            return
        }

        let maxPreviewBytes: UInt64 = 50 * 1024 * 1024
        if entry.uncompressedSize > maxPreviewBytes {
            statusMessage = l10n.quickLookTooLargeStatus(entry.name)
            return
        }
        if entry.isEncrypted && (savedPassword ?? "").isEmpty {
            return
        }

        let pw = savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let previousDir = self.activePreviewTempDir
            let resultURL: URL? = await Task.detached(priority: .userInitiated) {
                let subDir = previewRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let fileURL = subDir.appendingPathComponent(entry.name)
                do {
                    try BoltArchiveEngine.extractSingleEntryToFile(
                        archiveURL: archiveURL,
                        entryPath: entry.path,
                        destinationFileURL: fileURL,
                        password: pw,
                        encoding: enc
                    )
                    if Task.isCancelled {
                        try? FileManager.default.removeItem(at: subDir)
                        return nil
                    }
                    return fileURL
                } catch {
                    try? FileManager.default.removeItem(at: subDir)
                    return nil
                }
            }.value

            guard !Task.isCancelled, let resultURL else {
                if let resultURL {
                    try? FileManager.default.removeItem(at: resultURL.deletingLastPathComponent())
                }
                return
            }
            self.activePreviewTempDir = resultURL.deletingLastPathComponent()
            QuickLookPreviewController.shared.preview(url: resultURL)
            if let previousDir, previousDir != self.activePreviewTempDir {
                try? FileManager.default.removeItem(at: previousDir)
            }
        }
        quickLookRefreshTask = task
    }

    // MARK: - In-Place ZIP Editing

    func addItemsToCurrentZipPanel(targetFolder: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.title = l10n.ctxAddHere
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            addItemsToCurrentZip(panel.urls, targetFolder: targetFolder ?? currentFolder)
        }
    }

    func addItemsToCurrentZip(_ urls: [URL], targetFolder: String? = nil) {
        let folder = targetFolder ?? currentFolder
        if let listing, listing.hasEncryptedEntries, (savedPassword ?? "").isEmpty {
            activeSheet = .passwordPrompt(.unlockForEdit(urls: urls, targetFolder: folder))
            return
        }
        editCurrentZip([.addItems(urls: urls, targetFolder: folder)])
    }

    func unlockForEditAndAdd(urls: [URL], targetFolder: String, password: String) {
        guard let archiveURL = listing?.archiveURL else { return }
        let enc = encodingOption
        isBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                let report = try BoltArchiveEngine.testIntegrity(archiveURL: archiveURL, password: password, encoding: enc)
                guard report.failedCount == 0 && report.skippedEncryptedCount == 0 else {
                    throw BoltZipError.wrongPassword(archiveURL.lastPathComponent)
                }
                await MainActor.run {
                    self.isBusy = false
                    self.savedPassword = password
                    self.editCurrentZip([.addItems(urls: urls, targetFolder: targetFolder)])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = self.l10n.operationErrorMessage(error)
                }
            }
        }
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

    func updateArchiveComment(_ comment: String) {
        editCurrentZip([.setComment(comment)])
    }

    func deletePaths(_ targets: Set<String>) {
        guard !targets.isEmpty else { return }
        editCurrentZip([.deletePaths(targets)])
    }

    func deleteSelectedEntries() {
        deletePaths(Set(selectedEntries.map(\.path)))
    }

    func requestDeleteSelectedEntries() {
        guard let listing, listing.canEditInPlace else { return }
        let targets = Set(selectedEntries.map(\.path))
        guard !targets.isEmpty else { return }
        pendingDeleteConfirmation = PendingDeleteConfirmation(paths: targets)
    }

    func selectAllVisibleEntries() {
        selectedEntryIDs = Set(visibleEntries.map(\.id))
    }

    func copySelectedEntryNames() {
        let picked = selectedEntries
        guard !picked.isEmpty else { return }
        let names = picked.map(\.name).joined(separator: "\n")
        copyToPasteboard(names)
    }

    func editCurrentZip(_ ops: [ZipEditOperation]) {
        guard let listing, listing.canEditInPlace else { return }
        runArchiveEdit(ArchiveEditRequest(archiveURL: listing.archiveURL, operations: ops,
            options: archiveEditOptions, encoding: encodingOption))
    }
}
