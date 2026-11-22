import AppKit
import BoltZipCore
import Foundation
import UniformTypeIdentifiers

private struct ArchiveEditRequest: Sendable {
    let archiveURL: URL
    let operations: [ZipEditOperation]
    let options: CreateArchiveOptions
    let encoding: FilenameEncodingOption
    let temporaryDirectory: URL?
    let usedKeychain: Bool

    func discardDraft() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }
}

extension WorkspaceViewModel {
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
            if let kc = keychainPassword(for: listing.archiveURL), !kc.isEmpty {
                unlockForEditAndAdd(urls: urls, targetFolder: folder, password: kc, usedKeychain: true)
            } else {
                activeSheet = .passwordPrompt(.unlockForEdit(urls: urls, targetFolder: folder))
            }
            return
        }
        editCurrentZip([.addItems(urls: urls, targetFolder: folder)])
    }

    func unlockForEditAndAdd(urls: [URL], targetFolder: String, password: String, usedKeychain: Bool = false) {
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
                    self.commitPendingKeychainSaveIfMatching(password: password, for: archiveURL)
                    self.editCurrentZip([.addItems(urls: urls, targetFolder: targetFolder)])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    var promptError: any Error = error
                    if usedKeychain, case BoltZipError.wrongPassword = error {
                        _ = self.invalidateStaleKeychainPasswordIfNeeded(for: archiveURL, attemptedPassword: password)
                        promptError = BoltZipError.passwordRequired(archiveURL.lastPathComponent)
                    }
                    if let prompt = PasswordPurpose.unlockForEdit(urls: urls, targetFolder: targetFolder).prompt(for: promptError) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
                }
            }
        }
    }

    func unlockEditOperations(_ operations: [ArchiveEditOperation], password: String, usedKeychain: Bool = false) {
        guard let listing else { return }
        let archiveURL = listing.archiveURL
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
                    self.commitPendingKeychainSaveIfMatching(password: password, for: archiveURL)
                    self.editCurrentZip(operations)
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    var promptError: any Error = error
                    if usedKeychain, case BoltZipError.wrongPassword = error {
                        _ = self.invalidateStaleKeychainPasswordIfNeeded(for: archiveURL, attemptedPassword: password)
                        promptError = BoltZipError.passwordRequired(archiveURL.lastPathComponent)
                    }
                    if let prompt = PasswordPurpose.unlockEditOperations(operations).prompt(for: promptError) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
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

    private func editCurrentZip(_ ops: [ZipEditOperation]) {
        guard let listing, listing.canEditInPlace else { return }
        let useKeychain = (savedPassword ?? "").isEmpty && listing.hasEncryptedEntries
        let keychainCandidate = useKeychain ? keychainPassword(for: listing.archiveURL) : nil
        runArchiveEdit(ArchiveEditRequest(
            archiveURL: listing.archiveURL,
            operations: ops,
            options: archiveEditOptions(passwordOverride: keychainCandidate),
            encoding: encodingOption,
            temporaryDirectory: nil,
            usedKeychain: keychainCandidate != nil
        ))
    }

    func editEntryText(_ entry: ArchiveEntry, password overridePassword: String? = nil) {
        guard let archive = editableArchiveURL(for: entry) else { return }
        guard entry.uncompressedSize <= 2 * 1024 * 1024 else { alertMessage = l10n.archiveTextEditorLimit; return }
        let encoding = encodingOption
        let keychainCandidate = (overridePassword == nil && savedPassword == nil) ? keychainPassword(for: archive) : nil
        let password = overridePassword ?? savedPassword ?? keychainCandidate
        let usedKeychain = (overridePassword == nil && savedPassword == nil && keychainCandidate != nil)
        isBusy = true
        archiveEditErrorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let document = try ArchiveTextDocument.load(
                    archiveURL: archive, entryPath: entry.path, password: password, filenameEncoding: encoding
                )
                await MainActor.run {
                    self.isBusy = false
                    guard self.listing?.archiveURL == archive else { return }
                    if let password, !password.isEmpty {
                        self.savedPassword = password
                        self.commitPendingKeychainSaveIfMatching(password: password, for: archive)
                    }
                    guard let document else { self.alertMessage = self.l10n.archiveTextEncodingUnsupported; return }
                    self.activeSheet = .editEntryText(document)
                }
            } catch BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    if usedKeychain {
                        _ = self.invalidateStaleKeychainPasswordIfNeeded(for: archive, attemptedPassword: password)
                        self.activeSheet = .passwordPrompt(.editText(entry), wrongAttempt: false)
                    } else {
                        self.activeSheet = .passwordPrompt(.editText(entry), wrongAttempt: true)
                    }
                }
            } catch BoltZipError.passwordRequired {
                await MainActor.run { self.isBusy = false; self.activeSheet = .passwordPrompt(.editText(entry)) }
            } catch {
                await MainActor.run { self.isBusy = false; self.alertMessage = self.l10n.operationErrorMessage(error) }
            }
        }
    }

    func saveEntryText(_ document: ArchiveTextDocument, text: String) {
        guard let listing, listing.archiveURL == document.archiveURL else { return }
        var draftDirectory: URL?
        do {
            guard try document.matchesCurrentArchive() else { archiveEditErrorMessage = l10n.archiveChangedDuringEdit; return }
            guard let data = document.encoded(text) else { archiveEditErrorMessage = l10n.archiveTextEncodingUnsupported; return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipEdit-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            draftDirectory = directory
            let replacement = directory.appendingPathComponent("replacement")
            try data.write(to: replacement, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replacement.path)
            runArchiveEdit(ArchiveEditRequest(archiveURL: listing.archiveURL,
                operations: [.replaceEntry(path: document.entryPath, fileURL: replacement)], options: archiveEditOptions(),
                encoding: encodingOption, temporaryDirectory: directory, usedKeychain: false))
        } catch {
            if let draftDirectory { try? FileManager.default.removeItem(at: draftDirectory) }
            archiveEditErrorMessage = l10n.operationErrorMessage(error)
        }
    }

    func replaceEntryFile(_ entry: ArchiveEntry) {
        guard let archive = editableArchiveURL(for: entry) else { return }
        let encoding = encodingOption
        Task.detached(priority: .userInitiated) {
            do {
                let profile = try BoltArchiveEngine.entryCompressionProfile(at: archive, path: entry.path, encoding: encoding)
                await MainActor.run {
                    guard self.listing?.archiveURL == archive else { return }
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.title = self.l10n.replaceEntryFile
                    panel.message = self.l10n.compressionPreservationNotice(profile)
                    if panel.runModal() == .OK, let replacement = panel.url {
                        self.editCurrentZip([.replaceEntry(path: entry.path, fileURL: replacement)])
                    }
                }
            } catch { await MainActor.run { self.alertMessage = self.l10n.operationErrorMessage(error) } }
        }
    }

    private func editableArchiveURL(for entry: ArchiveEntry) -> URL? {
        guard let listing, listing.canEditInPlace, !entry.isDirectory, !entry.isSymbolicLink else { return nil }
        return listing.archiveURL
    }

    private func archiveEditOptions(passwordOverride: String? = nil) -> CreateArchiveOptions {
        let format = listing?.format ?? .zip
        let algo = format.supportedAlgorithms.contains(preferredZipEditAlgorithm)
            ? preferredZipEditAlgorithm
            : format.defaultAlgorithm
        let effectivePW = passwordOverride ?? savedPassword
        return CreateArchiveOptions(
            format: format,
            algorithm: algo,
            encryption: (effectivePW ?? "").isEmpty ? .none : .aes256,
            password: effectivePW,
            excludeMacJunk: false,
            preserveSymlinks: true
        )
    }

    private func runArchiveEdit(_ request: ArchiveEditRequest) {
        guard listing?.archiveURL == request.archiveURL else { request.discardDraft(); return }
        isBusy = true
        archiveEditErrorMessage = nil
        progress = OperationProgress(fractionCompleted: 0, currentItem: request.archiveURL.lastPathComponent)
        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.editArchive(at: request.archiveURL, operations: request.operations, options: request.options,
                    encoding: request.encoding) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                let updated = try BoltArchiveEngine.inspect(archiveURL: request.archiveURL, encoding: request.encoding, password: request.options.password)
                let index = ArchiveNavigationIndex.build(from: updated)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.activeSheet = nil
                    request.discardDraft()
                    if let pw = request.options.password, !pw.isEmpty {
                        self.savedPassword = pw
                    }
                    let folder = index.defaultSortedByFolder[self.currentFolder] != nil ? self.currentFolder : ""
                    self.applyLoadedListing(updated, prebuiltIndex: index, initialFolder: folder, clearForwardStack: false, clearSearch: false)
                    self.statusMessage = self.l10n.archiveEditSaved
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    var promptError: any Error = error
                    if request.usedKeychain, case BoltZipError.wrongPassword = error {
                        _ = self.invalidateStaleKeychainPasswordIfNeeded(for: request.archiveURL, attemptedPassword: request.options.password)
                        promptError = BoltZipError.passwordRequired(request.archiveURL.lastPathComponent)
                    }
                    if let prompt = PasswordPurpose.unlockEditOperations(request.operations).prompt(for: promptError) {
                        request.discardDraft()
                        self.activeSheet = prompt
                    } else if error is ArchiveEditCompatibilityError {
                        self.offerCompatibleZIP(request, error: error)
                    } else {
                        self.reportArchiveEditError(error, request: request)
                    }
                }
            }
        }
    }

    private func reportArchiveEditError(_ error: any Error, request: ArchiveEditRequest) {
        archiveEditErrorMessage = l10n.operationErrorMessage(error)
        if activeSheet == nil { alertMessage = archiveEditErrorMessage }
        request.discardDraft()
    }

    private func offerCompatibleZIP(_ request: ArchiveEditRequest, error: any Error) {
        let alert = NSAlert()
        alert.messageText = l10n.originalArchiveSaveUnsupported
        alert.informativeText = l10n.operationErrorMessage(error) + "\n\n" + l10n.compatibleZIPExplanation
        alert.addButton(withTitle: l10n.cancel)
        alert.addButton(withTitle: l10n.saveAsCompatibleZIP)
        guard alert.runModal() == .alertSecondButtonReturn else { request.discardDraft(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = request.archiveURL.deletingPathExtension().lastPathComponent + "-edited.zip"
        guard panel.runModal() == .OK, let output = panel.url, output.standardizedFileURL != request.archiveURL.standardizedFileURL else {
            request.discardDraft()
            return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.exportEditedArchiveAsZip(at: request.archiveURL, to: output,
                    operations: request.operations, password: request.options.password, encoding: request.encoding)
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = nil
                    request.discardDraft()
                    self.openArchive(url: output, password: request.options.password)
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.reportArchiveEditError(error, request: request)
                }
            }
        }
    }
}
