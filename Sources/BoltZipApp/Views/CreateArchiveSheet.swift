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
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.l10n.createArchiveTitle)
                        .font(.headline)
                    Text(vm.l10n.createArchiveSub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                Section("输出目标") {
                    TextField("归档名称（不含扩展名）", text: $archiveName)
                    HStack {
                        Text("保存位置")
                        Spacer()
                        Text(destinationDir.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("更改...") {
                            chooseDestinationDir()
                        }
                        .buttonStyle(.glass)
                    }
                    HStack {
                        Text("待压缩项目 (\(inputs.count))")
                        Spacer()
                        Text(inputs.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("添加...") { addMoreInputs() }
                            .buttonStyle(.glass)
                    }
                }

                Section("格式与开源算法") {
                    Picker("归档格式", selection: $format) {
                        ForEach(ArchiveFormat.creatableFormats) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .onChange(of: format) { _, newFmt in
                        if !newFmt.supportedAlgorithms.contains(algorithm) {
                            algorithm = newFmt.defaultAlgorithm
                        }
                        level = preset.level(for: algorithm)
                        if !newFmt.supportsEncryption { encryption = .none }
                        if !newFmt.supportsSplitVolumes { splitPreset = .none }
                    }

                    Picker("压缩算法", selection: $algorithm) {
                        ForEach(format.supportedAlgorithms) { algo in
                            Text("\(algo.displayName) — \(algo.openSourceLicenseNote)").tag(algo)
                        }
                    }
                    .onChange(of: algorithm) { _, newAlgo in
                        level = preset.level(for: newAlgo)
                    }

                    if algorithm != .store {
                        Picker("压缩级别预设", selection: $preset) {
                            ForEach(CompressionPreset.allCases.filter { $0 != .store }) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: preset) { _, newPreset in
                            level = newPreset.level(for: algorithm)
                        }

                        let range = algorithm.levelRange
                        if range.lowerBound < range.upperBound {
                            HStack {
                                Text("算法精细级别：\(level)")
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
                    Section("加密保护 (WinZip 兼容)") {
                        Picker("加密方式", selection: $encryption) {
                            ForEach(EncryptionMethod.allCases) { enc in
                                Text(enc.displayName).tag(enc)
                            }
                        }
                        if encryption != .none {
                            SecureField("输入密码", text: $password)
                            SecureField("确认密码", text: $confirmPassword)
                            if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                                Text("两次输入的密码不一致")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("高级选项与跨平台兼容") {
                    if format.supportsSplitVolumes {
                        Picker("分卷大小", selection: $splitPreset) {
                            ForEach(SplitPreset.allCases) { sp in
                                Text(sp.rawValue).tag(sp)
                            }
                        }
                        if splitPreset == .custom {
                            TextField("单卷体积 (MB)", text: $customSplitMB)
                        }
                    }

                    Toggle("排除 Mac 系统隐藏文件 (.DS_Store / __MACOSX / ._*)", isOn: $excludeMacJunk)

                    if format == .zip {
                        Picker("文件名编码", selection: $encoding) {
                            ForEach([FilenameEncodingOption.utf8, .gb18030, .cp437]) { enc in
                                Text(enc.displayName).tag(enc)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("将生成：\(resolvedOutputURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(vm.l10n.cancel) { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(vm.l10n.startCompress) { startCompress() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidInput)
            }
            .padding(16)
        }
        .frame(width: 540, height: 550)
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
