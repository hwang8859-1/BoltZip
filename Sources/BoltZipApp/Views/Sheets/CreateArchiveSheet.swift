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
    @State private var archiveComment: String = ""
    @State private var moveSourcesToTrash: Bool = false
    @State private var isDropTargeted: Bool = false
    /// `-1` = follow global `BoltConcurrency`, `0` = auto, `>= 1` = explicit core count.
    @State private var workerSelection: Int = -1

    private static let unifiedControlWidth: CGFloat = 248

    enum SplitPreset: String, CaseIterable, Identifiable {
        case none
        case mb10
        case mb100
        case mb700
        case gb4
        case custom

        var id: String { rawValue }

        func compactTitle(_ l: L10n) -> String {
            switch self {
            case .none: return l.splitPresetNone
            case .mb10: return "10 MB"
            case .mb100: return "100 MB"
            case .mb700: return "700 MB"
            case .gb4: return "4 GB"
            case .custom: return l.customSplitShortTitle
            }
        }

        func menuTitle(_ l: L10n) -> String {
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
            headerCard(l: l, glassEnabled: glassEnabled)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
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

            footerCard(l: l, glassEnabled: glassEnabled)
        }
        .padding(12)
        .frame(width: 496, height: isStandaloneWindow ? 536 : 528)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            DropHelper.extractFileURLs(from: providers) { urls in
                appendInputURLs(urls)
            }
        }
        .modifier(CreateArchiveContainerStyleModifier(
            vm: vm,
            isStandaloneWindow: isStandaloneWindow,
            glassEnabled: glassEnabled
        ))
    }

    // MARK: - Top Header & Bottom Footer

    @ViewBuilder
    private func headerCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassContainer(spacing: 8) {
            HStack(spacing: 10) {
                BoltDocumentIconView(
                    kind: format.documentIconKind,
                    appTheme: vm.appTheme,
                    renderSize: 40,
                    displaySize: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(l.createArchiveTitle)
                        .font(BoltType.windowTitle)
                    Text(l.createArchiveSub)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                BoltReadOnlyBadge(
                    text: format.fileExtension.uppercased(),
                    isEmphasized: true
                )
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
    }

    @ViewBuilder
    private func footerCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltSheetFooterBar(glassEnabled: glassEnabled) {
            Image(systemName: "doc.zipper")
                .font(BoltType.captionMedium)
                .foregroundStyle(Color.accentColor)
            Text("\(l.willGeneratePrefix)\(resolvedOutputURL.lastPathComponent)")
                .font(BoltType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(l.cancel) { closeSheetOrWindow() }
                .boltGlassButton()
                .keyboardShortcut(.cancelAction)
            Button(l.startCompress) { startCompress() }
                .boltGlassProminentButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidInput)
        }
    }

    // MARK: - Section Cards

    @ViewBuilder
    private func outputTargetCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(
            l.outputTargetSection,
            icon: "folder.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 7
        ) {
            CompressInputRow(
                title: l.archiveNameField,
                trailingSuffix: ".\(format.fileExtension)",
                controlWidth: Self.unifiedControlWidth
            ) {
                TextField(l.archiveNameField, text: $archiveName)
                    .textFieldStyle(.roundedBorder)
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            CompressActionRow(
                title: l.saveLocationLabel,
                valueSubtitle: destinationDir.path,
                buttonTitle: l.createChooseBtn
            ) {
                chooseDestinationDir()
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            CompressActionRow(
                title: "\(l.inputItemsLabel) (\(inputs.count))",
                valueSubtitle: inputs.map(\.lastPathComponent).joined(separator: ", "),
                buttonTitle: l.createAddBtn
            ) {
                addMoreInputs()
            }
        }
    }

    @ViewBuilder
    private func formatAlgorithmCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(
            l.formatAlgoSection,
            icon: "gearshape.2.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 7
        ) {
            BoltFormMenuRow(
                title: l.archiveFormatLabel,
                selectedTitle: format.displayName
            ) {
                ForEach(ArchiveFormat.creatableFormats) { fmt in
                    BoltMenuOptionButton(
                        title: fmt.displayName,
                        isSelected: format == fmt
                    ) {
                        selectFormat(fmt)
                    }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormMenuRow(
                title: l.compressionAlgoLabel,
                subtitle: algorithm.openSourceLicenseNote,
                selectedTitle: algorithm.displayName
            ) {
                ForEach(format.supportedAlgorithms) { algo in
                    BoltMenuOptionButton(
                        title: "\(algo.displayName) — \(algo.openSourceLicenseNote)",
                        isSelected: algorithm == algo
                    ) {
                        algorithm = algo
                        level = preset.level(for: algo)
                    }
                }
            }

            if algorithm != .store {
                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack(alignment: .center, spacing: 10) {
                    Text(l.compressionPresetLabel)
                        .font(BoltType.subbodyMedium)
                    Spacer(minLength: 8)
                    Picker("", selection: $preset) {
                        ForEach(CompressionPreset.allCases.filter { $0 != .store }) { p in
                            Text(l.createPresetShortTitle(p)).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()
                    .onChange(of: preset) { _, newPreset in
                        level = newPreset.level(for: algorithm)
                    }
                }

                let range = algorithm.levelRange
                if range.lowerBound < range.upperBound {
                    BoltSectionDivider(glassEnabled: glassEnabled)

                    HStack(alignment: .center, spacing: 10) {
                        Text(l.fineLevelLabel)
                            .font(BoltType.subbodyMedium)
                        Slider(
                            value: Binding(
                                get: { Double(level) },
                                set: { level = Int($0.rounded()) }
                            ),
                            in: Double(range.lowerBound)...Double(range.upperBound),
                            step: 1
                        )
                        .controlSize(.small)
                        BoltReadOnlyBadge(
                            text: "\(level)",
                            isEmphasized: true
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func encryptionCard(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(
            l.encryptionSection,
            icon: "lock.shield.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 7
        ) {
            BoltFormMenuRow(
                title: l.encryptionMethodLabel,
                selectedTitle: l.encryptionCompactTitle(encryption)
            ) {
                ForEach(EncryptionMethod.allCases) { enc in
                    BoltMenuOptionButton(
                        title: enc.displayName,
                        isSelected: encryption == enc
                    ) {
                        encryption = enc
                    }
                }
            }

            if encryption != .none {
                BoltSectionDivider(glassEnabled: glassEnabled)

                CompressInputRow(
                    title: l.passwordPlaceholder,
                    controlWidth: Self.unifiedControlWidth
                ) {
                    SecureField(l.passwordPlaceholder, text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                CompressInputRow(
                    title: l.confirmPasswordField,
                    controlWidth: Self.unifiedControlWidth
                ) {
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
        BoltGlassSectionCard(
            l.advancedOptionsSection,
            icon: "slider.horizontal.3",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 7
        ) {
            if format.supportsSplitVolumes {
                BoltFormMenuRow(
                    title: l.splitVolumeLabel,
                    selectedTitle: splitPreset.compactTitle(l)
                ) {
                    ForEach(SplitPreset.allCases) { sp in
                        BoltMenuOptionButton(
                            title: sp.menuTitle(l),
                            isSelected: splitPreset == sp
                        ) {
                            splitPreset = sp
                        }
                    }
                }

                if splitPreset == .custom {
                    BoltSectionDivider(glassEnabled: glassEnabled)

                    CompressInputRow(
                        title: l.customSplitMBField,
                        trailingSuffix: "MB",
                        controlWidth: Self.unifiedControlWidth
                    ) {
                        TextField(l.customSplitMBField, text: $customSplitMB)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                BoltSectionDivider(glassEnabled: glassEnabled)
            }

            BoltFormSwitchRow(
                title: l.stripMacJunkTitle,
                subtitle: l.stripMacJunkSubtitle,
                isOn: $excludeMacJunk
            )

            if format == .zip {
                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormMenuRow(
                    title: l.filenameEncoding,
                    selectedTitle: l.encodingCompactTitle(encoding)
                ) {
                    ForEach([FilenameEncodingOption.utf8, .gb18030, .big5, .shiftJIS, .eucKR, .cp437]) { enc in
                        BoltMenuOptionButton(
                            title: l.encodingTitle(enc),
                            isSelected: encoding == enc
                        ) {
                            encoding = enc
                        }
                    }
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                CompressInputRow(
                    title: l.archiveCommentTitle,
                    controlWidth: Self.unifiedControlWidth
                ) {
                    TextField(l.archiveCommentPlaceholder, text: $archiveComment)
                        .textFieldStyle(.roundedBorder)
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormSwitchRow(
                title: l.moveSourcesToTrashToggle,
                isOn: $moveSourcesToTrash
            )

            if format == .zip || algorithm == .zstd || algorithm == .xz {
                let hwCores = vm.hardwareCoreCount
                let selectedLabel = selectedWorkersSummary(l)

                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormMenuRow(
                    title: l.multiCoreCountLabel,
                    selectedTitle: selectedLabel
                ) {
                    BoltMenuOptionButton(
                        title: l.multiCoreFollowGlobal(vm.multiCoreStatusSummary(l)),
                        isSelected: workerSelection == -1
                    ) {
                        workerSelection = -1
                    }

                    Divider()

                    BoltMenuOptionButton(
                        title: l.multiCoreMenuAuto(vm.autoWorkerCount),
                        isSelected: workerSelection == 0
                    ) {
                        workerSelection = 0
                    }

                    ForEach(1...hwCores, id: \.self) { cores in
                        BoltMenuOptionButton(
                            title: l.multiCoreMenuCoreOption(cores, total: hwCores),
                            isSelected: workerSelection == cores
                        ) {
                            workerSelection = cores
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions & Logic

    private func selectFormat(_ newFmt: ArchiveFormat) {
        format = newFmt
        if !newFmt.supportedAlgorithms.contains(algorithm) {
            algorithm = newFmt.defaultAlgorithm
        }
        level = preset.level(for: algorithm)
        if !newFmt.supportsEncryption { encryption = .none }
        if !newFmt.supportsSplitVolumes { splitPreset = .none }
    }

    private func selectedWorkersSummary(_ l: L10n) -> String {
        if workerSelection < 0 {
            return l.createFollowGlobalWorkers(vm.multiCoreStatusSummary(l))
        }
        if workerSelection == 0 {
            return l.multiCoreBadgeAuto(vm.autoWorkerCount)
        }
        return l.multiCoreBadgeManual(workerSelection)
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
            appendInputURLs(panel.urls)
        }
    }

    private func appendInputURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let existing = Set(inputs.map(\.path))
        for url in urls {
            let std = url.standardizedFileURL
            if !existing.contains(std.path) && !inputs.contains(where: { $0.path == std.path }) {
                inputs.append(std)
            }
        }
        if inputs.count == 1, archiveName == "Archive", let first = inputs.first {
            archiveName = first.deletingPathExtension().lastPathComponent
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
        let overrideWorkers: Int? = workerSelection < 0 ? nil : workerSelection
        let opts = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: encryption == .none ? nil : password,
            splitVolumeSizeBytes: resolvedSplitBytes,
            excludeMacJunk: excludeMacJunk,
            encoding: encoding,
            archiveComment: format == .zip ? archiveComment : "",
            workerCount: overrideWorkers,
            preserveSymlinks: vm.preserveSymlinksOnCreate
        )
        let out = resolvedOutputURL
        let useFloatingHUD = isStandaloneWindow && !vm.hasVisibleMainWindow
        let trashSources = moveSourcesToTrash
        closeSheetOrWindow()
        vm.createArchive(
            inputs: inputs,
            outputURL: out,
            options: opts,
            useFloatingHUD: useFloatingHUD,
            trashSourcesOnCompletion: trashSources
        )
    }
}

// MARK: - Unified Compress Row Primitives

private struct CompressInputRow<Field: View>: View {
    let title: String
    var trailingSuffix: String? = nil
    let controlWidth: CGFloat
    @ViewBuilder let field: () -> Field

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(BoltType.subbodyMedium)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                field()
                if let trailingSuffix, !trailingSuffix.isEmpty {
                    Text(trailingSuffix)
                        .font(BoltType.monoCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .frame(width: controlWidth)
        }
    }
}

private struct CompressActionRow: View {
    let title: String
    let valueSubtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BoltType.subbodyMedium)
                Text(valueSubtitle)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .controlSize(.small)
                .boltGlassButton()
                .fixedSize()
        }
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
                .environment(\.boltGlassIntensity, vm.glassIntensity)
                .boltUnifiedWindowContainerBackground(glassEnabled: glassEnabled)
                .preferredColorScheme(vm.appTheme.colorScheme)
        } else {
            content
                .boltUnifiedSheetStyle(vm: vm)
        }
    }
}
