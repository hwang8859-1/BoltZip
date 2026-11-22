import AppKit
import BoltZipCore
import Foundation
import UniformTypeIdentifiers

extension WorkspaceViewModel {
    func quickExtract(mode: ExtractMode, archiveURL overrideURL: URL? = nil) {
        guard let targetArchive = overrideURL ?? listing?.archiveURL,
              let destination = selectExtractDestination(for: targetArchive) else { return }
        let password = targetArchive == listing?.archiveURL ? savedPassword : nil
        let options = makeQuickExtractOptions(destination: destination, mode: mode, password: password)
        runExtract(options: options, archiveURL: targetArchive)
    }

    func selectExtractDestination(for archiveURL: URL) -> URL? {
        if let resolved = resolveDefaultExtractDirectory(for: archiveURL) { return resolved }
        let panel = NSOpenPanel()
        panel.title = l10n.selectExtractDestTitle
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func makeQuickExtractOptions(destination: URL, mode: ExtractMode, password: String?) -> ExtractOptions {
        ExtractOptions(
            destinationURL: destination,
            mode: mode,
            overwritePolicy: .overwrite,
            password: password,
            encoding: encodingOption,
            stripMacJunk: defaultStripMacJunk,
            restoreSymlinks: restoreSymlinksOnExtract
        )
    }

    func triggerSmartExtractNow() {
        quickExtract(mode: defaultExtractMode.extractMode)
    }

    func runExtract(
        options: ExtractOptions,
        archiveURL overrideURL: URL? = nil,
        trashArchiveOnCompletion: Bool = false
    ) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        var effectiveOptions = options
        let keychainCandidate = (effectiveOptions.password == nil) ? keychainPassword(for: archiveURL) : nil
        let usedKeychain = (effectiveOptions.password == nil && keychainCandidate != nil)
        if let keychainCandidate {
            effectiveOptions.password = keychainCandidate
        }

        if effectiveOptions.overwritePolicy == .overwrite {
            let finalOpts = effectiveOptions
            Task.detached(priority: .userInitiated) {
                do {
                    let conflicts = try BoltArchiveEngine.detectExtractConflicts(archiveURL: archiveURL, options: finalOpts)
                    await MainActor.run {
                        if let pw = finalOpts.password, !pw.isEmpty {
                            self.commitPendingKeychainSaveIfMatching(password: pw, for: archiveURL)
                        }
                        if conflicts.hasConflicts {
                            self.pendingExtractConflict = PendingExtractConflict(
                                archiveURL: archiveURL,
                                options: finalOpts,
                                destinationRoot: conflicts.destinationRoot,
                                conflictingNames: conflicts.conflictingNames,
                                trashArchiveOnCompletion: trashArchiveOnCompletion
                            )
                        } else {
                            self.enqueueInAppExtract(
                                archiveURL: archiveURL,
                                options: finalOpts,
                                trashArchiveOnCompletion: trashArchiveOnCompletion
                            )
                        }
                    }
                } catch {
                    await MainActor.run {
                        var promptError: any Error = error
                        if usedKeychain, case BoltZipError.wrongPassword = error {
                            _ = self.invalidateStaleKeychainPasswordIfNeeded(for: archiveURL, attemptedPassword: finalOpts.password)
                            promptError = BoltZipError.passwordRequired(archiveURL.lastPathComponent)
                        }
                        var retryOpts = finalOpts
                        if usedKeychain { retryOpts.password = nil }
                        let purpose = PasswordPurpose.extract(
                            archiveURL: archiveURL,
                            options: retryOpts,
                            trashArchiveOnCompletion: trashArchiveOnCompletion
                        )
                        if let prompt = purpose.prompt(for: promptError) {
                            self.activeSheet = prompt
                        } else {
                            self.alertMessage = self.l10n.operationErrorMessage(error)
                        }
                    }
                }
            }
            return
        }
        enqueueInAppExtract(archiveURL: archiveURL, options: effectiveOptions, trashArchiveOnCompletion: trashArchiveOnCompletion)
    }

    private func enqueueInAppExtract(archiveURL: URL, options: ExtractOptions, trashArchiveOnCompletion: Bool = false) {
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
        var renamedOpts = conflict.options
        renamedOpts.overwritePolicy = .rename
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

        let request = SelectedZipExport(source: sourceArchive, destination: destZip, entryPaths: entryIDs,
                                        encoding: encodingOption, stripMacJunk: defaultStripMacJunk)
        runSelectedZipExport(request, password: savedPassword)
    }

    func runSelectedZipExport(_ request: SelectedZipExport, password: String?) {
        let keychainCandidate = (password == nil) ? keychainPassword(for: request.source) : nil
        let effectivePassword = password ?? keychainCandidate
        let usedKeychain = (password == nil && keychainCandidate != nil)

        isBusy = true
        progress = OperationProgress(fractionCompleted: 0.1, currentItem: request.destination.lastPathComponent)

        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.exportSelectedEntriesAsZip(
                    at: request.source, to: request.destination, entryPaths: request.entryPaths,
                    password: effectivePassword, encoding: request.encoding, stripMacJunk: request.stripMacJunk
                )
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if let effectivePassword, !effectivePassword.isEmpty {
                        if self.listing?.archiveURL == request.source {
                            self.savedPassword = effectivePassword
                        }
                        self.commitPendingKeychainSaveIfMatching(password: effectivePassword, for: request.source)
                    }
                    self.statusMessage = request.destination.lastPathComponent
                    NSWorkspace.shared.activateFileViewerSelecting([request.destination])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    var promptError: any Error = error
                    if usedKeychain, case BoltZipError.wrongPassword = error {
                        _ = self.invalidateStaleKeychainPasswordIfNeeded(for: request.source, attemptedPassword: effectivePassword)
                        promptError = BoltZipError.passwordRequired(request.source.lastPathComponent)
                    }
                    if let prompt = PasswordPurpose.exportSelectedZip(request).prompt(for: promptError) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
                }
            }
        }
    }
}
