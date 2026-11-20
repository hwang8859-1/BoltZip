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
        if options.overwritePolicy == .overwrite {
            Task.detached(priority: .userInitiated) {
                do {
                    let conflicts = try BoltArchiveEngine.detectExtractConflicts(archiveURL: archiveURL, options: options)
                    await MainActor.run {
                        if conflicts.hasConflicts {
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
                } catch {
                    await MainActor.run {
                        let purpose = PasswordPurpose.extract(
                            archiveURL: archiveURL,
                            options: options,
                            trashArchiveOnCompletion: trashArchiveOnCompletion
                        )
                        if let prompt = purpose.prompt(for: error) {
                            self.activeSheet = prompt
                        } else {
                            self.alertMessage = self.l10n.operationErrorMessage(error)
                        }
                    }
                }
            }
            return
        }
        enqueueInAppExtract(archiveURL: archiveURL, options: options, trashArchiveOnCompletion: trashArchiveOnCompletion)
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
}
