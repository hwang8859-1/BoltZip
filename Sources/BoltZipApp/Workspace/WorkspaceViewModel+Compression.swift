import AppKit
import BoltZipCore
import Foundation

extension WorkspaceViewModel {
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

    func createArchivesIndividually(
        inputs: [URL],
        destinationDirectory: URL,
        options: CreateArchiveOptions,
        useFloatingHUD: Bool = false,
        trashSourcesOnCompletion: Bool = false
    ) {
        guard !inputs.isEmpty else { return }
        if useFloatingHUD {
            configureHUD()
        } else {
            configureInAppHUD()
        }
        var reservedPaths: Set<String> = []
        for input in inputs {
            let base = BoltArchiveEngine.defaultBaseStem(for: [input], format: options.format)
            let outURL = BoltArchiveEngine.makeOutputURL(
                stem: base,
                format: options.format,
                splitVolumeSizeBytes: options.splitVolumeSizeBytes,
                in: destinationDirectory,
                deduplicating: true,
                reservedPaths: reservedPaths
            )
            reservedPaths.insert(outURL.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased())
            let op = QuickTaskHUDModel.Operation.compress(inputs: [input], outputURL: outURL, options: options)
            if trashSourcesOnCompletion {
                trashAfterSuccessByOpID[op.id] = [input]
            }
            if useFloatingHUD {
                hudModel.enqueue(op)
            } else {
                inAppTaskHUD.enqueue(op)
            }
        }
        statusMessage = "\(inputs.count)..."
    }

    func openRecoverZipPanel(sourceURL: URL? = nil) {
        if let sourceURL {
            activeSheet = .recoverZip(initialSource: sourceURL)
            return
        }
        if let currentURL = listing?.archiveURL, ArchiveFormat.isZipLike(url: currentURL) {
            activeSheet = .recoverZip(initialSource: currentURL)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.title = l10n.recoverZipMenuTitle
        panel.prompt = l10n.confirm
        if panel.runModal() == .OK, let url = panel.url {
            activeSheet = .recoverZip(initialSource: url)
        }
    }

    func openMCPHelpPanel() {
        activeSheet = .mcpHelp
    }
}
