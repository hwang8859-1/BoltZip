import AppKit
import BoltZipCore
import SwiftUI

struct CreateArchiveSheet: View {
    @Bindable var vm: WorkspaceViewModel
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
        case none = "不分卷"
        case mb10 = "10 MB (聊天软件友好)"
        case mb100 = "100 MB"
        case mb700 = "700 MB (CD)"
        case gb4 = "4 GB (FAT32)"
        case custom = "自定义 (MB)"

        var id: String { rawValue }
    }

    init(vm: WorkspaceViewModel, initialInputs: [URL]) {
        self.vm = vm
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

        VStack(spacing: 12) {
            // Header Glass Card
            BoltGlassContainer(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.cyan.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.cyan.opacity(0.30), lineWidth: 0.75)
                            )
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.createArchiveTitle)
                            .font(.headline)
                        Text(l.createArchiveSub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(format.fileExtension.uppercased())
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .boltLayeredSurface(
                            glassEnabled: glassEnabled,
                            tone: .regular,
                            tint: .cyan.opacity(0.18),
                            in: Capsule()
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: .cyan.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }

            // Layered Glass Form Sections (strictly clipped between header & footer)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                        BoltGlassSectionCard(l.outputTargetSection, icon: "folder.fill", glassEnabled: glassEnabled) {
                            HStack(spacing: 10) {
                                Text(l.archiveNameField)
                                    .frame(width: 148, alignment: .leading)
                                TextField(l.archiveNameField, text: $archiveName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Divider().opacity(glassEnabled ? 0.28 : 0.6)

                            HStack(spacing: 10) {
                                Text(l.saveLocationLabel)
                                Spacer(minLength: 8)
                                Text(destinationDir.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(l.change) { chooseDestinationDir() }
                                    .controlSize(.small)
                                    .boltGlassButton()
                            }

                            Divider().opacity(glassEnabled ? 0.28 : 0.6)

                            HStack(spacing: 10) {
                                Text("\(l.inputItemsLabel) (\(inputs.count))")
                                Spacer(minLength: 8)
                                Text(inputs.map(\.lastPathComponent).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(l.add) { addMoreInputs() }
                                    .controlSize(.small)
                                    .boltGlassButton()
                            }
                        }

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
                                .frame(maxWidth: 260)
                                .onChange(of: format) { _, newFmt in
                                    if !newFmt.supportedAlgorithms.contains(algorithm) {
                                        algorithm = newFmt.defaultAlgorithm
                                    }
                                    level = preset.level(for: algorithm)
                                    if !newFmt.supportsEncryption { encryption = .none }
                                    if !newFmt.supportsSplitVolumes { splitPreset = .none }
                                }
                            }

                            Divider().opacity(glassEnabled ? 0.28 : 0.6)

                            HStack {
                                Text(l.compressionAlgoLabel)
                                Spacer()
                                Picker("", selection: $algorithm) {
                                    ForEach(format.supportedAlgorithms) { algo in
                                        Text("\(algo.displayName) — \(algo.openSourceLicenseNote)").tag(algo)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 260)
                                .onChange(of: algorithm) { _, newAlgo in
                                    level = preset.level(for: newAlgo)
                                }
                            }

                            if algorithm != .store {
                                Divider().opacity(glassEnabled ? 0.28 : 0.6)

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
                                    .frame(maxWidth: 260)
                                    .onChange(of: preset) { _, newPreset in
                                        level = newPreset.level(for: algorithm)
                                    }
                                }

                                let range = algorithm.levelRange
                                if range.lowerBound < range.upperBound {
                                    HStack(spacing: 12) {
                                        Text("\(l.fineLevelLabel): \(level)")
                                            .monospacedDigit()
                                            .frame(width: 110, alignment: .leading)
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

                        if format.supportsEncryption {
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
                                    .frame(maxWidth: 260)
                                }

                                if encryption != .none {
                                    Divider().opacity(glassEnabled ? 0.28 : 0.6)
                                    HStack(spacing: 10) {
                                        Text(l.passwordPlaceholder)
                                            .frame(width: 110, alignment: .leading)
                                        SecureField(l.passwordPlaceholder, text: $password)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    HStack(spacing: 10) {
                                        Text(l.confirmPasswordField)
                                            .frame(width: 110, alignment: .leading)
                                        SecureField(l.confirmPasswordField, text: $confirmPassword)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                                        Text(l.passwordMismatch)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }

                        BoltGlassSectionCard(l.advancedOptionsSection, icon: "slider.horizontal.3", glassEnabled: glassEnabled) {
                            if format.supportsSplitVolumes {
                                HStack {
                                    Text(l.splitVolumeLabel)
                                    Spacer()
                                    Picker("", selection: $splitPreset) {
                                        ForEach(SplitPreset.allCases) { sp in
                                            Text(sp.rawValue).tag(sp)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                                if splitPreset == .custom {
                                    HStack(spacing: 10) {
                                        Text(l.customSplitMBField)
                                            .frame(width: 140, alignment: .leading)
                                        TextField(l.customSplitMBField, text: $customSplitMB)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                                Divider().opacity(glassEnabled ? 0.28 : 0.6)
                            }

                            Toggle(l.stripMacJunkToggle, isOn: $excludeMacJunk)

                            if format == .zip {
                                Divider().opacity(glassEnabled ? 0.28 : 0.6)
                                HStack {
                                    Text(l.filenameEncoding)
                                    Spacer()
                                    Picker("", selection: $encoding) {
                                        ForEach([FilenameEncodingOption.utf8, .gb18030, .cp437]) { enc in
                                            Text(l.encodingTitle(enc)).tag(enc)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 260)
                                }
                            }
                        }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Footer Glass Card
            BoltGlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.zipper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(l.willGeneratePrefix)\(resolvedOutputURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(l.cancel) { dismiss() }
                        .boltGlassButton()
                        .keyboardShortcut(.cancelAction)
                    Button(l.startCompress) { startCompress() }
                        .boltGlassProminentButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValidInput)
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
        .frame(width: 560, height: 610)
        .boltGlassSheetStyle(enabled: glassEnabled, colorScheme: vm.appTheme.colorScheme)
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
        dismiss()
        vm.createArchive(inputs: inputs, outputURL: out, options: opts)
    }
}
