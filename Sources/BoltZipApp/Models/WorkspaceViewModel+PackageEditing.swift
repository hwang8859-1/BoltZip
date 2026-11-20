import AppKit
import BoltZipCore
import Foundation
import UniformTypeIdentifiers

extension WorkspaceViewModel {
    func editEntryText(_ entry: ArchiveEntry) {
        guard let listing, listing.canEditInPlace, !entry.isDirectory, !entry.isSymbolicLink else { return }
        guard entry.uncompressedSize <= 2 * 1024 * 1024 else { alertMessage = l10n.archiveTextEditorLimit; return }
        let archive = listing.archiveURL, encoding = encodingOption, password = savedPassword
        isBusy = true
        archiveEditErrorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let modified = try FileManager.default.attributesOfItem(atPath: archive.path)[.modificationDate] as? Date
                let data = try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: entry.path, password: password, encoding: encoding)
                let profile = try BoltArchiveEngine.entryCompressionProfile(at: archive, path: entry.path, encoding: encoding)
                let decoded = ArchiveTextDocument.decode(data)
                guard try FileManager.default.attributesOfItem(atPath: archive.path)[.modificationDate] as? Date == modified else {
                    throw ArchiveOperationError.inputChanged(archive.lastPathComponent)
                }
                await MainActor.run {
                    self.isBusy = false
                    guard self.listing?.archiveURL == archive else { return }
                    guard let decoded else { self.alertMessage = self.l10n.archiveTextEncodingUnsupported; return }
                    let ending = decoded.0.contains("\r\n") ? "\r\n" : (decoded.0.contains("\r") ? "\r" : "\n")
                    self.activeSheet = .editEntryText(ArchiveTextDocument(archiveURL: archive, entryPath: entry.path,
                        text: decoded.0, encoding: decoded.1, bom: decoded.2, lineEnding: ending,
                        archiveModifiedDate: modified, profile: profile))
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
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
            let modified = try FileManager.default.attributesOfItem(atPath: document.archiveURL.path)[.modificationDate] as? Date
            guard modified == document.archiveModifiedDate else { archiveEditErrorMessage = l10n.archiveChangedDuringEdit; return }
            guard let data = document.encoded(text) else { archiveEditErrorMessage = l10n.archiveTextEncodingUnsupported; return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipEdit-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            draftDirectory = directory
            let replacement = directory.appendingPathComponent("replacement")
            try data.write(to: replacement, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replacement.path)
            runArchiveEdit(ArchiveEditRequest(archiveURL: listing.archiveURL,
                operations: [.replaceEntry(path: document.entryPath, fileURL: replacement)], options: archiveEditOptions,
                encoding: encodingOption, temporaryDirectory: directory))
        } catch {
            if let draftDirectory { try? FileManager.default.removeItem(at: draftDirectory) }
            archiveEditErrorMessage = l10n.operationErrorMessage(error)
        }
    }

    func replaceEntryFile(_ entry: ArchiveEntry) {
        guard let listing, listing.canEditInPlace, !entry.isDirectory, !entry.isSymbolicLink else { return }
        let archive = listing.archiveURL, encoding = encodingOption
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

    var archiveEditOptions: CreateArchiveOptions {
        CreateArchiveOptions(format: .zip, algorithm: preferredZipEditAlgorithm,
            encryption: (savedPassword ?? "").isEmpty ? .none : .aes256, password: savedPassword,
            excludeMacJunk: false, preserveSymlinks: true)
    }

    func runArchiveEdit(_ request: ArchiveEditRequest) {
        guard listing?.archiveURL == request.archiveURL else { cancelArchiveEdit(request); return }
        isBusy = true
        archiveEditErrorMessage = nil
        progress = OperationProgress(fractionCompleted: 0, currentItem: request.archiveURL.lastPathComponent)
        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.editZip(at: request.archiveURL, operations: request.operations, options: request.options,
                    encoding: request.encoding) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                let updated = try BoltArchiveEngine.inspect(archiveURL: request.archiveURL, encoding: request.encoding, password: request.options.password)
                let index = ArchiveNavigationIndex.build(from: updated, rootTitle: updated.archiveURL.lastPathComponent)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.activeSheet = nil
                    self.cancelArchiveEdit(request)
                    let folder = index.defaultSortedByFolder[self.currentFolder] != nil ? self.currentFolder : ""
                    self.applyLoadedListing(updated, prebuiltIndex: index, initialFolder: folder, clearForwardStack: false, clearSearch: false)
                    self.statusMessage = self.l10n.archiveEditSaved
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if error is ArchiveEditCompatibilityError {
                        self.offerCompatibleZIP(request, error: error)
                    } else {
                        self.archiveEditErrorMessage = self.l10n.operationErrorMessage(error)
                        if self.activeSheet == nil { self.alertMessage = self.archiveEditErrorMessage }
                        self.cancelArchiveEdit(request)
                    }
                }
            }
        }
    }

    func cancelArchiveEdit(_ request: ArchiveEditRequest?) {
        if let directory = request?.temporaryDirectory { try? FileManager.default.removeItem(at: directory) }
    }

    private func offerCompatibleZIP(_ request: ArchiveEditRequest, error: any Error) {
        let alert = NSAlert()
        alert.messageText = l10n.originalArchiveSaveUnsupported
        alert.informativeText = l10n.operationErrorMessage(error) + "\n\n" + l10n.compatibleZIPExplanation
        alert.addButton(withTitle: l10n.cancel)
        alert.addButton(withTitle: l10n.saveAsCompatibleZIP)
        guard alert.runModal() == .alertSecondButtonReturn else { cancelArchiveEdit(request); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = request.archiveURL.deletingPathExtension().lastPathComponent + "-edited.zip"
        guard panel.runModal() == .OK, let output = panel.url, output.standardizedFileURL != request.archiveURL.standardizedFileURL else {
            cancelArchiveEdit(request); return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.exportEditedArchiveAsZip(at: request.archiveURL, to: output,
                    operations: request.operations, password: request.options.password, encoding: request.encoding)
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = nil
                    self.cancelArchiveEdit(request)
                    self.openArchive(url: output, password: request.options.password)
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.archiveEditErrorMessage = self.l10n.operationErrorMessage(error)
                    if self.activeSheet == nil { self.alertMessage = self.archiveEditErrorMessage }
                    self.cancelArchiveEdit(request)
                }
            }
        }
    }
}
