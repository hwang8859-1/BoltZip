import AppKit
import BoltZipCore
import SwiftUI

struct CreateArchiveSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let isStandaloneWindow: Bool
    let onCloseWindow: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var inputs: [URL]
    @State private var archiveName: String
    @State private var destinationDir: URL
    @State private var format: ArchiveFormat = .zip
    @State private var algorithm: CompressionAlgorithm = .deflate
    @State private var preset: CompressionPreset = .balanced
    @State private var level: Int = 6
    @State private var encryption: EncryptionMethod = .none
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var splitPreset: SplitPreset = .none
    @State private var customSplitMB: String = "50"
    @State private var excludeMacJunk: Bool
    @State private var encoding: FilenameEncodingOption = .utf8

    enum SplitPreset: String, CaseIterable, Identifiable {
        case none
        case mb10
        case mb100
        case mb700
        case gb4
        case custom

        var id: String { rawValue }

        func title(_ l: L10n) -> String {
            switch self {
            case .none: return l.splitPresetNone
            case .mb10: return l.splitPreset10MB
            case .mb100: return "100 MB"
            case .mb700: return "700 MB (CD)"
            case .gb4: return "4 GB (FAT32)"
            case .custom: return l.splitPresetCustom
            }
        }
    }

    init(
        vm: WorkspaceViewModel,
        initialInputs: [URL],
        isStandaloneWindow: Bool = false,
        onCloseWindow: (() -> Void)? = nil
    ) {
        self.vm = vm
        self.isStandaloneWindow = isStandaloneWindow
        self.onCloseWindow = onCloseWindow
        _inputs = State(initialValue: initialInputs)
        let first = initialInputs.first
        let defaultName = initialInputs.count == 1
            ? (first?.deletingPathExtension().lastPathComponent ?? "Archive")
            : "Archive"
        _archiveName = State(initialValue: defaultName)
        _destinationDir = State(initialValue: first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
        _excludeMacJunk = State(initialValue: vm.defaultStripMacJunk)
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 10) {
            BoltGlassContainer(spacing: 8) {
                HStack(spacing: 10) {
                    BoltHeaderIconBadge(symbol: "bolt.fill", tint: .cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.createArchiveTitle)
                            .font(BoltType.windowTitle)
                        Text(l.createArchiveSub)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(format.fileExtension.uppercased())
                        .font(BoltType.badge)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .boltLayeredSurface(
                            glassEnabled: glassEnabled,
                            tone: .regular,
                            tint: .cyan.opacity(0.18),
                            in: Capsule()
                        )
                }
                .padding(.horizontal, BoltMetrics.cardHeaderHPad)
                .padding(.vertical, BoltMetrics.cardHeaderVPad)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 9) {
                    outputTargetCard(l: l, glassEnabled: glassEnabled)
                    formatAlgorithmCard(l: l, glassEnabled: glassEnabled)
                    if format.supportsEncryption {
                        encryptionCard(l: l, glassEnabled: glassEnabled)
                    }
                    advancedCard(l: l, glassEnabled: glassEnabled)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))

            BoltGlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.zipper")
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                    Text("\(l.willGeneratePrefix)\(resolvedOutputURL.lastPathComponent)")
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(l.cancel) { closeSheetOrWindow() }
                        .boltGlassButton()
                        .keyboardShortcut(.cancelAction)
                    Button(l.startCompress) { startCompress() }
                        .boltGlassProminentButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValidInput)
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
        .frame(width: 496, height: isStandaloneWindow ? 508 : 520)
        .modifier(CreateArchiveContainerStyleModifier(
            vm: vm,
            isStandaloneWindow: isStandaloneWindow,
            glassEnabled: glassEnabled
        ))
    }

    @ViewBuilder
    private func outputTargetCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.outputTargetSection, icon: "folder.fill", glassEnabled: glassEnabled) {
            HStack(spacing: 8) {
                Text(l.archiveNameField)
                    .lineLimit(1)
                    .frame(width: 146, alignment: .leading)
                TextField(l.archiveNameField, text: $archiveName)
                    .textFieldStyle(.roundedBorder)
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack(spacing: 10) {
                Text(l.saveLocationLabel)
                Spacer(minLength: 8)
                Text(destinationDir.path)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(l.change) { chooseDestinationDir() }
                    .controlSize(.small)
                    .boltGlassButton()
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack(spacing: 10) {
                Text("\(l.inputItemsLabel) (\(inputs.count))")
                Spacer(minLength: 8)
                Text(inputs.map(\.lastPathComponent).joined(separator: ", "))
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(l.add) { addMoreInputs() }
                    .controlSize(.small)
                    .boltGlassButton()
            }
        }
    }

    @ViewBuilder
    private func formatAlgorithmCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.formatAlgoSection, icon: "gearshape.2.fill", glassEnabled: glassEnabled) {
            HStack {
                Text(l.archiveFormatLabel)
                Spacer()
                Picker("", selection: $format) {
                    ForEach(ArchiveFormat.creatableFormats) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: BoltMetrics.createPickerWidth)
                .onChange(of: format) { _, newFmt in
                    if !newFmt.supportedAlgorithms.contains(algorithm) {
                        algorithm = newFmt.defaultAlgorithm
                    }
                    level = preset.level(for: algorithm)
                    if !newFmt.supportsEncryption { encryption = .none }
                    if !newFmt.supportsSplitVolumes { splitPreset = .none }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack {
                Text(l.compressionAlgoLabel)
                Spacer()
                Picker("", selection: $algorithm) {
                    ForEach(format.supportedAlgorithms) { algo in
                        Text("\(algo.displayName) — \(algo.openSourceLicenseNote)").tag(algo)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: BoltMetrics.createPickerWidth)
                .onChange(of: algorithm) { _, newAlgo in
                    level = preset.level(for: newAlgo)
                }
            }

            if algorithm != .store {
                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    Text(l.compressionPresetLabel)
                    Spacer()
                    Picker("", selection: $preset) {
                        ForEach(CompressionPreset.allCases.filter { $0 != .store }) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 264)
                    .onChange(of: preset) { _, newPreset in
                        level = newPreset.level(for: algorithm)
                    }
                }

                let range = algorithm.levelRange
                if range.lowerBound < range.upperBound {
                    HStack(spacing: 10) {
                        Text("\(l.fineLevelLabel): \(level)")
                            .monospacedDigit()
                            .frame(width: 104, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(level) },
                                set: { level = Int($0.rounded()) }
                            ),
                            in: Double(range.lowerBound)...Double(range.upperBound),
                            step: 1
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func encryptionCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.encryptionSection, icon: "lock.shield.fill", glassEnabled: glassEnabled) {
            HStack {
                Text(l.encryptionMethodLabel)
                Spacer()
                Picker("", selection: $encryption) {
                    ForEach(EncryptionMethod.allCases) { enc in
                        Text(enc.displayName).tag(enc)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: BoltMetrics.createPickerWidth)
            }

            if encryption != .none {
                BoltSectionDivider(glassEnabled: glassEnabled)
                HStack(spacing: 8) {
                    Text(l.passwordPlaceholder)
                        .frame(width: 104, alignment: .leading)
                    SecureField(l.passwordPlaceholder, text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 8) {
                    Text(l.confirmPasswordField)
                        .frame(width: 104, alignment: .leading)
                    SecureField(l.confirmPasswordField, text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }
                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text(l.passwordMismatch)
                        .font(BoltType.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func advancedCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.advancedOptionsSection, icon: "slider.horizontal.3", glassEnabled: glassEnabled) {
            if format.supportsSplitVolumes {
                HStack {
                    Text(l.splitVolumeLabel)
                    Spacer()
                    Picker("", selection: $splitPreset) {
                        ForEach(SplitPreset.allCases) { sp in
                            Text(sp.title(l)).tag(sp)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: BoltMetrics.createPickerWidth)
                }
                if splitPreset == .custom {
                    HStack(spacing: 8) {
                        Text(l.customSplitMBField)
                            .frame(width: 114, alignment: .leading)
                        TextField(l.customSplitMBField, text: $customSplitMB)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                BoltSectionDivider(glassEnabled: glassEnabled)
            }

            Toggle(l.stripMacJunkToggle, isOn: $excludeMacJunk)

            if format == .zip {
                BoltSectionDivider(glassEnabled: glassEnabled)
                HStack {
                    Text(l.filenameEncoding)
                    Spacer()
                    Picker("", selection: $encoding) {
                        ForEach([FilenameEncodingOption.utf8, .gb18030, .cp437]) { enc in
                            Text(l.encodingTitle(enc)).tag(enc)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: BoltMetrics.createPickerWidth)
                }
            }
        }
    }

    private var resolvedOutputURL: URL {
        let cleanName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleanName.isEmpty ? "Archive" : cleanName
        return destinationDir.appendingPathComponent("\(base).\(format.fileExtension)")
    }

    private var isValidInput: Bool {
        guard !inputs.isEmpty else { return false }
        if encryption != .none {
            return !password.isEmpty && password == confirmPassword
        }
        return true
    }

    private var resolvedSplitBytes: UInt64? {
        switch splitPreset {
        case .none: return nil
        case .mb10: return 10 * 1024 * 1024
        case .mb100: return 100 * 1024 * 1024
        case .mb700: return 700 * 1024 * 1024
        case .gb4: return 4 * 1024 * 1024 * 1024
        case .custom:
            guard let mb = UInt64(customSplitMB), mb >= 1 else { return nil }
            return mb * 1024 * 1024
        }
    }

    private func chooseDestinationDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            destinationDir = url
        }
    }

    private func addMoreInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            let existing = Set(inputs)
            for u in panel.urls where !existing.contains(u) {
                inputs.append(u)
            }
        }
    }

    private func closeSheetOrWindow() {
        if isStandaloneWindow {
            onCloseWindow?()
        } else {
            dismiss()
        }
    }

    private func startCompress() {
        let opts = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: encryption == .none ? nil : password,
            splitVolumeSizeBytes: resolvedSplitBytes,
            excludeMacJunk: excludeMacJunk,
            encoding: encoding
        )
        let out = resolvedOutputURL
        let useFloatingHUD = isStandaloneWindow && !vm.hasVisibleMainWindow
        closeSheetOrWindow()
        vm.createArchive(inputs: inputs, outputURL: out, options: opts, useFloatingHUD: useFloatingHUD)
    }
}

private struct CreateArchiveContainerStyleModifier: ViewModifier {
    @Bindable var vm: WorkspaceViewModel
    let isStandaloneWindow: Bool
    let glassEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isStandaloneWindow {
            content
                .background(BoltUnifiedWindowBacking(vm: vm))
                .background(
                    BoltAuxiliaryWindowStyleBridge(
                        isTranslucent: glassEnabled,
                        backgroundOpacity: vm.windowBackgroundOpacity
                    )
                )
                .boltWindowContainerBackground(
                    glassEnabled ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                )
                .boltWindowToolbarBackgroundVisibility(glassEnabled ? .hidden : .automatic)
                .preferredColorScheme(vm.appTheme.colorScheme)
        } else {
            content
                .boltUnifiedSheetStyle(vm: vm)
        }
    }
}
