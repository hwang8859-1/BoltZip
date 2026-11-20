import BoltZipCore
import Foundation
import QuickLookUI

extension WorkspaceViewModel {
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
                let fileURL = try Self.extractEntryToTemporaryDirectory(
                    entry, from: archiveURL, into: subDir, password: pw, encoding: enc
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
                do {
                    let fileURL = try Self.extractEntryToTemporaryDirectory(
                        entry, from: archiveURL, into: subDir, password: pw, encoding: enc
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

    nonisolated static func extractEntryToTemporaryDirectory(
        _ entry: ArchiveEntry,
        from archiveURL: URL,
        into directory: URL,
        password: String?,
        encoding: FilenameEncodingOption
    ) throws -> URL {
        let destination = directory.appendingPathComponent(entry.name)
        try BoltArchiveEngine.extractSingleEntryToFile(
            archiveURL: archiveURL,
            entryPath: entry.path,
            destinationFileURL: destination,
            password: password,
            encoding: encoding
        )
        return destination
    }
}
