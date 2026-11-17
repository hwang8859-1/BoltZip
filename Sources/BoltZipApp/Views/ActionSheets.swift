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
        self._destinationURL = State(initialValue: vm.listing?.archiveURL.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
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
            // Header card
            BoltGlassContainer(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.cyan.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.cyan.opacity(0.30), lineWidth: 0.75)
                            )
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    .frame(width: 34, height: 34)

                    Text(l.extractOptionsTitle)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }

            ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        BoltGlassSectionCard(l.destFolderLabel, icon: "folder.fill", glassEnabled: glassEnabled) {
                            HStack(spacing: 10) {
                                Text(destinationURL.path)
                                    .font(.callout)
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
                                .frame(maxWidth: 230)
                            }

                            Divider().opacity(glassEnabled ? 0.28 : 0.6)

                            HStack {
                                Text(l.overwriteLabel)
                                Spacer()
                                Picker("", selection: $overwritePolicy) {
                                    ForEach(OverwritePolicy.allCases) { pol in
                                        Text(pol.displayName).tag(pol)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 230)
                            }

                            Divider().opacity(glassEnabled ? 0.28 : 0.6)

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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .padding(14)
        .frame(width: 500, height: 430)
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
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
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
            }
            .frame(width: 54, height: 54)

            Text(l.passwordPromptTitle)
                .font(.headline)
            Text(l.passwordPromptDesc)
                .font(.caption)
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
                        case .preview(let entry):
                            vm.previewOrOpenEntry(entry, password: pw)
                        case .extract(let archiveURL, var opts):
                            opts.password = pw
                            vm.runExtract(options: opts, archiveURL: archiveURL)
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
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
    }
}

struct EntryPropertiesSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let entry: ArchiveEntry
    @Environment(\.dismiss) private var dismiss

    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        BoltGlassContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.headline)
                        Text(entry.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                VStack(spacing: 8) {
                    PropRow(title: l.colOriginalSize, value: entry.isDirectory ? "—" : "\(DropHelper.formatBytes(entry.uncompressedSize)) (\(entry.uncompressedSize) B)")
                    PropRow(title: l.colPackedSize, value: entry.isDirectory ? "—" : "\(DropHelper.formatBytes(entry.compressedSize)) (\(entry.compressedSize) B)")
                    PropRow(title: l.colRatio, value: entry.isDirectory ? "—" : String(format: "%.2f%%", entry.compressionRatioPercent))
                    PropRow(title: l.colMethod, value: entry.compressionMethodName)
                    PropRow(title: l.encryptedBadge, value: entry.isEncrypted ? entry.encryptionLabel : "—")
                    PropRow(title: "CRC32", value: entry.crc32 == 0 ? "0x00000000" : String(format: "0x%08X", entry.crc32))
                    PropRow(title: "POSIX", value: String(format: "0o%03o", entry.permissions))
                    PropRow(title: l.colModified, value: Self.formatter.string(from: entry.modifiedDate))
                }
                .padding(14)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Button(l.close) { dismiss() }
                        .boltGlassProminentButton()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 450, height: 375)
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
    }
}

private struct PropRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

struct IntegrityReportSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let report: IntegrityReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        BoltGlassContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(report.isHealthy ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(l.verify) · \(report.archiveName)")
                            .font(.headline)
                        Text("\(report.passedCount)/\(report.totalEntries) · \(String(format: "%.2fs", report.elapsedSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: (report.isHealthy ? Color.green : Color.red).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(report.results) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(item.status == .passed ? .green : (item.status == .missingPassword ? .orange : .red))
                                Text(item.path)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                HStack {
                    Spacer()
                    Button(l.close) { dismiss() }
                        .boltGlassProminentButton()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 560, height: 400)
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
    }
}

struct BenchmarkSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var results: [BenchmarkEntryResult] = []
    @State private var isRunning = false
    @State private var errorMsg: String?
    @State private var hoveredIndex: Int?

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let isDark = colorScheme == .dark
        let maxDecompress = results.map(\.decompressMBps).max() ?? 0

        BoltGlassContainer(spacing: 12) {
            VStack(spacing: 12) {
                // Header glass card
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.cyan.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.cyan.opacity(0.32), lineWidth: 0.75)
                            )
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.benchmarkTitle)
                            .font(.headline)
                        Text(l.benchmarkSub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isRunning ? "..." : l.rerunBench) {
                        runBench()
                    }
                    .boltGlassButton()
                    .disabled(isRunning)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(isDark ? 0.05 : 0.06),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                // Results glass panel
                VStack(spacing: 0) {
                    if isRunning {
                        ProgressView(l.runningBench)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMsg {
                        Text(errorMsg)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Column Header
                        HStack(spacing: 10) {
                            Text(l.colMethod)
                                .frame(width: 148, alignment: .leading)
                            Text(l.colPackedSize)
                                .frame(width: 82, alignment: .trailing)
                            Text(l.colRatio)
                                .frame(width: 112, alignment: .trailing)
                            Text(l.compressSpeedCol)
                                .frame(width: 100, alignment: .trailing)
                            Text(l.decompressSpeedCol)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(glassEnabled ? 0.04 : 0.03))

                        Divider().opacity(glassEnabled ? 0.28 : 0.6)

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 4) {
                                ForEach(Array(results.enumerated()), id: \.offset) { idx, r in
                                    let isFastest = maxDecompress > 0 && r.decompressMBps >= maxDecompress - 0.01
                                    HStack(spacing: 10) {
                                        HStack(spacing: 6) {
                                            Text(r.algorithm.shortName)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("lvl \(r.level)")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.07), in: Capsule())
                                        }
                                        .frame(width: 148, alignment: .leading)

                                        Text(DropHelper.formatBytes(UInt64(r.compressedBytes)))
                                            .font(.system(size: 12.5))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(width: 82, alignment: .trailing)

                                        HStack(spacing: 6) {
                                            GeometryReader { barGeo in
                                                let pct = min(max(r.ratioPercent / 100.0, 0), 1)
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.primary.opacity(0.08))
                                                    Capsule()
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [.green, .mint],
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                        .frame(width: max(4, barGeo.size.width * pct))
                                                }
                                            }
                                            .frame(width: 38, height: 5)

                                            Text(String(format: "%.1f%%", r.ratioPercent))
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(.green)
                                        }
                                        .frame(width: 112, alignment: .trailing)

                                        Text(String(format: "%.1f MB/s", r.compressMBps))
                                            .font(.system(size: 12.5))
                                            .monospacedDigit()
                                            .frame(width: 100, alignment: .trailing)

                                        Text(String(format: "%.1f MB/s", r.decompressMBps))
                                            .font(.system(size: 12.5, weight: isFastest ? .semibold : .regular))
                                            .monospacedDigit()
                                            .foregroundStyle(isFastest ? Color.cyan : Color.primary)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(
                                                hoveredIndex == idx
                                                    ? Color.primary.opacity(0.08)
                                                    : (idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                                            )
                                    )
                                    .onHover { inside in
                                        hoveredIndex = inside ? idx : (hoveredIndex == idx ? nil : hoveredIndex)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: Color.white.opacity(isDark ? 0.03 : 0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                // Footer pill
                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(l.benchHardwareNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(l.done) { dismiss() }
                        .boltGlassProminentButton()
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .padding(14)
        }
        .frame(width: 640, height: 396)
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
        .onAppear {
            if results.isEmpty { runBench() }
        }
    }

    private func runBench() {
        isRunning = true
        errorMsg = nil
        Task.detached(priority: .userInitiated) {
            do {
                let res = try BenchmarkRunner.run()
                await MainActor.run {
                    self.results = res
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
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

    init(vm: WorkspaceViewModel, title: String, initialValue: String = "", placeholder: String, confirmLabel: String, onConfirm: @escaping (String) -> Void) {
        self.vm = vm
        self.title = title
        self.placeholder = placeholder
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        self._text = State(initialValue: initialValue)
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        VStack(spacing: 12) {
            Text(title).font(.headline)
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
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
    }
}

struct SettingsView: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case general
        case appearance
        case codecs

        var id: Int { rawValue }
    }

    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .general
    @State private var feedbackMessage: String?

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            // Layer 3: Floating Glass Tab Bar
            BoltGlassContainer(spacing: 6) {
                HStack(spacing: 6) {
                    tabPill(tab: .general, title: l.settingsTabGeneral, icon: "gearshape.fill", glassEnabled: glassEnabled)
                    tabPill(tab: .appearance, title: l.settingsTabAppearance, icon: "slider.horizontal.3", glassEnabled: glassEnabled)
                    tabPill(tab: .codecs, title: l.settingsTabCodecs, icon: "cpu", glassEnabled: glassEnabled)
                }
                .padding(5)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }

            // Layer 2: Active Settings Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .general:
                        generalTabContent(l: l, glassEnabled: glassEnabled)
                    case .appearance:
                        appearanceTabContent(l: l, glassEnabled: glassEnabled)
                    case .codecs:
                        codecsTabContent(l: l, glassEnabled: glassEnabled)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Footer with close button
            BoltGlassContainer(spacing: 10) {
                HStack {
                    Text(BoltPlatformCapabilities.runtimeVersionSummary(
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.0"
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(l.close) {
                        NSApp.keyWindow?.performClose(nil)
                        dismiss()
                    }
                    .boltGlassProminentButton()
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .padding(16)
        .frame(width: 620, height: 500)
        .background {
            if glassEnabled {
                ZStack {
                    BoltAmbientBackdrop()
                        .opacity(max(0.15, 0.9 - vm.windowBackgroundOpacity * 0.45))
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(max(0.0, vm.windowBackgroundOpacity - 0.35))
                        .ignoresSafeArea()
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
        }
        .background(
            BoltAuxiliaryWindowStyleBridge(
                isTranslucent: glassEnabled,
                backgroundOpacity: vm.windowBackgroundOpacity
            )
        )
        .boltWindowContainerBackground(
            glassEnabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .boltWindowToolbarBackgroundVisibility(glassEnabled ? .hidden : .automatic)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }

    @ViewBuilder
    private func tabPill(tab: Tab, title: String, icon: String, glassEnabled: Bool) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(glassEnabled ? 0.18 : 0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75)
                            )
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func generalTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.settingsTabGeneral, icon: "gearshape.fill", glassEnabled: glassEnabled) {
            Toggle(l.stripMacJunkToggle, isOn: Binding(
                get: { vm.defaultStripMacJunk },
                set: { vm.updateDefaultStripMacJunk($0) }
            ))

            Divider().opacity(glassEnabled ? 0.28 : 0.6)

            HStack {
                Text(l.defaultEncodingLabel)
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.encodingOption },
                    set: { vm.encodingOption = $0 }
                )) {
                    ForEach(FilenameEncodingOption.allCases) { enc in
                        Text(l.encodingTitle(enc)).tag(enc)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 230)
            }
        }

        BoltGlassSectionCard(l.finderIntegrationSection, icon: "contextualmenu.and.cursorarrow", glassEnabled: glassEnabled, tint: .cyan.opacity(0.05)) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.quickActionsInstalled ? l.finderEnabledSummary : l.finderDisabledSummary)
                        .font(.subheadline.weight(.medium))
                    Text(l.finderBannerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l.extensionSettings) {
                    vm.openFinderExtensionSettings()
                }
                .controlSize(.small)
                .boltGlassButton()

                Button(vm.quickActionsInstalled ? l.reinstallOrSync : l.installNow) {
                    feedbackMessage = vm.installFinderQuickActions()
                }
                .controlSize(.small)
                .boltGlassProminentButton()

                if vm.quickActionsInstalled {
                    Button(l.disableNow) {
                        vm.uninstallFinderQuickActions()
                        feedbackMessage = l.finderDisabledSummary
                    }
                    .controlSize(.small)
                    .boltGlassButton()
                }
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func appearanceTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.languageLabel, icon: "globe", glassEnabled: glassEnabled) {
            HStack {
                Text(l.languageLabel)
                Spacer()
                Picker("", selection: $vm.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativePickerTitle).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }

        BoltGlassSectionCard(l.appearanceTitle, icon: "sparkles", glassEnabled: glassEnabled, tint: .cyan.opacity(0.05)) {
            HStack {
                Text(l.themeLabel)
                Spacer()
                Picker("", selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(l)).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            if vm.supportsLiquidGlass {
                Divider().opacity(glassEnabled ? 0.28 : 0.6)
                Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
                if vm.isWindowTranslucent {
                    HStack(spacing: 12) {
                        Text("\(l.opacityLabel): \(Int((vm.windowBackgroundOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 145, alignment: .leading)
                        Slider(value: $vm.windowBackgroundOpacity, in: 0.25...1.0, step: 0.05)
                    }
                }
            }
        }

        BoltGlassSectionCard(l.visibleSectionsTitle, icon: "rectangle.3.group", glassEnabled: glassEnabled) {
            Toggle(l.toggleFinderBanner, isOn: $vm.showFinderBanner)
            Divider().opacity(glassEnabled ? 0.28 : 0.6)
            Toggle(l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
            Divider().opacity(glassEnabled ? 0.28 : 0.6)
            Toggle(l.toggleRecentsCard, isOn: $vm.showRecentArchives)
            Divider().opacity(glassEnabled ? 0.28 : 0.6)
            Toggle(l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
            Divider().opacity(glassEnabled ? 0.28 : 0.6)
            Toggle(l.toggleStatusBar, isOn: $vm.showStatusBar)
        }
    }

    @ViewBuilder
    private func codecsTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.settingsTabCodecs, icon: "cpu", glassEnabled: glassEnabled, tint: .cyan.opacity(0.04)) {
            let engines = CompressionCodec.engineVersions()
            ForEach(Array(engines.enumerated()), id: \.element.id) { idx, info in
                if idx > 0 {
                    Divider().opacity(glassEnabled ? 0.28 : 0.6)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name).font(.headline)
                        Text(info.license)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v\(info.version)")
                        .font(.callout.monospaced())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .boltLayeredSurface(
                            glassEnabled: glassEnabled,
                            tone: .regular,
                            tint: .cyan.opacity(0.14),
                            in: Capsule()
                        )
                }
            }
        }
    }
}


struct AboutView: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.0"
        VStack(spacing: 14) {
            BoltLogoBadge(size: 72)

            VStack(spacing: 4) {
                Text("BoltZip")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(BoltPlatformCapabilities.runtimeVersionSummary(appVersion: appVersion))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(l.slogan)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            Text(l.aboutDesc)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                Text(l.openSourceEnginesLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(l.copyrightLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)

            BoltGlassContainer(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "https://github.com/hwang8859-1/BoltZip") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(l.openGitHub, systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .boltGlassProminentButton()

                    Button {
                        vm.openShowcaseWebsite()
                    } label: {
                        Label(l.showcasePage, systemImage: "safari")
                    }
                    .boltGlassButton()

                    Button(l.close) {
                        NSApp.keyWindow?.performClose(nil)
                        dismiss()
                    }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background {
            if glassEnabled {
                ZStack {
                    BoltAmbientBackdrop().opacity(0.5)
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(max(0.0, vm.windowBackgroundOpacity - 0.35))
                        .ignoresSafeArea()
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
        }
        .background(
            BoltAuxiliaryWindowStyleBridge(
                isTranslucent: glassEnabled,
                backgroundOpacity: vm.windowBackgroundOpacity
            )
        )
        .boltWindowContainerBackground(
            glassEnabled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .boltWindowToolbarBackgroundVisibility(glassEnabled ? .hidden : .automatic)
        .preferredColorScheme(vm.appTheme.colorScheme)
    }
}
