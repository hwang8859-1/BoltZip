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
}
