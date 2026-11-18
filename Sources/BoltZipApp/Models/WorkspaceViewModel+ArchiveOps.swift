import AppKit
import BoltZipCore
import Foundation
import UniformTypeIdentifiers

extension WorkspaceViewModel {
    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
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

    func openArchive(url: URL, fromExternalFinder: Bool = false, password: String? = nil) {
        let encoding = encodingOption
        let fromHomeOrigin: Bool = {
            if fromExternalFinder { return false }
            if listing == nil { return true }
            return openedArchiveFromHome
        }()

        isBusy = true
        statusMessage = "\(url.lastPathComponent)..."
        Task.detached(priority: .userInitiated) {
            do {
                let result = try BoltArchiveEngine.inspect(archiveURL: url, encoding: encoding, password: password)
                await MainActor.run {
                    if self.listing?.archiveURL != url {
                        self.cleanupPreviewTempFiles()
                    }
                    self.listing = result
                    self.openedArchiveFromHome = fromHomeOrigin
                    self.currentFolder = ""
                    self.folderForwardStack.removeAll()
                    self.selectedEntryIDs.removeAll()
                    self.searchText = ""
                    if let password, !password.isEmpty {
                        self.savedPassword = password
                    } else {
                        self.savedPassword = nil
                    }
                    self.isBusy = false
                    self.recordRecent(url)
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
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func reloadWithEncoding(_ newEncoding: FilenameEncodingOption) {
        encodingOption = newEncoding
        guard let url = listing?.archiveURL else { return }
        openArchive(url: url, password: savedPassword)
    }

    func closeArchive() {
        cleanupPreviewTempFiles()
        listing = nil
        openedArchiveFromHome = false
        currentFolder = ""
        folderForwardStack.removeAll()
        selectedEntryIDs.removeAll()
        searchText = ""
        savedPassword = nil
        statusMessage = l10n.readyStatus
    }

    func createArchive(inputs: [URL], outputURL: URL, options: CreateArchiveOptions, useFloatingHUD: Bool = false) {
        statusMessage = "\(outputURL.lastPathComponent)..."
        if useFloatingHUD {
            configureHUD()
            hudModel.enqueue(.compress(inputs: inputs, outputURL: outputURL, options: options))
        } else {
            configureInAppHUD()
            inAppTaskHUD.enqueue(.compress(inputs: inputs, outputURL: outputURL, options: options))
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

    func runExtract(options: ExtractOptions, archiveURL overrideURL: URL? = nil, skipConflictCheck: Bool = false) {
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
                            conflictingNames: conflicts.conflictingNames
                        )
                    } else {
                        self.enqueueInAppExtract(archiveURL: archiveURL, options: options)
                    }
                }
            }
            return
        }
        enqueueInAppExtract(archiveURL: archiveURL, options: options)
    }

    func enqueueInAppExtract(archiveURL: URL, options: ExtractOptions) {
        configureInAppHUD()
        statusMessage = "\(archiveURL.lastPathComponent)..."
        inAppTaskHUD.enqueue(.extract(archiveURL: archiveURL, options: options))
    }

    func confirmExtractOverwrite() {
        guard let conflict = pendingExtractConflict else { return }
        pendingExtractConflict = nil
        enqueueInAppExtract(archiveURL: conflict.archiveURL, options: conflict.options)
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
            stripMacJunk: conflict.options.stripMacJunk
        )
        enqueueInAppExtract(archiveURL: conflict.archiveURL, options: renamedOpts)
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
        guard let listing, listing.canEditInPlace else { return }
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
}
