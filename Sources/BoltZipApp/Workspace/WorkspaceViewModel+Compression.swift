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
        namingTemplate: String = "{name}",
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
            let base = CompressionProfile.defaultBaseStem(for: [input], format: options.format)
            let stem = CompressionProfile.resolveBaseStem(template: namingTemplate, defaultStem: base, format: options.format)
            let outURL = CompressionProfile.makeOutputURL(
                stem: stem,
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

    func batchCompressWithProfile(
        _ profile: CompressionProfile,
        inputs: [URL],
        destinationDirectory: URL? = nil,
        compressIndividually: Bool = false,
        useFloatingHUD: Bool = false
    ) {
        guard !inputs.isEmpty else { return }
        let clean = profile.sanitized()
        var sessionPassword: String? = nil
        if clean.encryption != .none {
            boltActivateAppToForeground()
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = l10n.passwordPromptTitle
            alert.informativeText = clean.name
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.placeholderString = l10n.passwordPlaceholder
            alert.accessoryView = field
            alert.addButton(withTitle: l10n.confirm)
            alert.addButton(withTitle: l10n.cancel)
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let pw = field.stringValue
            guard !pw.isEmpty else { return }
            sessionPassword = pw
        }
        let opts = CreateArchiveOptions(profile: clean, password: sessionPassword)
        let targetDir = destinationDirectory ?? inputs[0].deletingLastPathComponent()

        if compressIndividually && inputs.count > 1 {
            createArchivesIndividually(
                inputs: inputs,
                destinationDirectory: targetDir,
                options: opts,
                namingTemplate: clean.namingTemplate,
                useFloatingHUD: useFloatingHUD
            )
        } else {
            let outURL = clean.resolveOutputURL(for: inputs, in: targetDir)
            createArchive(inputs: inputs, outputURL: outURL, options: opts, useFloatingHUD: useFloatingHUD)
        }
    }

    func openConvertArchivesPanel(prefilled: [URL]? = nil) {
        if let prefilled, !prefilled.isEmpty {
            activeSheet = .convertArchives(prefilled)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.title = l10n.convertArchivesTitle
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let archives = BoltArchiveEngine.filterArchiveURLs(panel.urls)
            if !archives.isEmpty {
                activeSheet = .convertArchives(archives)
            }
        }
    }

    func openRecoverZipPanel(sourceURL: URL? = nil) {
        if let sourceURL {
            activeSheet = .recoverZip(initialSource: sourceURL)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        panel.title = l10n.recoverZipTitle
        if panel.runModal() == .OK, let url = panel.url {
            activeSheet = .recoverZip(initialSource: url)
        }
    }
}
