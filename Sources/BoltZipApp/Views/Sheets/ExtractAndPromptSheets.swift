import AppKit
import BoltZipCore
import SwiftUI

struct ExtractOptionsSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case smart
        case here
        case subfolder
        case selected

        var id: String { rawValue }
    }

    @State private var choice: Choice
    @State private var destinationURL: URL
    @State private var overwritePolicy: OverwritePolicy = .overwrite
    @State private var password: String
    @State private var stripMacJunk: Bool
    @State private var moveArchiveToTrash: Bool = false
    private let selectedIDs: Set<String>

    init(vm: WorkspaceViewModel, initialMode: ExtractMode) {
        self.vm = vm
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let fallbackDir = vm.listing?.archiveURL.deletingLastPathComponent() ?? downloadsDir
        let initialDest: URL = {
            switch vm.defaultExtractDestination {
            case .downloads: return downloadsDir
            case .sameFolder, .ask: return fallbackDir
            }
        }()
        self._destinationURL = State(initialValue: initialDest)
        self._password = State(initialValue: vm.savedPassword ?? "")
        self._stripMacJunk = State(initialValue: vm.defaultStripMacJunk)

        switch initialMode {
        case .smart:
            self._choice = State(initialValue: vm.defaultExtractMode == .subfolder ? .subfolder : .smart)
            self.selectedIDs = []
        case .here:
            self._choice = State(initialValue: .here)
            self.selectedIDs = []
        case .subfolder:
            self._choice = State(initialValue: .subfolder)
            self.selectedIDs = []
        case .selected(let ids):
            self._choice = State(initialValue: ids.isEmpty ? .smart : .selected)
            self.selectedIDs = ids
        }
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            BoltGlassContainer(spacing: 10) {
                HStack(spacing: 12) {
                    BoltHeaderIconBadge(symbol: "square.and.arrow.down.on.square.fill", tint: .cyan)
                    Text(l.extractOptionsTitle)
                        .font(BoltType.windowTitle)
                    Spacer()
                }
                .padding(.horizontal, BoltMetrics.cardHeaderHPad)
                .padding(.vertical, BoltMetrics.cardHeaderVPad)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    level: .elevated,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    BoltGlassSectionCard(l.destFolderLabel, icon: "folder.fill", glassEnabled: glassEnabled) {
                        HStack(spacing: 10) {
                            Text(destinationURL.path)
                                .font(BoltType.subbody)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(l.browse) { chooseDest() }
                                .controlSize(.small)
                                .boltGlassButton()
                        }
                    }

                    BoltGlassSectionCard(l.extractModeLabel, icon: "shippingbox.and.arrow.backward.fill", glassEnabled: glassEnabled) {
                        HStack {
                            Text(l.extractModeLabel)
                            Spacer()
                            Picker("", selection: $choice) {
                                Text(l.ctxSmartExtractAll).tag(Choice.smart)
                                Text(l.ctxExtractSelHere).tag(Choice.here)
                                Text(l.ctxExtractAllSubfolder).tag(Choice.subfolder)
                                if !selectedIDs.isEmpty {
                                    Text(l.ctxExtractSelTo).tag(Choice.selected)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: BoltMetrics.pickerWidth)
                        }

                        BoltSectionDivider(glassEnabled: glassEnabled)

                        HStack {
                            Text(l.overwriteLabel)
                            Spacer()
                            Picker("", selection: $overwritePolicy) {
                                ForEach(OverwritePolicy.allCases) { pol in
                                    Text(pol.displayName).tag(pol)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: BoltMetrics.pickerWidth)
                        }

                        BoltSectionDivider(glassEnabled: glassEnabled)

                        Toggle(l.stripMacJunkToggle, isOn: $stripMacJunk)

                        BoltSectionDivider(glassEnabled: glassEnabled)

                        Toggle(l.moveArchiveToTrashToggle, isOn: $moveArchiveToTrash)
                    }

                    if vm.listing?.hasEncryptedEntries == true {
                        BoltGlassSectionCard(l.decryptPasswordSection, icon: "lock.fill", glassEnabled: glassEnabled) {
                            SecureField(l.passwordPlaceholder, text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Spacer()
                Button(l.cancel) { dismiss() }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)
                Button(l.startExtract) {
                    let mode: ExtractMode
                    switch choice {
                    case .smart: mode = .smart
                    case .here: mode = .here
                    case .subfolder: mode = .subfolder
                    case .selected: mode = .selected(selectedIDs)
                    }
                    let opts = ExtractOptions(
                        destinationURL: destinationURL,
                        mode: mode,
                        overwritePolicy: overwritePolicy,
                        password: password.isEmpty ? nil : password,
                        encoding: vm.encodingOption,
                        stripMacJunk: stripMacJunk,
                        restoreSymlinks: vm.restoreSymlinksOnExtract
                    )
                    let shouldTrashArchive = moveArchiveToTrash
                    dismiss()
                    vm.runExtract(options: opts, trashArchiveOnCompletion: shouldTrashArchive)
                }
                .boltGlassProminentButton()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 430, height: 405)
        .boltUnifiedSheetStyle(vm: vm)
        .onAppear {
            if vm.defaultExtractDestination == .ask {
                chooseDest()
            }
        }
    }

    private func chooseDest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
        }
    }
}

struct PasswordPromptSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let purpose: PasswordPurpose
    let wrongAttempt: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""

    var body: some View {
        let l = vm.l10n

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                Image(systemName: "lock.shield.fill")
                    .font(BoltType.displayTitle)
                    .foregroundStyle(.orange)
            }
            .frame(width: 54, height: 54)

            Text(l.passwordPromptTitle)
                .font(BoltType.windowTitle)
            Text(wrongAttempt ? l.retryArchivePassword : l.passwordPromptDesc)
                .font(BoltType.caption)
                .foregroundStyle(wrongAttempt ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)

            SecureField(l.passwordPlaceholder, text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            BoltGlassContainer(spacing: 10) {
                HStack {
                    Button(l.cancel) { dismiss() }
                        .boltGlassButton()
                        .keyboardShortcut(.cancelAction)
                    Button(l.confirm) {
                        let pw = password
                        vm.activeSheet = nil
                        switch purpose {
                        case .openArchive(let url, let fromExternalFinder, let isNestedOpening, let initialFolder, let encoding):
                            vm.openArchive(
                                url: url,
                                fromExternalFinder: fromExternalFinder,
                                password: pw,
                                isNestedOpening: isNestedOpening,
                                initialFolder: initialFolder,
                                encoding: encoding
                            )
                        case .returnToParent(let frameID):
                            vm.navigateBackFromNestedArchive(password: pw, expectedFrameID: frameID)
                        case .openNested(let entry):
                            vm.openNestedArchiveEntry(entry, password: pw)
                        case .openNestedContents(let entry, let parentPassword):
                            vm.openNestedArchiveEntry(entry, password: parentPassword, nestedPassword: pw)
                        case .preview(let entry):
                            vm.previewOrOpenEntry(entry, password: pw)
                        case .extract(let archiveURL, var opts, let trashArchiveOnCompletion):
                            opts.password = pw
                            vm.runExtract(options: opts, archiveURL: archiveURL, trashArchiveOnCompletion: trashArchiveOnCompletion)
                        case .exportSelectedZip(let request):
                            vm.runSelectedZipExport(request, password: pw)
                        case .testIntegrity(let archiveURL):
                            vm.testIntegrity(password: pw, archiveURL: archiveURL)
                        case .unlockForEdit(let urls, let targetFolder):
                            vm.unlockForEditAndAdd(urls: urls, targetFolder: targetFolder, password: pw)
                        case .editText(let entry):
                            vm.savedPassword = pw
                            vm.editEntryText(entry)
                        }
                    }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 340)
        .boltUnifiedSheetStyle(vm: vm)
    }
}

struct SimpleNamePromptSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let title: String
    let placeholder: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(
        vm: WorkspaceViewModel,
        title: String,
        initialValue: String = "",
        placeholder: String,
        confirmLabel: String,
        onConfirm: @escaping (String) -> Void
    ) {
        self.vm = vm
        self.title = title
        self.placeholder = placeholder
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        self._text = State(initialValue: initialValue)
    }

    var body: some View {
        let l = vm.l10n
        VStack(spacing: 12) {
            Text(title)
                .font(BoltType.windowTitle)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            BoltGlassContainer(spacing: 10) {
                HStack {
                    Button(l.cancel) { dismiss() }
                        .boltGlassButton()
                        .keyboardShortcut(.cancelAction)
                    Button(confirmLabel) {
                        onConfirm(text)
                        dismiss()
                    }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(18)
        .boltUnifiedSheetStyle(vm: vm)
    }
}

struct ArchiveCommentSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let canEdit: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var commentText: String

    init(vm: WorkspaceViewModel, initialComment: String, canEdit: Bool) {
        self.vm = vm
        self.canEdit = canEdit
        self._commentText = State(initialValue: initialComment)
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let byteCount = commentText.utf8.count

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "text.bubble.fill", tint: .cyan)
                Text(l.archiveCommentTitle)
                    .font(BoltType.windowTitle)
                Spacer()
                Text("\(byteCount) / 65535 B")
                    .font(BoltType.monoCaption)
                    .foregroundStyle(byteCount > 65535 ? Color.red : Color.secondary)
            }
            .padding(.horizontal, BoltMetrics.cardHeaderHPad)
            .padding(.vertical, BoltMetrics.cardHeaderVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            TextEditor(text: $commentText)
                .font(BoltType.subbody)
                .scrollContentBackground(.hidden)
                .disabled(!canEdit)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Spacer()
                Button(l.cancel) { dismiss() }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)
                if canEdit {
                    Button(l.saveBtn) {
                        let safe = String(decoding: Data(commentText.utf8.prefix(65535)), as: UTF8.self)
                        dismiss()
                        vm.updateArchiveComment(safe)
                    }
                    .boltGlassProminentButton()
                    .disabled(byteCount > 65535)
                }
            }
        }
        .padding(14)
        .frame(width: 440, height: 300)
        .boltUnifiedSheetStyle(vm: vm)
    }
}

struct UpdateAvailableSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let release: UpdateReleaseInfo
    @Environment(\.dismiss) private var dismiss

    @State private var isDownloading = false
    @State private var verifiedDMGURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let currentVer = UpdateCheckerService.currentAppVersionString()

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "arrow.down.circle.fill", tint: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.updateAvailableTitle)
                        .font(BoltType.windowTitle)
                    Text(l.updateSummaryLine(current: currentVer, latest: release.version))
                        .font(BoltType.monoCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if release.dmgSizeBytes > 0 {
                    BoltReadOnlyBadge(text: DropHelper.formatBytes(release.dmgSizeBytes))
                }
            }
            .padding(.horizontal, BoltMetrics.cardHeaderHPad)
            .padding(.vertical, BoltMetrics.cardHeaderVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            ScrollView(.vertical, showsIndicators: true) {
                Text(release.releaseNotes.isEmpty ? release.title : release.releaseNotes)
                    .font(BoltType.subbody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(BoltType.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Button(l.updateSkipVersionBtn) {
                    vm.skipUpdateVersion(release.version)
                    dismiss()
                }
                .controlSize(.small)
                .boltGlassButton()

                Button(l.updateViewOnGitHub) {
                    NSWorkspace.shared.open(release.htmlURL)
                }
                .controlSize(.small)
                .boltGlassButton()

                Spacer()

                Button(l.updateLaterBtn) { dismiss() }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)

                if let dmgURL = verifiedDMGURL {
                    Button(l.updateVerifiedOpenBtn) {
                        NSWorkspace.shared.open(dmgURL)
                        dismiss()
                    }
                    .boltGlassProminentButton()
                } else if release.dmgURL != nil {
                    Button(isDownloading ? l.updateDownloadingStatus : l.updateDownloadVerifyBtn) {
                        downloadAndVerify()
                    }
                    .boltGlassProminentButton()
                    .disabled(isDownloading)
                }
            }
        }
        .padding(14)
        .frame(width: 500, height: 380)
        .boltUnifiedSheetStyle(vm: vm)
    }

    private func downloadAndVerify() {
        isDownloading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let verifiedURL = try await UpdateCheckerService.downloadAndVerifyDMG(release: release)
                self.verifiedDMGURL = verifiedURL
                self.isDownloading = false
                NSWorkspace.shared.open(verifiedURL)
            } catch {
                self.errorMessage = error.localizedDescription
                self.isDownloading = false
            }
        }
    }
}
