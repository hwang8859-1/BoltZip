import AppKit
import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compression Presets & Batch Application Sheet

struct CompressionProfilesSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let initialProfileID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID?
    @State private var draftName: String = ""
    @State private var draftFormat: ArchiveFormat = .zip
    @State private var draftAlgorithm: CompressionAlgorithm = .deflate
    @State private var draftLevel: Int = 6
    @State private var draftEncryption: EncryptionMethod = .none
    @State private var draftEncryptNames: Bool = false
    @State private var draftSplitMB: String = ""
    @State private var draftExcludeMacJunk: Bool = true
    @State private var draftExcludePatterns: String = ""
    @State private var draftPreserveSymlinks: Bool = true
    @State private var draftNamingTemplate: String = "{name}"
    @State private var draftQuickDefault: Bool = false
    @State private var compressEachOnBatch: Bool = true
    @State private var statusBanner: String?

    init(vm: WorkspaceViewModel, initialProfileID: UUID? = nil) {
        self.vm = vm
        self.initialProfileID = initialProfileID
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "slider.horizontal.2.rectangle.and.arrow.trianglehead.2.clockwise", tint: .cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.presetManageBtn.replacingOccurrences(of: "…", with: ""))
                        .font(BoltType.windowTitle)
                    Text(l.presetManageSubtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(l.presetStarterBtn) {
                    importStarterTemplates()
                }
                .controlSize(.small)
                .boltGlassButton()

                Button(l.presetNewBtn) {
                    startBlankDraft()
                }
                .controlSize(.small)
                .boltGlassProminentButton()
            }
            .padding(.horizontal, BoltMetrics.cardHeaderHPad)
            .padding(.vertical, BoltMetrics.cardHeaderVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )

            HStack(spacing: 12) {
                listColumn(l: l, glassEnabled: glassEnabled)
                    .frame(width: 215)
                editorColumn(l: l, glassEnabled: glassEnabled)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                if let statusBanner {
                    Text(statusBanner)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(l.presetApplyBatchBtn) {
                    runBatchWithCurrentDraft()
                }
                .boltGlassButton()
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(l.close) { dismiss() }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 680, height: 500)
        .boltUnifiedSheetStyle(vm: vm)
        .onAppear {
            vm.refreshCompressionProfiles()
            if let initial = initialProfileID,
               let found = vm.compressionProfiles.first(where: { $0.id == initial }) {
                loadIntoDraft(found)
            } else if let first = vm.compressionProfiles.first {
                loadIntoDraft(first)
            } else {
                startBlankDraft()
            }
        }
    }

    @ViewBuilder
    private func listColumn(l: L10n, glassEnabled: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 5) {
                if vm.compressionProfiles.isEmpty {
                    Text(l.presetEmptyState)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                } else {
                    ForEach(vm.compressionProfiles) { profile in
                        Button {
                            loadIntoDraft(profile)
                        } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(BoltType.subbodyMedium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(profile.format.rawValue.uppercased()) · \(profile.algorithm.shortName) L\(profile.level)")
                                        .font(BoltType.badge)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if profile.isDefaultQuickPreset {
                                    BoltReadOnlyBadge(text: l.presetQuickBadge, dotColor: .green, isEmphasized: true)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedID == profile.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity)
        .boltLayeredSurface(
            glassEnabled: glassEnabled,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private func editorColumn(l: L10n, glassEnabled: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 8) {
                HStack {
                    Text(l.colName)
                        .font(BoltType.subbodyMedium)
                    Spacer()
                    TextField(l.presetNamePromptPlaceholder, text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormMenuRow(title: l.archiveFormatLabel, selectedTitle: draftFormat.displayName) {
                    ForEach(ArchiveFormat.creatableFormats) { fmt in
                        BoltMenuOptionButton(title: fmt.displayName, isSelected: draftFormat == fmt) {
                            draftFormat = fmt
                            if !fmt.supportedAlgorithms.contains(draftAlgorithm) {
                                draftAlgorithm = fmt.defaultAlgorithm
                            }
                            let range = draftAlgorithm.levelRange
                            draftLevel = min(range.upperBound, max(range.lowerBound, draftLevel))
                            if !fmt.supportsEncryption { draftEncryption = .none }
                            if fmt == .sevenZip && draftEncryption != .none { draftEncryption = .aes256 }
                            if !fmt.supportsSplitVolumes { draftSplitMB = "" }
                        }
                    }
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormMenuRow(title: l.compressionAlgoLabel, selectedTitle: draftAlgorithm.displayName) {
                    ForEach(draftFormat.supportedAlgorithms) { algo in
                        BoltMenuOptionButton(title: algo.displayName, isSelected: draftAlgorithm == algo) {
                            draftAlgorithm = algo
                            draftLevel = algo.defaultLevel
                        }
                    }
                }

                let range = draftAlgorithm.levelRange
                if range.lowerBound < range.upperBound {
                    BoltSectionDivider(glassEnabled: glassEnabled)
                    HStack {
                        Text(l.fineLevelLabel)
                            .font(BoltType.subbodyMedium)
                        Slider(
                            value: Binding(
                                get: { Double(draftLevel) },
                                set: { draftLevel = Int($0.rounded()) }
                            ),
                            in: Double(range.lowerBound)...Double(range.upperBound),
                            step: 1
                        )
                        BoltReadOnlyBadge(text: "\(draftLevel)", isEmphasized: true)
                    }
                }

                if draftFormat.supportsEncryption {
                    BoltSectionDivider(glassEnabled: glassEnabled)
                    let methods: [EncryptionMethod] = draftFormat.supportsFilenameEncryption ? [.none, .aes256] : EncryptionMethod.allCases
                    BoltFormMenuRow(title: l.encryptionMethodLabel, selectedTitle: draftEncryption.displayName) {
                        ForEach(methods) { m in
                            BoltMenuOptionButton(title: m.displayName, isSelected: draftEncryption == m) {
                                draftEncryption = m
                            }
                        }
                    }
                    if draftFormat.supportsFilenameEncryption && draftEncryption == .aes256 {
                        BoltFormSwitchRow(title: l.encryptFileNames, isOn: $draftEncryptNames)
                    }
                }

                if draftFormat.supportsSplitVolumes {
                    BoltSectionDivider(glassEnabled: glassEnabled)
                    HStack {
                        Text(l.splitVolumeLabel)
                            .font(BoltType.subbodyMedium)
                        Spacer()
                        TextField("MB (optional)", text: $draftSplitMB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    Text(l.namingTemplateLabel)
                        .font(BoltType.subbodyMedium)
                    Spacer()
                    TextField(l.namingTemplatePlaceholder, text: $draftNamingTemplate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                HStack {
                    Text(l.excludePatternsLabel)
                        .font(BoltType.subbodyMedium)
                    Spacer()
                    TextField(l.excludePatternsPlaceholder, text: $draftExcludePatterns)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormSwitchRow(title: l.stripMacJunkTitle, isOn: $draftExcludeMacJunk)
                BoltFormSwitchRow(title: l.preserveSymlinksTitle, isOn: $draftPreserveSymlinks)
                BoltFormSwitchRow(title: l.presetQuickDefaultTitle, isOn: $draftQuickDefault)
                BoltFormSwitchRow(title: l.compressIndividuallyLabel(2).replacingOccurrences(of: "2", with: "N"), isOn: $compressEachOnBatch)

                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    if let selectedID {
                        Button(l.delete, role: .destructive) {
                            try? CompressionProfileStore.shared.delete(id: selectedID)
                            vm.refreshCompressionProfiles()
                            if let next = vm.compressionProfiles.first {
                                loadIntoDraft(next)
                            } else {
                                startBlankDraft()
                            }
                        }
                        .boltGlassButton()
                    }
                    Spacer()
                    Button(l.saveBtn) {
                        saveDraft()
                    }
                    .boltGlassProminentButton()
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .boltLayeredSurface(
            glassEnabled: glassEnabled,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

    private func buildDraftProfile() -> CompressionProfile {
        let mib: UInt64 = 1024 * 1024
        let trimmedSplit = draftSplitMB.trimmingCharacters(in: .whitespacesAndNewlines)
        let splitBytes: UInt64?
        if let mb = UInt64(trimmedSplit), mb >= 1, mb <= UInt64.max / mib {
            splitBytes = mb * mib
        } else {
            splitBytes = nil
        }
        return CompressionProfile(
            id: selectedID ?? UUID(),
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            format: draftFormat,
            algorithm: draftAlgorithm,
            level: draftLevel,
            encryption: draftEncryption,
            encryptFileNames: draftEncryptNames,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: draftExcludeMacJunk,
            excludePatterns: ArchiveExcludeMatcher.parse(draftExcludePatterns),
            preserveSymlinks: draftPreserveSymlinks,
            encoding: .utf8,
            namingTemplate: draftNamingTemplate,
            isDefaultQuickPreset: draftQuickDefault
        ).sanitized()
    }

    private func loadIntoDraft(_ profile: CompressionProfile) {
        selectedID = profile.id
        draftName = profile.name
        draftFormat = profile.format
        draftAlgorithm = profile.algorithm
        draftLevel = profile.level
        draftEncryption = profile.encryption
        draftEncryptNames = profile.encryptFileNames
        if let bytes = profile.splitVolumeSizeBytes {
            draftSplitMB = String(max(1, bytes / (1024 * 1024)))
        } else {
            draftSplitMB = ""
        }
        draftExcludeMacJunk = profile.excludeMacJunk
        draftExcludePatterns = profile.excludePatterns.joined(separator: ", ")
        draftPreserveSymlinks = profile.preserveSymlinks
        draftNamingTemplate = profile.namingTemplate
        draftQuickDefault = profile.isDefaultQuickPreset
    }

    private func startBlankDraft() {
        selectedID = nil
        draftName = "Custom Preset"
        draftFormat = .zip
        draftAlgorithm = .deflate
        draftLevel = 6
        draftEncryption = .none
        draftEncryptNames = false
        draftSplitMB = ""
        draftExcludeMacJunk = vm.defaultStripMacJunk
        draftExcludePatterns = ""
        draftPreserveSymlinks = vm.preserveSymlinksOnCreate
        draftNamingTemplate = "{name}"
        draftQuickDefault = vm.compressionProfiles.isEmpty
    }

    private func importStarterTemplates() {
        for template in CompressionProfile.starterTemplates {
            _ = try? CompressionProfileStore.shared.upsert(template)
        }
        vm.refreshCompressionProfiles()
        if let first = vm.compressionProfiles.first {
            loadIntoDraft(first)
        }
    }

    private func saveDraft() {
        let profile = buildDraftProfile()
        do {
            let saved = try CompressionProfileStore.shared.upsert(profile)
            vm.refreshCompressionProfiles()
            loadIntoDraft(saved)
            statusBanner = saved.name
        } catch {
            statusBanner = vm.l10n.operationErrorMessage(error)
        }
    }

    private func runBatchWithCurrentDraft() {
        let profile = buildDraftProfile()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.title = profile.name
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        dismiss()
        vm.batchCompressWithProfile(
            profile,
            inputs: panel.urls,
            compressIndividually: compressEachOnBatch,
            useFloatingHUD: !vm.hasVisibleMainWindow
        )
    }
}

// MARK: - Damaged ZIP Recovery Sheet

struct ZipRecoverySheet: View {
    @Bindable var vm: WorkspaceViewModel
    let initialSource: URL?
    @Environment(\.dismiss) private var dismiss

    @State private var sourceURL: URL?
    @State private var outputURL: URL?
    @State private var passwordInput: String = ""
    @State private var isRunning: Bool = false
    @State private var progressFraction: Double = 0
    @State private var progressItem: String = ""
    @State private var report: ZipRecoveryReport?
    @State private var errorMessage: String?

    init(vm: WorkspaceViewModel, initialSource: URL? = nil) {
        self.vm = vm
        self.initialSource = initialSource
        _sourceURL = State(initialValue: initialSource)
        if let initialSource {
            let dir = initialSource.deletingLastPathComponent()
            let stem = BoltArchiveEngine.archiveBaseStem(initialSource)
            let defaultOut = CompressionProfile.makeOutputURL(
                stem: "\(stem)_recovered",
                format: .zip,
                splitVolumeSizeBytes: nil,
                in: dir,
                deduplicating: true
            )
            _outputURL = State(initialValue: defaultOut)
        }
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "bandage.fill", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.recoverZipTitle)
                        .font(BoltType.windowTitle)
                    Text(l.recoverZipSubtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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

            BoltGlassSectionCard(l.recoverZipTitle, icon: "doc.zipper", iconColor: .orange, glassEnabled: glassEnabled, contentSpacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.recoverZipSourceLabel).font(BoltType.subbodyMedium)
                        Text(sourceURL?.path ?? "—")
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(l.createChooseBtn) { chooseSourceZip() }
                        .controlSize(.small)
                        .boltGlassButton()
                        .disabled(isRunning)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.recoverZipOutputLabel).font(BoltType.subbodyMedium)
                        Text(outputURL?.path ?? "—")
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(l.createChooseBtn) { chooseOutputZip() }
                        .controlSize(.small)
                        .boltGlassButton()
                        .disabled(isRunning)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    Text(l.passwordPlaceholder)
                        .font(BoltType.subbodyMedium)
                    Spacer()
                    SecureField(l.passwordPlaceholder, text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .disabled(isRunning)
                }
            }

            if isRunning {
                VStack(spacing: 6) {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(.linear)
                    Text(progressItem)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(BoltType.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if let report {
                recoveryReportView(report, l: l, glassEnabled: glassEnabled)
            } else {
                Spacer(minLength: 0)
            }

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                if let saved = report?.recoveredArchiveURL {
                    Button(l.hudRevealBtn) {
                        NSWorkspace.shared.activateFileViewerSelecting([saved])
                    }
                    .boltGlassButton()
                }
                Spacer()
                Button(l.close) { dismiss() }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)

                Button(l.recoverZipStartBtn) {
                    runRecovery()
                }
                .boltGlassProminentButton()
                .disabled(isRunning || sourceURL == nil || outputURL == nil)
            }
        }
        .padding(12)
        .frame(width: 560, height: 490)
        .boltUnifiedSheetStyle(vm: vm)
    }

    @ViewBuilder
    private func recoveryReportView(_ report: ZipRecoveryReport, l: L10n, glassEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                BoltReadOnlyBadge(
                    text: l.recoverZipSummary(scanned: report.totalScannedCount, recovered: report.recoveredCount, failed: report.unrecoverableCount),
                    dotColor: report.recoveredCount > 0 ? .green : .red,
                    isEmphasized: true
                )
                Spacer()
                if report.usedLocalHeaderFallbackScan {
                    BoltReadOnlyBadge(text: l.recoverZipFallbackUsed, dotColor: .orange)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(report.recoveredEntries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(entry.path)
                                .font(BoltType.subbody)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(DropHelper.formatBytes(entry.uncompressedSize))
                                .font(BoltType.monoCaption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }

                    if !report.unrecoverableEntries.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text(l.recoverZipUnrecoverableSection)
                            .font(BoltType.captionMedium)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                        ForEach(report.unrecoverableEntries) { fail in
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                                Text(fail.entryPath)
                                    .font(BoltType.subbody)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(fail.reason)
                                    .font(BoltType.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: BoltRadius.row))
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
            .boltLayeredSurface(glassEnabled: glassEnabled, tone: .regular, in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
        }
    }

    private func chooseSourceZip() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceURL = url
        let dir = url.deletingLastPathComponent()
        let stem = BoltArchiveEngine.archiveBaseStem(url)
        outputURL = CompressionProfile.makeOutputURL(stem: "\(stem)_recovered", format: .zip, splitVolumeSizeBytes: nil, in: dir, deduplicating: true)
    }

    private func chooseOutputZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "recovered.zip"
        if let dir = sourceURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
    }

    private func runRecovery() {
        guard let src = sourceURL, let out = outputURL else { return }
        let explicitPW = passwordInput.isEmpty ? vm.keychainPassword(for: src) : passwordInput
        let enc = vm.encodingOption
        isRunning = true
        errorMessage = nil
        report = nil
        progressFraction = 0
        progressItem = src.lastPathComponent

        Task.detached(priority: .userInitiated) {
            do {
                let res = try BoltArchiveEngine.recoverZip(
                    at: src,
                    to: out,
                    password: explicitPW,
                    encoding: enc
                ) { prog in
                    Task { @MainActor in
                        progressFraction = prog.fractionCompleted
                        progressItem = prog.currentItem
                    }
                }
                await MainActor.run {
                    isRunning = false
                    report = res
                    if res.recoveredCount > 0 {
                        vm.statusMessage = res.recoveredArchiveURL?.lastPathComponent ?? ""
                    } else if res.unrecoverableCount > 0 {
                        errorMessage = vm.l10n.operationErrorMessage(ArchiveOperationError.noRecoverableZipEntries)
                    }
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = vm.l10n.operationErrorMessage(error)
                }
            }
        }
    }
}

// MARK: - Batch Format Conversion Sheet

struct ConvertArchivesSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let initialSources: [URL]
    @Environment(\.dismiss) private var dismiss

    @State private var sources: [URL]
    @State private var destinationDir: URL
    @State private var format: ArchiveFormat = .zip
    @State private var algorithm: CompressionAlgorithm = .deflate
    @State private var level: Int = 6
    @State private var namingTemplate: String = "{name}"
    @State private var splitMB: String = ""
    @State private var excludePatternsText: String = ""
    @State private var passwordInput: String = ""
    @State private var selectedProfileID: UUID? = nil
    @State private var excludeMacJunk: Bool
    @State private var preserveSymlinks: Bool
    @State private var encryptFileNames: Bool = false
    @State private var overwritePolicy: OverwritePolicy = .rename
    @State private var isRunning: Bool = false
    @State private var progressFraction: Double = 0
    @State private var progressItem: String = ""
    @State private var report: ArchiveConversionReport?
    @State private var errorMessage: String?

    init(vm: WorkspaceViewModel, initialSources: [URL]) {
        self.vm = vm
        self.initialSources = initialSources
        _sources = State(initialValue: initialSources)
        let firstDir = initialSources.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        _destinationDir = State(initialValue: firstDir)
        _excludeMacJunk = State(initialValue: vm.defaultStripMacJunk)
        _preserveSymlinks = State(initialValue: vm.preserveSymlinksOnCreate)
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BoltHeaderIconBadge(symbol: "arrow.triangle.2.circlepath.doc.on.clipboard", tint: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.convertArchivesTitle)
                        .font(BoltType.windowTitle)
                    Text(l.convertArchivesSubtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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

            BoltGlassSectionCard(l.convertArchivesTitle, icon: "gearshape.2.fill", iconColor: .indigo, glassEnabled: glassEnabled, contentSpacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(l.convertSourceCountLabel) (\(sources.count))")
                            .font(BoltType.subbodyMedium)
                        Text(sources.map(\.lastPathComponent).joined(separator: ", "))
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(l.createChooseBtn) { chooseSourceArchives() }
                        .controlSize(.small)
                        .boltGlassButton()
                        .disabled(isRunning)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.convertDestDirLabel).font(BoltType.subbodyMedium)
                        Text(destinationDir.path)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(l.createChooseBtn) { chooseDestinationDirectory() }
                        .controlSize(.small)
                        .boltGlassButton()
                        .disabled(isRunning)
                }

                BoltSectionDivider(glassEnabled: glassEnabled)

                if !vm.compressionProfiles.isEmpty {
                    BoltFormMenuRow(title: l.presetMenuTitle, selectedTitle: selectedPresetTitle(l)) {
                        BoltMenuOptionButton(title: l.presetNoneLabel, isSelected: selectedProfileID == nil) {
                            selectedProfileID = nil
                        }
                        Divider()
                        ForEach(vm.compressionProfiles) { p in
                            BoltMenuOptionButton(title: p.name, isSelected: selectedProfileID == p.id) {
                                applyProfile(p)
                            }
                        }
                    }
                    BoltSectionDivider(glassEnabled: glassEnabled)
                }

                BoltFormMenuRow(title: l.convertTargetFormatLabel, selectedTitle: format.displayName) {
                    ForEach(ArchiveFormat.creatableFormats) { fmt in
                        BoltMenuOptionButton(title: fmt.displayName, isSelected: format == fmt) {
                            format = fmt
                            if !fmt.supportedAlgorithms.contains(algorithm) {
                                algorithm = fmt.defaultAlgorithm
                                level = algorithm.defaultLevel
                            }
                            if !fmt.supportsSplitVolumes { splitMB = "" }
                        }
                    }
                }

                BoltFormMenuRow(title: l.compressionAlgoLabel, selectedTitle: algorithm.displayName) {
                    ForEach(format.supportedAlgorithms) { algo in
                        BoltMenuOptionButton(title: algo.displayName, isSelected: algorithm == algo) {
                            algorithm = algo
                            level = algo.defaultLevel
                        }
                    }
                }

                BoltFormMenuRow(title: l.overwriteLabel, selectedTitle: overwriteTitle(for: overwritePolicy, l: l)) {
                    ForEach([OverwritePolicy.rename, .skip, .overwrite], id: \.rawValue) { pol in
                        BoltMenuOptionButton(title: overwriteTitle(for: pol, l: l), isSelected: overwritePolicy == pol) {
                            overwritePolicy = pol
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(l.namingTemplatePlaceholder, text: $namingTemplate)
                        .textFieldStyle(.roundedBorder)
                    TextField(l.excludePatternsPlaceholder, text: $excludePatternsText)
                        .textFieldStyle(.roundedBorder)
                    if format.supportsSplitVolumes {
                        TextField("MB", text: $splitMB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }
                }

                HStack {
                    Text(l.passwordPlaceholder).font(BoltType.subbodyMedium)
                    Spacer()
                    SecureField(l.convertOptionalPasswordPlaceholder, text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            if isRunning {
                VStack(spacing: 4) {
                    ProgressView(value: progressFraction).progressViewStyle(.linear)
                    Text(progressItem).font(BoltType.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(BoltType.caption).foregroundStyle(.red)
            }

            if let report {
                VStack(alignment: .leading, spacing: 4) {
                    BoltReadOnlyBadge(
                        text: l.convertSummaryLine(report.succeededCount, report.results.count),
                        dotColor: report.isAllHealthy ? .green : .orange,
                        isEmphasized: true
                    )
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(report.results.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(item.succeeded ? .green : .red)
                                    Text(item.sourceURL.lastPathComponent)
                                        .font(BoltType.subbodyMedium)
                                    Spacer()
                                    if item.succeeded {
                                        Text(item.destinationURLs.map(\.lastPathComponent).joined(separator: ", "))
                                            .font(BoltType.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    } else {
                                        Text(item.error.map { vm.l10n.operationErrorMessage($0) } ?? "")
                                            .font(BoltType.caption)
                                            .foregroundStyle(.red)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 110)
                    .boltLayeredSurface(glassEnabled: glassEnabled, tone: .regular, in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
                }
            }

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                if let firstDest = report?.results.first(where: { $0.succeeded && !$0.destinationURLs.isEmpty })?.destinationURLs.first {
                    Button(l.hudRevealBtn) {
                        NSWorkspace.shared.activateFileViewerSelecting([firstDest])
                    }
                    .boltGlassButton()
                }
                Spacer()
                Button(l.close) { dismiss() }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)
                Button(l.convertStartBtn) { runConversion() }
                    .boltGlassProminentButton()
                    .disabled(isRunning || sources.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 600, height: 560)
        .boltUnifiedSheetStyle(vm: vm)
        .onAppear { vm.refreshCompressionProfiles() }
    }

    private func overwriteTitle(for policy: OverwritePolicy, l: L10n) -> String {
        switch policy {
        case .rename: return l.batchOverwriteRename
        case .skip: return l.batchOverwriteSkip
        case .overwrite: return l.batchOverwriteReplace
        }
    }

    private func selectedPresetTitle(_ l: L10n) -> String {
        guard let selectedProfileID,
              let prof = vm.compressionProfiles.first(where: { $0.id == selectedProfileID }) else {
            return l.presetNoneLabel
        }
        return prof.name
    }

    private func applyProfile(_ profile: CompressionProfile) {
        let clean = profile.sanitized()
        selectedProfileID = clean.id
        format = clean.format
        algorithm = clean.algorithm
        level = clean.level
        namingTemplate = clean.namingTemplate
        excludePatternsText = clean.excludePatterns.joined(separator: ", ")
        excludeMacJunk = clean.excludeMacJunk
        preserveSymlinks = clean.preserveSymlinks
        encryptFileNames = clean.encryptFileNames
        if let bytes = clean.splitVolumeSizeBytes {
            splitMB = String(max(1, bytes / (1024 * 1024)))
        } else {
            splitMB = ""
        }
    }

    private func chooseSourceArchives() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        sources = BoltArchiveEngine.filterArchiveURLs(panel.urls)
    }

    private func chooseDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationDir = url
    }

    private func runConversion() {
        let mib: UInt64 = 1024 * 1024
        let splitBytes: UInt64?
        if format.supportsSplitVolumes,
           let mb = UInt64(splitMB.trimmingCharacters(in: .whitespacesAndNewlines)),
           mb >= 1, mb <= UInt64.max / mib {
            splitBytes = mb * mib
        } else {
            splitBytes = nil
        }
        let pw: String? = passwordInput.isEmpty ? nil : passwordInput
        let encMethod: EncryptionMethod = pw == nil || !format.supportsEncryption ? .none : .aes256
        let opts = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            level: level,
            encryption: encMethod,
            password: pw,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: excludeMacJunk,
            excludePatterns: ArchiveExcludeMatcher.parse(excludePatternsText),
            preserveSymlinks: preserveSymlinks,
            encryptFileNames: format.supportsFilenameEncryption && encMethod == .aes256 && encryptFileNames
        )
        let currentSources = sources
        let dest = destinationDir
        let template = namingTemplate
        let policy = overwritePolicy
        let enc = vm.encodingOption
        let l10nCopy = vm.l10n

        isRunning = true
        errorMessage = nil
        report = nil
        progressFraction = 0
        progressItem = ""

        let passwordProvider: @Sendable (URL, Bool) throws -> String? = { archiveURL, wrongAttempt in
            if !wrongAttempt, let kc = ArchiveKeychainService.shared.password(for: archiveURL), !kc.isEmpty {
                return kc
            }
            return DispatchQueue.main.sync {
                boltActivateAppToForeground()
                let alert = NSAlert()
                alert.alertStyle = wrongAttempt ? .warning : .informational
                alert.messageText = l10nCopy.passwordPromptTitle
                alert.informativeText = wrongAttempt
                    ? "\(archiveURL.lastPathComponent) — \(l10nCopy.retryArchivePassword)"
                    : "\(archiveURL.lastPathComponent) — \(l10nCopy.passwordPromptDesc)"
                let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
                field.placeholderString = l10nCopy.passwordPlaceholder
                alert.accessoryView = field
                alert.addButton(withTitle: l10nCopy.confirm)
                alert.addButton(withTitle: l10nCopy.cancel)
                alert.window.initialFirstResponder = field
                guard alert.runModal() == .alertFirstButtonReturn else {
                    return nil
                }
                return field.stringValue.isEmpty ? nil : field.stringValue
            }
        }

        Task.detached(priority: .userInitiated) {
            do {
                let res = try BoltArchiveEngine.convertArchives(
                    sources: currentSources,
                    destinationDirectory: dest,
                    options: opts,
                    sourcePassword: pw,
                    sourcePasswordProvider: passwordProvider,
                    overwritePolicy: policy,
                    encoding: enc,
                    namingTemplate: template
                ) { prog in
                    Task { @MainActor in
                        progressFraction = prog.fractionCompleted
                        progressItem = prog.currentItem
                    }
                }
                await MainActor.run {
                    isRunning = false
                    report = res
                    vm.statusMessage = vm.l10n.convertSummaryLine(res.succeededCount, res.results.count)
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = vm.l10n.operationErrorMessage(error)
                }
            }
        }
    }
}
