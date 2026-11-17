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
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                Text(l.extractOptionsTitle)
                    .font(.headline)
                Spacer()
            }
            .padding(14)

            Divider()

            Form {
                Section(l.destFolderLabel) {
                    HStack {
                        Text(destinationURL.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(l.browse) { chooseDest() }
                            .buttonStyle(.glass)
                    }
                }

                Section(l.extractModeLabel) {
                    Picker(l.extractModeLabel, selection: $choice) {
                        Text(l.ctxSmartExtractAll).tag(Choice.smart)
                        Text(l.ctxExtractSelHere).tag(Choice.here)
                        Text(l.ctxExtractAllSubfolder).tag(Choice.subfolder)
                        if !selectedIDs.isEmpty {
                            Text(l.ctxExtractSelTo).tag(Choice.selected)
                        }
                    }

                    Picker(l.overwriteLabel, selection: $overwritePolicy) {
                        ForEach(OverwritePolicy.allCases) { pol in
                            Text(pol.displayName).tag(pol)
                        }
                    }

                    Toggle(l.stripMacJunkToggle, isOn: $stripMacJunk)
                }

                if vm.listing?.hasEncryptedEntries == true {
                    Section(l.decryptPasswordSection) {
                        SecureField(l.passwordPlaceholder, text: $password)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            GlassEffectContainer(spacing: 10) {
                HStack {
                    Spacer()
                    Button(l.cancel) { dismiss() }
                        .buttonStyle(.glass)
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
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 480, height: 390)
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
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(l.passwordPromptTitle)
                .font(.headline)
            Text(l.passwordPromptDesc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField(l.passwordPlaceholder, text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            GlassEffectContainer(spacing: 10) {
                HStack {
                    Button(l.cancel) { dismiss() }
                        .buttonStyle(.glass)
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
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
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
        VStack(spacing: 0) {
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
            .padding(14)

            Divider()

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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(14)

            Spacer()

            HStack {
                Spacer()
                Button(l.close) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 14)
        }
        .frame(width: 440, height: 360)
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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
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
            .padding(14)

            Divider()

            List(report.results) { item in
                HStack {
                    Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(item.status == .passed ? .green : (item.status == .missingPassword ? .orange : .red))
                    Text(item.path)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(l.close) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 390)
    }
}

struct BenchmarkSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var results: [BenchmarkEntryResult] = []
    @State private var isRunning = false
    @State private var errorMsg: String?

    var body: some View {
        let l = vm.l10n
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title3)
                    .foregroundStyle(.cyan)
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
                .buttonStyle(.glass)
                .disabled(isRunning)
            }
            .padding(14)

            Divider()

            if isRunning {
                ProgressView(l.runningBench)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg {
                Text(errorMsg).foregroundStyle(.red).padding()
            } else {
                Table(results) {
                    TableColumn(l.colMethod) { r in
                        Text("\(r.algorithm.shortName) (lvl \(r.level))").fontWeight(.medium)
                    }
                    TableColumn(l.colPackedSize) { r in
                        Text(DropHelper.formatBytes(UInt64(r.compressedBytes))).monospacedDigit()
                    }
                    TableColumn(l.colRatio) { r in
                        Text(String(format: "%.1f%%", r.ratioPercent)).foregroundStyle(.green).monospacedDigit()
                    }
                    TableColumn(l.compressSpeedCol) { r in
                        Text(String(format: "%.1f MB/s", r.compressMBps)).monospacedDigit()
                    }
                    TableColumn(l.decompressSpeedCol) { r in
                        Text(String(format: "%.1f MB/s", r.decompressMBps)).monospacedDigit()
                    }
                }
            }

            Divider()

            HStack {
                Text(l.benchHardwareNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l.done) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 580, height: 350)
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
        VStack(spacing: 12) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            GlassEffectContainer(spacing: 10) {
                HStack {
                    Button(l.cancel) { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button(confirmLabel) {
                        onConfirm(text)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(18)
    }
}

struct SettingsView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var feedbackMessage: String?

    var body: some View {
        let l = vm.l10n
        TabView {
            Form {
                Section(l.settingsTabGeneral) {
                    Toggle(l.stripMacJunkToggle, isOn: Binding(
                        get: { vm.defaultStripMacJunk },
                        set: { vm.updateDefaultStripMacJunk($0) }
                    ))
                    Picker(l.defaultEncodingLabel, selection: Binding(
                        get: { vm.encodingOption },
                        set: { vm.encodingOption = $0 }
                    )) {
                        ForEach(FilenameEncodingOption.allCases) { enc in
                            Text(l.encodingTitle(enc)).tag(enc)
                        }
                    }
                }

                Section(l.finderIntegrationSection) {
                    HStack {
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
                        .buttonStyle(.glass)

                        Button(vm.quickActionsInstalled ? l.reinstallOrSync : l.installNow) {
                            feedbackMessage = vm.installFinderQuickActions()
                        }
                        .buttonStyle(.glassProminent)

                        if vm.quickActionsInstalled {
                            Button(l.disableNow) {
                                vm.uninstallFinderQuickActions()
                                feedbackMessage = l.finderDisabledSummary
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    if let feedbackMessage {
                        Text(feedbackMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(l.settingsTabGeneral, systemImage: "gearshape")
            }

            Form {
                Section(l.languageLabel) {
                    Picker(l.languageLabel, selection: $vm.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.nativePickerTitle).tag(lang)
                        }
                    }
                }

                Section(l.appearanceTitle) {
                    Picker(l.themeLabel, selection: $vm.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title(l)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
                    if vm.isWindowTranslucent {
                        HStack {
                            Text("\(l.opacityLabel): \(Int((vm.windowBackgroundOpacity * 100).rounded()))%")
                            Slider(value: $vm.windowBackgroundOpacity, in: 0.25...1.0, step: 0.05)
                        }
                    }
                }

                Section(l.visibleSectionsTitle) {
                    Toggle(l.toggleFinderBanner, isOn: $vm.showFinderBanner)
                    Toggle(l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
                    Toggle(l.toggleRecentsCard, isOn: $vm.showRecentArchives)
                    Toggle(l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
                    Toggle(l.toggleStatusBar, isOn: $vm.showStatusBar)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(l.settingsTabAppearance, systemImage: "slider.horizontal.3")
            }

            List(CompressionCodec.engineVersions()) { info in
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(.cyan.opacity(0.14)), in: Capsule())
                }
            }
            .tabItem {
                Label(l.settingsTabCodecs, systemImage: "cpu")
            }
        }
        .frame(width: 600, height: 380)
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }
}


struct AboutView: View {
    @Bindable var vm: WorkspaceViewModel

    var body: some View {
        let l = vm.l10n
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        VStack(spacing: 14) {
            BoltLogoBadge(size: 72)

            VStack(spacing: 4) {
                Text("BoltZip")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("v\(appVersion) · macOS 27.3 · arm64")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(l.slogan)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.cyan.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "https://github.com/hwang8859-1/BoltZip") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(l.openGitHub, systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        vm.openShowcaseWebsite()
                    } label: {
                        Label(l.showcasePage, systemImage: "safari")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(BoltAmbientBackdrop().opacity(0.5))
        .containerBackground(.ultraThinMaterial, for: .window)
        .preferredColorScheme(vm.appTheme.colorScheme)
    }
}
