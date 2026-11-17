import AppKit
import BoltZipCore
import SwiftUI

struct ExtractOptionsSheet: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case smart = "智能解压 (推荐：单目录不套娃)"
        case here = "解压到目标目录 (不建子目录)"
        case subfolder = "始终创建同名子目录"
        case selected = "仅解压选中的条目"

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
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                Text("解压选项")
                    .font(.headline)
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                Section("目标文件夹") {
                    HStack {
                        Text(destinationURL.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("浏览...") { chooseDest() }
                            .buttonStyle(.glass)
                    }
                }

                Section("解压策略") {
                    Picker("解压模式", selection: $choice) {
                        ForEach(Choice.allCases) { c in
                            if c != .selected || !selectedIDs.isEmpty {
                                Text(c.rawValue).tag(c)
                            }
                        }
                    }

                    Picker("遇到重名文件", selection: $overwritePolicy) {
                        ForEach(OverwritePolicy.allCases) { pol in
                            Text(pol.displayName).tag(pol)
                        }
                    }

                    Toggle("过滤 __MACOSX / .DS_Store 隐藏文件", isOn: $stripMacJunk)
                }

                if vm.listing?.hasEncryptedEntries == true {
                    Section("解密密码") {
                        SecureField("输入压缩包密码", text: $password)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            GlassEffectContainer(spacing: 10) {
                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("开始解压") {
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
            .padding(16)
        }
        .frame(width: 500, height: 430)
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
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("该压缩包已加密")
                .font(.headline)
            Text("请输入解密密码以继续操作（支持 WinZip AE-2 AES-256 与 ZipCrypto）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("输入密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            GlassEffectContainer(spacing: 10) {
                HStack {
                    Button("取消") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("确认") {
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
        .padding(24)
        .frame(width: 360)
    }
}

struct EntryPropertiesSheet: View {
    let entry: ArchiveEntry
    @Environment(\.dismiss) private var dismiss

    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text.magnifyingglass")
                    .font(.title)
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
            .padding(18)

            Divider()

            VStack(spacing: 10) {
                PropRow(title: "类型", value: entry.isDirectory ? "文件夹" : "文件")
                PropRow(title: "原始大小", value: "\(DropHelper.formatBytes(entry.uncompressedSize)) (\(entry.uncompressedSize) B)")
                PropRow(title: "压缩后大小", value: entry.isDirectory ? "—" : "\(DropHelper.formatBytes(entry.compressedSize)) (\(entry.compressedSize) B)")
                PropRow(title: "空间节省", value: entry.isDirectory ? "—" : String(format: "%.2f%%", entry.compressionRatioPercent))
                PropRow(title: "压缩算法", value: entry.compressionMethodName)
                PropRow(title: "加密状态", value: entry.isEncrypted ? entry.encryptionLabel : "未加密")
                PropRow(title: "CRC32", value: entry.crc32 == 0 ? "0x00000000 (或 AE-2 HMAC)" : String(format: "0x%08X", entry.crc32))
                PropRow(title: "POSIX 权限", value: String(format: "0o%03o", entry.permissions))
                PropRow(title: "修改时间", value: Self.formatter.string(from: entry.modifiedDate))
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(16)

            Spacer()

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 470, height: 410)
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
    let report: IntegrityReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(report.isHealthy ? .green : .red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("完整性校验报告 · \(report.archiveName)")
                        .font(.headline)
                    Text("通过 \(report.passedCount)/\(report.totalEntries) · 失败 \(report.failedCount) · 缺少密码 \(report.skippedEncryptedCount) · 耗时 \(String(format: "%.2fs", report.elapsedSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

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
                Button("关闭") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 600, height: 420)
    }
}

struct BenchmarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [BenchmarkEntryResult] = []
    @State private var isRunning = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开源算法本机性能跑分")
                        .font(.headline)
                    Text("基于 2 MB 混合结构化样本实时压测 5 大开源压缩内核")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isRunning ? "测试中..." : "重新跑分") {
                    runBench()
                }
                .buttonStyle(.glass)
                .disabled(isRunning)
            }
            .padding(18)

            Divider()

            if isRunning {
                ProgressView("正在运行本机基准测试...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg {
                Text(errorMsg).foregroundStyle(.red).padding()
            } else {
                Table(results) {
                    TableColumn("开源算法") { r in
                        Text("\(r.algorithm.shortName) (lvl \(r.level))").fontWeight(.medium)
                    }
                    TableColumn("压缩后体积") { r in
                        Text(DropHelper.formatBytes(UInt64(r.compressedBytes))).monospacedDigit()
                    }
                    TableColumn("空间节省") { r in
                        Text(String(format: "%.1f%%", r.ratioPercent)).foregroundStyle(.green).monospacedDigit()
                    }
                    TableColumn("压缩速度") { r in
                        Text(String(format: "%.1f MB/s", r.compressMBps)).monospacedDigit()
                    }
                    TableColumn("解压速度") { r in
                        Text(String(format: "%.1f MB/s", r.decompressMBps)).monospacedDigit()
                    }
                }
            }

            Divider()

            HStack {
                Text("说明：结果均为当前 Mac 硬件实际测量值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 620, height: 380)
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
    let title: String
    let placeholder: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(title: String, initialValue: String = "", placeholder: String, confirmLabel: String, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        self._text = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            GlassEffectContainer(spacing: 10) {
                HStack {
                    Button("取消") { dismiss() }
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
        .padding(22)
    }
}

struct SettingsView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var feedbackMessage: String?

    var body: some View {
        TabView {
            Form {
                Section("跨平台与打包默认项") {
                    Toggle("创建或解压时自动过滤 Mac 隐藏垃圾文件 (.DS_Store / __MACOSX / ._*)", isOn: Binding(
                        get: { vm.defaultStripMacJunk },
                        set: { vm.updateDefaultStripMacJunk($0) }
                    ))
                    Picker("默认文件名编码识别", selection: Binding(
                        get: { vm.encodingOption },
                        set: { vm.encodingOption = $0 }
                    )) {
                        ForEach(FilenameEncodingOption.allCases) { enc in
                            Text(enc.displayName).tag(enc)
                        }
                    }
                }

                Section("macOS 访达一级右键菜单 (Bolt >)") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.quickActionsInstalled ? "已启用访达一级右键「Bolt >」目录" : "尚未启用访达一级右键「Bolt >」目录")
                                .font(.subheadline.weight(.medium))
                            Text("直接出现在访达右键菜单顶层「Bolt >」：智能解压、解压到文件夹、压缩 ZIP/TAR.ZST/7z、加密打包")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(vm.quickActionsInstalled ? "重新安装" : "一键安装") {
                            feedbackMessage = vm.installFinderQuickActions()
                        }
                        .buttonStyle(.glassProminent)

                        if vm.quickActionsInstalled {
                            Button("卸载") {
                                vm.uninstallFinderQuickActions()
                                feedbackMessage = "已从 ~/Library/Services 移除"
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
                Label("通用与访达集成", systemImage: "gearshape")
            }

            List(CompressionCodec.engineVersions()) { info in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name).font(.headline)
                        Text("开源协议：\(info.license)")
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
                Label("开源算法内核", systemImage: "cpu")
            }
        }
        .frame(width: 580, height: 360)
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }
}
