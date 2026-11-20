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
        initialFolder: String = "",
        encoding: FilenameEncodingOption? = nil,
        returningTo parentFrame: ArchiveNavigationFrame? = nil
    ) {
        let encoding = encoding ?? encodingOption
        let fromHomeOrigin: Bool = {
            if let parentFrame { return parentFrame.openedFromHome }
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
                    self.isBusy = false
                    if let parentFrame, self.archiveBackStack.last?.id != parentFrame.id { return }
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
                    if let parentFrame {
                        self.encodingOption = parentFrame.encoding
                        self.archiveBackStack.removeLast()
                        if let dir = parentFrame.nestedTempDirToCleanup {
                            self.nestedTempDirs.removeAll { $0 == dir }
                            try? FileManager.default.removeItem(at: dir)
                        }
                    }
                    self.preferredZipEditAlgorithm = detectedAlgo
                    if let password, !password.isEmpty {
                        self.savedPassword = password
                    } else {
                        self.savedPassword = nil
                    }
                    if !isNestedOpening {
                        self.recordRecent(url)
                    }
                    self.statusMessage = "\(url.lastPathComponent) · \(self.l10n.itemCount(result.entries.count))"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    let purpose: PasswordPurpose
                    if let parentFrame {
                        guard self.archiveBackStack.last?.id == parentFrame.id else { return }
                        purpose = .returnToParent(frameID: parentFrame.id)
                    } else {
                        purpose = .openArchive(
                            url: url, fromExternalFinder: fromExternalFinder,
                            isNestedOpening: isNestedOpening, initialFolder: initialFolder, encoding: encoding
                        )
                    }
                    if let prompt = purpose.prompt(for: error) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
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

    func navigateBackFromNestedArchive(password: String? = nil, expectedFrameID: UUID? = nil) {
        guard !isBusy, let frame = archiveBackStack.last,
              expectedFrameID == nil || expectedFrameID == frame.id else { return }
        openArchive(
            url: frame.archiveURL,
            fromExternalFinder: !frame.openedFromHome,
            password: password ?? frame.savedPassword,
            isNestedOpening: true,
            initialFolder: frame.currentFolder,
            encoding: frame.encoding,
            returningTo: frame
        )
    }

    func openNestedArchiveEntry(_ entry: ArchiveEntry, password: String? = nil, nestedPassword: String? = nil) {
        guard let parentListing = listing else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot

        isBusy = true
        statusMessage = "\(entry.name)..."
        Task.detached(priority: .userInitiated) {
            let nestedDir = previewRoot.appendingPathComponent("Nested-\(UUID().uuidString)", isDirectory: true)
            var passwordPurpose = PasswordPurpose.openNested(entry)
            do {
                let nestedURL = try Self.extractEntryToTemporaryDirectory(
                    entry, from: parentListing.archiveURL, into: nestedDir, password: pw, encoding: enc
                )

                passwordPurpose = .openNestedContents(entry, parentPassword: pw)
                let (inspectedNested, detectedAlgo, nestedIndex) = try Self.loadArchiveContents(
                    at: nestedURL, encoding: enc, password: nestedPassword
                )
                await MainActor.run {
                    self.isBusy = false
                    let backFrame = ArchiveNavigationFrame(
                        archiveURL: parentListing.archiveURL,
                        savedPassword: pw,
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
                    self.savedPassword = nestedPassword
                    self.preferredZipEditAlgorithm = detectedAlgo
                    self.statusMessage = "\(nestedURL.lastPathComponent) · \(self.l10n.itemCount(inspectedNested.entries.count))"
                }
            } catch {
                try? FileManager.default.removeItem(at: nestedDir)
                let purpose = passwordPurpose
                await MainActor.run {
                    self.isBusy = false
                    if let prompt = purpose.prompt(for: error) {
                        self.activeSheet = prompt
                    } else {
                        self.alertMessage = self.l10n.operationErrorMessage(error)
                    }
                }
            }
        }
    }
}
