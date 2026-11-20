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
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.title = l10n.openArchive
        if panel.runModal() == .OK, let url = panel.url {
            openArchive(url: url, fromExternalFinder: false)
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
                let (result, detectedAlgo, navIndex) = try Self.loadArchiveContents(at: url, encoding: encoding, password: password)
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

    private nonisolated static func loadArchiveContents(
        at url: URL,
        encoding: FilenameEncodingOption,
        password: String? = nil
    ) throws -> (ArchiveListing, CompressionAlgorithm, ArchiveNavigationIndex) {
        let listing = try BoltArchiveEngine.inspect(archiveURL: url, encoding: encoding, password: password)
        return (listing, dominantZipAlgorithm(from: listing), ArchiveNavigationIndex.build(from: listing))
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
                let nestedURL = try Self.extractEntryToTemporaryDirectory(
                    entry, from: parentListing.archiveURL, into: nestedDir, password: pw, encoding: enc
                )

                let (inspectedNested, detectedAlgo, nestedIndex) = try Self.loadArchiveContents(at: nestedURL, encoding: enc)
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
}
