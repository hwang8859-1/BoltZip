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
    private let selectedIDs: Set<String>

    init(vm: WorkspaceViewModel, initialMode: ExtractMode) {
        self.vm = vm
        self._destinationURL = State(
            initialValue: vm.listing?.archiveURL.deletingLastPathComponent()
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        )
        self._password = State(initialValue: vm.savedPassword ?? "")
        self._stripMacJunk = State(initialValue: vm.defaultStripMacJunk)

        switch initialMode {
        case .smart:
            self._choice = State(initialValue: .smart)
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

            BoltGlassContainer(spacing: 10) {
                HStack {
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
                            stripMacJunk: stripMacJunk
                        )
                        dismiss()
                        vm.runExtract(options: opts)
                    }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, BoltMetrics.cardFooterHPad)
                .padding(.vertical, BoltMetrics.cardFooterVPad)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
                )
            }
        }
        .padding(12)
        .frame(width: 430, height: 375)
        .boltUnifiedSheetStyle(vm: vm)
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
            Text(l.passwordPromptDesc)
                .font(BoltType.caption)
                .foregroundStyle(.secondary)
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
                        dismiss()
                        switch purpose {
                        case .openArchive(let url, let fromExternalFinder):
                            vm.openArchive(url: url, fromExternalFinder: fromExternalFinder, password: pw)
                        case .preview(let entry):
                            vm.previewOrOpenEntry(entry, password: pw)
                        case .extract(let archiveURL, var opts):
                            opts.password = pw
                            vm.runExtract(options: opts, archiveURL: archiveURL, skipConflictCheck: true)
                        case .testIntegrity(let archiveURL):
                            vm.testIntegrity(password: pw, archiveURL: archiveURL)
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
