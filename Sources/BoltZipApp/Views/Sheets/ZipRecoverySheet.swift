import BoltZipCore
import SwiftUI

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
            let defaultOut = BoltArchiveEngine.makeOutputURL(
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
        outputURL = BoltArchiveEngine.makeOutputURL(stem: "\(stem)_recovered", format: .zip, splitVolumeSizeBytes: nil, in: dir, deduplicating: true)
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
        let explicitPW = passwordInput.isEmpty ? nil : passwordInput
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
