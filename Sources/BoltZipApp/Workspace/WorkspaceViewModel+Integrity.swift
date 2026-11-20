import BoltZipCore
import Foundation

extension WorkspaceViewModel {
    func testIntegrity(password: String? = nil, archiveURL overrideURL: URL? = nil) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        let pw = password ?? (archiveURL == listing?.archiveURL ? savedPassword : nil)
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
                        if archiveURL == self.listing?.archiveURL, let pw, !pw.isEmpty { self.savedPassword = pw }
                        self.activeSheet = .integrityReport(report)
                        self.statusMessage = "\(report.passedCount)/\(report.totalEntries)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if let prompt = PasswordPurpose.testIntegrity(archiveURL: archiveURL).prompt(for: error) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
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
}
