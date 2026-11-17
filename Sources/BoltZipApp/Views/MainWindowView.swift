import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isTableDropTargeted = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        Group {
            if let listing = vm.listing {
                archiveExplorer(listing: listing)
            } else {
                WelcomeDropZoneView(vm: vm)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .containerBackground(.ultraThinMaterial, for: .window)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if vm.listing != nil {
                    Button {
                        vm.closeArchive()
                    } label: {
                        Label("返回首页", systemImage: "house")
                    }
                    .help("关闭当前压缩包并返回欢迎页")

                    Button {
                        vm.navigateUp()
                    } label: {
                        Label("上一级", systemImage: "chevron.up")
                    }
                    .disabled(!vm.canNavigateUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.startNewArchivePanel()
                } label: {
                    Label("新建压缩", systemImage: "plus.rectangle.on.folder")
                }

                Button {
                    vm.openArchivePanel()
                } label: {
                    Label("打开", systemImage: "folder")
                }

                if let listing = vm.listing {
                    Divider()

                    Button {
                        vm.triggerSmartExtractNow()
                    } label: {
                        Label("智能解压", systemImage: "arrow.down.doc.fill")
                    }
                    .help("单目录直接解压，多目录自动新建同名文件夹")

                    Button {
                        let mode: ExtractMode = vm.selectedEntryIDs.isEmpty ? .smart : .selected(vm.selectedEntryIDs)
                        vm.activeSheet = .extractOptions(mode)
                    } label: {
                        Label("解压到...", systemImage: "square.and.arrow.down.on.square")
                    }

                    if listing.format.supportsInPlaceEditing {
                        Button {
                            vm.addItemsToCurrentZipPanel()
                        } label: {
                            Label("包内添加", systemImage: "doc.badge.plus")
                        }

                        Button {
                            vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
                        } label: {
                            Label("新建目录", systemImage: "folder.badge.plus")
                        }

                        Button {
                            vm.deleteSelectedEntries()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(vm.selectedEntryIDs.isEmpty)
                    }

                    Button {
                        vm.testIntegrity()
                    } label: {
                        Label("校验", systemImage: "checkmark.shield")
                    }
                    .help("验证所有条目的 CRC32 / HMAC-SHA1 完整性")
                }
            }
        }
        .overlay {
            if vm.isBusy {
                ZStack {
                    Color.black.opacity(0.20).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(value: vm.progress?.fractionCompleted ?? 0.3)
                            .progressViewStyle(.linear)
                            .frame(width: 280)
                        Text(vm.progress?.currentItem ?? vm.statusMessage)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(24)
                    .glassEffect(.regular.tint(.cyan.opacity(0.08)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(radius: 20)
                }
            }
        }
        .sheet(item: $vm.activeSheet) { sheet in
            switch sheet {
            case .createArchive(let urls):
                CreateArchiveSheet(vm: vm, initialInputs: urls)
            case .extractOptions(let mode):
                ExtractOptionsSheet(vm: vm, initialMode: mode)
            case .integrityReport(let report):
                IntegrityReportSheet(report: report)
            case .benchmark:
                BenchmarkSheet()
            case .passwordPrompt(let purpose):
                PasswordPromptSheet(vm: vm, purpose: purpose)
            case .createFolder(let parentFolder):
                SimpleNamePromptSheet(
                    title: "在归档内新建文件夹",
                    placeholder: "例如：docs",
                    confirmLabel: "创建"
                ) { name in
                    vm.createFolderInZip(parentFolder: parentFolder, name: name)
                }
            case .renamePath(let oldPath, let currentName):
                SimpleNamePromptSheet(
                    title: "重命名归档条目",
                    initialValue: currentName,
                    placeholder: "新名称",
                    confirmLabel: "重命名"
                ) { newName in
                    vm.renamePath(oldPath, to: newName)
                }
            case .entryProperties(let entry):
                EntryPropertiesSheet(entry: entry)
            }
        }
        .alert("BoltZip 提示", isPresented: Binding(
            get: { vm.alertMessage != nil },
            set: { if !$0 { vm.alertMessage = nil } }
        )) {
            Button("确定", role: .cancel) { vm.alertMessage = nil }
        } message: {
            Text(vm.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func archiveExplorer(listing: ArchiveListing) -> some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 10) {
                List(selection: Binding(
                    get: { vm.currentFolder },
                    set: { newValue in
                        if let newValue {
                            vm.currentFolder = newValue
                            vm.selectedEntryIDs.removeAll()
                        }
                    }
                )) {
                    Section("目录结构") {
                        FolderTreeRow(
                            node: vm.folderTree,
                            vm: vm,
                            canEditZip: listing.format.supportsInPlaceEditing
                        )
                    }
                }
                .listStyle(.sidebar)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(listing.format.displayName)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .glassEffect(.regular.tint(.cyan.opacity(0.18)), in: Capsule())
                        Spacer()
                        if listing.hasEncryptedEntries {
                            Label("已加密", systemImage: "lock.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    InfoMetricRow(label: "条目总数", value: "\(listing.entries.count) 项")
                    InfoMetricRow(label: "原始体积", value: DropHelper.formatBytes(listing.totalUncompressedBytes))
                    InfoMetricRow(label: "压缩后", value: DropHelper.formatBytes(listing.totalCompressedBytes))
                    InfoMetricRow(label: "节省空间", value: String(format: "%.1f%%", listing.overallCompressionRatioPercent))

                    Divider()

                    HStack {
                        Text("文件名编码")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.encodingOption },
                            set: { vm.reloadWithEncoding($0) }
                        )) {
                            ForEach(FilenameEncodingOption.allCases) { enc in
                                Text(enc.displayName).tag(enc)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .glassEffect(.regular.tint(.cyan.opacity(0.06)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding([.horizontal, .bottom], 10)
            }
            .navigationSplitViewColumnWidth(min: 235, ideal: 265, max: 325)
        } detail: {
            ZStack {
                BoltAmbientBackdrop().opacity(0.55)

                VStack(spacing: 10) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(Array(vm.breadcrumbComponents.enumerated()), id: \.offset) { idx, crumb in
                                        if idx > 0 {
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Button {
                                            vm.currentFolder = crumb.path
                                            vm.selectedEntryIDs.removeAll()
                                        } label: {
                                            HStack(spacing: 4) {
                                                if idx == 0 { Image(systemName: "archivebox.fill") }
                                                Text(crumb.title)
                                            }
                                            .font(.callout.weight(crumb.path == vm.currentFolder ? .semibold : .regular))
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        .glassEffect(
                                            crumb.path == vm.currentFolder
                                                ? .regular.tint(.cyan.opacity(0.18)).interactive()
                                                : .clear.interactive(),
                                            in: Capsule()
                                        )
                                    }
                                }
                            }

                            Spacer()

                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("搜索归档内文件...", text: $vm.searchText)
                                    .textFieldStyle(.plain)
                                    .frame(width: 185)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Table(vm.visibleEntries, selection: $vm.selectedEntryIDs) {
                        TableColumn("名称") { entry in
                            HStack(spacing: 8) {
                                Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile(entry.name))
                                    .foregroundStyle(entry.isDirectory ? Color.cyan : Color.secondary)
                                Text(entry.name)
                                    .lineLimit(1)
                                if entry.isEncrypted {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .width(min: 220, ideal: 300)

                        TableColumn("原始大小") { entry in
                            Text(entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 80, ideal: 95)

                        TableColumn("压缩后") { entry in
                            Text(entry.isDirectory || entry.compressedSize == 0 ? "—" : DropHelper.formatBytes(entry.compressedSize))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 80, ideal: 95)

                        TableColumn("压缩率") { entry in
                            if entry.isDirectory || entry.uncompressedSize == 0 {
                                Text("—").foregroundStyle(.tertiary)
                            } else {
                                Text(String(format: "%.1f%%", entry.compressionRatioPercent))
                                    .monospacedDigit()
                                    .foregroundStyle(.green)
                            }
                        }
                        .width(min: 65, ideal: 75)

                        TableColumn("算法 / 加密") { entry in
                            let label = entry.isEncrypted ? "\(entry.compressionMethodName) · \(entry.encryptionLabel)" : entry.compressionMethodName
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 95, ideal: 130)

                        TableColumn("修改时间") { entry in
                            Text(Self.dateFormatter.string(from: entry.modifiedDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 110, ideal: 130)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
                    .contextMenu(forSelectionType: String.self) { ids in
                        if ids.isEmpty {
                            emptySpaceContextMenu(listing: listing)
                        } else {
                            rowContextMenu(ids: ids, listing: listing)
                        }
                    } primaryAction: { ids in
                        guard let firstID = ids.first,
                              let entry = vm.visibleEntries.first(where: { $0.id == firstID }) else { return }
                        vm.previewOrOpenEntry(entry)
                    }
                    .overlay {
                        if isTableDropTargeted && listing.format.supportsInPlaceEditing {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    Label("松手即可直接添加到「\(vm.currentFolder.isEmpty ? "根目录" : vm.currentFolder)」", systemImage: "plus.circle.fill")
                                        .font(.headline)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .glassEffect(.regular.tint(.cyan.opacity(0.22)).interactive(), in: Capsule())
                                }
                                .padding(.horizontal, 12)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isTableDropTargeted) { providers in
                        guard listing.format.supportsInPlaceEditing else { return false }
                        return DropHelper.extractFileURLs(from: providers) { urls in
                            vm.addItemsToCurrentZip(urls)
                        }
                    }

                    HStack(spacing: 14) {
                        Text(vm.statusMessage)
                            .lineLimit(1)
                        Spacer()
                        if !vm.selectedEntryIDs.isEmpty {
                            let selBytes = vm.selectedEntries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
                            Text("已选 \(vm.selectedEntryIDs.count) 项 (\(DropHelper.formatBytes(selBytes)))")
                                .foregroundStyle(.cyan)
                        }
                        if listing.format.supportsInPlaceEditing {
                            Text("右键支持全部高频操作 · 支持直接拖入文件")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding([.horizontal, .bottom], 12)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(ids: Set<String>, listing: ArchiveListing) -> some View {
        let picked = vm.visibleEntries.filter { ids.contains($0.id) }
        if let first = picked.first, picked.count == 1 {
            Button(first.isDirectory ? "打开文件夹" : "Quick Look 快速预览") {
                vm.previewOrOpenEntry(first)
            }
            Button("查看属性详情...") {
                vm.activeSheet = .entryProperties(first)
            }
            Divider()
            Button("复制文件名 (\(first.name))") {
                vm.copyToPasteboard(first.name, label: "文件名")
            }
            Button("复制归档内路径") {
                vm.copyToPasteboard(first.path, label: "内部路径")
            }
            Divider()
        }

        Button("智能解压选中项到所在目录") {
            vm.quickExtract(mode: .selected(ids))
        }
        Button("解压选中项到指定位置...") {
            vm.activeSheet = .extractOptions(.selected(ids))
        }
        Button("单独导出选中项为新 ZIP...") {
            vm.exportSelectedAsNewZip(entryIDs: ids)
        }

        Divider()

        Button("校验归档完整性") {
            vm.testIntegrity()
        }

        if listing.format.supportsInPlaceEditing {
            Divider()
            Button("在此目录添加文件/文件夹...") {
                vm.addItemsToCurrentZipPanel()
            }
            Button("在此目录新建文件夹...") {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
            if let single = picked.first, picked.count == 1 {
                Button("重命名...") {
                    vm.activeSheet = .renamePath(oldPath: single.path, currentName: single.name)
                }
            }
            Button("从归档中删除", role: .destructive) {
                vm.selectedEntryIDs = ids
                vm.deleteSelectedEntries()
            }
        }
    }

    @ViewBuilder
    private func emptySpaceContextMenu(listing: ArchiveListing) -> some View {
        Button("智能解压全部") {
            vm.quickExtract(mode: .smart)
        }
        Button("全部解压到同名文件夹") {
            vm.quickExtract(mode: .subfolder)
        }
        Button("解压全部到指定位置...") {
            vm.activeSheet = .extractOptions(.smart)
        }

        if listing.format.supportsInPlaceEditing {
            Divider()
            Button("添加文件到当前目录...") {
                vm.addItemsToCurrentZipPanel()
            }
            Button("在当前目录新建文件夹...") {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
        }

        Divider()

        Button("校验全部文件完整性") {
            vm.testIntegrity()
        }

        Menu("切换文件名编码") {
            ForEach(FilenameEncodingOption.allCases) { enc in
                Button {
                    vm.reloadWithEncoding(enc)
                } label: {
                    if vm.encodingOption == enc {
                        Label(enc.displayName, systemImage: "checkmark")
                    } else {
                        Text(enc.displayName)
                    }
                }
            }
        }

        Menu("排序方式") {
            ForEach(SortColumn.allCases) { col in
                Button {
                    if vm.sortColumn == col {
                        vm.sortAscending.toggle()
                    } else {
                        vm.sortColumn = col
                        vm.sortAscending = true
                    }
                } label: {
                    if vm.sortColumn == col {
                        Label("\(col.displayName) (\(vm.sortAscending ? "升序" : "降序"))", systemImage: "checkmark")
                    } else {
                        Text(col.displayName)
                    }
                }
            }
        }

        Divider()
        Button("在访达中定位压缩包") {
            vm.showInFinder(listing.archiveURL)
        }
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "c", "h", "js", "ts", "py", "json", "xml", "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "webp", "gif", "svg": return "photo"
        case "pdf": return "doc.richtext"
        case "md", "txt", "log": return "doc.text"
        case "zip", "7z", "tar", "gz", "zst", "xz": return "doc.zipper"
        case "mp4", "mov": return "film"
        case "mp3", "wav", "m4a": return "waveform"
        default: return "doc"
        }
    }
}

private struct FolderTreeRow: View {
    let node: FolderTreeNode
    @Bindable var vm: WorkspaceViewModel
    let canEditZip: Bool

    var body: some View {
        if node.children.isEmpty {
            rowLabel
        } else {
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(node.children) { child in
                    FolderTreeRow(node: child, vm: vm, canEditZip: canEditZip)
                }
            } label: {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        Label(node.name, systemImage: node.path.isEmpty ? "archivebox.fill" : "folder.fill")
            .tag(node.path)
            .contextMenu {
                Button("打开此目录") {
                    vm.currentFolder = node.path
                    vm.selectedEntryIDs.removeAll()
                }
                if !node.path.isEmpty {
                    Button("解压此目录到...") {
                        vm.activeSheet = .extractOptions(.selected([node.path]))
                    }
                    Button("复制目录路径") {
                        vm.copyToPasteboard(node.path, label: "目录路径")
                    }
                } else {
                    Button("智能解压全部") {
                        vm.quickExtract(mode: .smart)
                    }
                }

                if canEditZip {
                    Divider()
                    Button("在此目录添加文件...") {
                        vm.addItemsToCurrentZipPanel(targetFolder: node.path)
                    }
                    Button("在此目录新建子文件夹...") {
                        vm.activeSheet = .createFolder(parentFolder: node.path)
                    }
                    if !node.path.isEmpty {
                        Button("重命名此目录...") {
                            vm.activeSheet = .renamePath(oldPath: node.path, currentName: node.name)
                        }
                        Button("删除此目录", role: .destructive) {
                            vm.deletePaths([node.path])
                        }
                    }
                }
            }
    }
}

private struct InfoMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}
