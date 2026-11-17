import AppKit
import BoltZipCore
import Foundation
import Observation
import UniformTypeIdentifiers

struct FolderTreeNode: Identifiable, Hashable, Sendable {
    let id: String // "" for root, or "a/b/"
    let name: String
    let path: String
    var children: [FolderTreeNode]
    let fileCount: Int
}

enum SortColumn: String, CaseIterable, Identifiable {
    case name
    case uncompressedSize
    case compressedSize
    case ratio
    case method
    case modifiedDate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "名称"
        case .uncompressedSize: return "原始大小"
        case .compressedSize: return "压缩后大小"
        case .ratio: return "压缩率"
        case .method: return "算法 / 加密"
        case .modifiedDate: return "修改时间"
        }
    }
}

enum ActiveSheet: Identifiable {
    case createArchive([URL])
    case extractOptions(ExtractMode)
    case integrityReport(IntegrityReport)
    case benchmark
    case passwordPrompt(PasswordPurpose)
    case createFolder(parentFolder: String)
    case renamePath(oldPath: String, currentName: String)
    case entryProperties(ArchiveEntry)

    var id: String {
        switch self {
        case .createArchive: return "createArchive"
        case .extractOptions: return "extractOptions"
        case .integrityReport: return "integrityReport"
        case .benchmark: return "benchmark"
        case .passwordPrompt: return "passwordPrompt"
        case .createFolder(let parent): return "createFolder-\(parent)"
        case .renamePath(let oldPath, _): return "rename-\(oldPath)"
        case .entryProperties(let e): return "props-\(e.id)"
        }
    }
}

enum PasswordPurpose {
    case preview(ArchiveEntry)
    case extract(archiveURL: URL, options: ExtractOptions)
    case testIntegrity(archiveURL: URL)
}

@Observable
@MainActor
final class WorkspaceViewModel {
    var listing: ArchiveListing?
    var currentFolder: String = ""
    var selectedEntryIDs: Set<String> = []
    var searchText: String = ""
    var encodingOption: FilenameEncodingOption = .auto
    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true

    var isBusy: Bool = false
    var progress: OperationProgress?
    var statusMessage: String = "就绪 · 拖入压缩包浏览，或拖入文件立即打包"
    var alertMessage: String?
    var activeSheet: ActiveSheet?
    var savedPassword: String?

    var recentArchivePaths: [String] = []
    var defaultStripMacJunk: Bool = true
    var quickActionsInstalled: Bool = QuickActionInstaller.isExtensionEnabled()

    private let recentsKey = "BoltZip.RecentArchives"
    private let stripJunkKey = "BoltZip.ExcludeMacJunk"
    private let previewTempRoot: URL

    init() {
        self.previewTempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoltZipPreview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        self.recentArchivePaths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        if UserDefaults.standard.object(forKey: stripJunkKey) != nil {
            self.defaultStripMacJunk = UserDefaults.standard.bool(forKey: stripJunkKey)
        }
    }

    var recentArchiveURLs: [URL] {
        recentArchivePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func updateDefaultStripMacJunk(_ value: Bool) {
        defaultStripMacJunk = value
        UserDefaults.standard.set(value, forKey: stripJunkKey)
    }

    func refreshQuickActionsStatus() {
        quickActionsInstalled = QuickActionInstaller.isExtensionEnabled()
    }

    func installFinderQuickActions() -> String {
        do {
            let enabled = try QuickActionInstaller.installTopLevelFinderMenu()
            refreshQuickActionsStatus()
            if enabled {
                statusMessage = "已启用访达一级右键「Bolt >」菜单！"
                return "已将 Bolt 目录注册至访达一级右键菜单（已清理旧服务项）"
            } else {
                QuickActionInstaller.openSystemExtensionSettings()
                statusMessage = "请在系统设置中勾选 Bolt 访达扩展"
                return "已完成注册，请在打开的系统扩展设置中启用「Bolt」"
            }
        } catch {
            return "启用失败：\(error.localizedDescription)"
        }
    }

    func openFinderExtensionSettings() {
        QuickActionInstaller.openSystemExtensionSettings()
    }

    func uninstallFinderQuickActions() {
        QuickActionInstaller.disableTopLevelFinderMenu()
        try? QuickActionInstaller.uninstallLegacyWorkflows()
        refreshQuickActionsStatus()
        statusMessage = "已停用访达右键菜单"
    }

    // MARK: - Breadcrumbs & Folder Tree

    var breadcrumbComponents: [(title: String, path: String)] {
        var crumbs: [(String, String)] = [("根目录", "")]
        let parts = currentFolder.split(separator: "/").map(String.init)
        var acc = ""
        for p in parts {
            acc += p + "/"
            crumbs.append((p, acc))
        }
        return crumbs
    }

    var canNavigateUp: Bool { !currentFolder.isEmpty }

    func navigateUp() {
        guard canNavigateUp else { return }
        let trimmed = currentFolder.hasSuffix("/") ? String(currentFolder.dropLast()) : currentFolder
        if let idx = trimmed.lastIndex(of: "/") {
            currentFolder = String(trimmed[..<idx]) + "/"
        } else {
            currentFolder = ""
        }
        selectedEntryIDs.removeAll()
    }

    var folderTree: FolderTreeNode {
        guard let entries = listing?.entries else {
            return FolderTreeNode(id: "", name: "根目录", path: "", children: [], fileCount: 0)
        }

        var allFolders: Set<String> = [""]
        var directFileCount: [String: Int] = [:]

        for entry in entries {
            let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = clean.split(separator: "/").map(String.init)
            if entry.isDirectory {
                var acc = ""
                for p in parts {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
            } else {
                var acc = ""
                for p in parts.dropLast() {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
                directFileCount[acc, default: 0] += 1
            }
        }

        func buildNode(path: String, name: String) -> FolderTreeNode {
            let directChildren = allFolders
                .filter { candidate in
                    guard candidate != path, candidate.hasPrefix(path) else { return false }
                    let rem = String(candidate.dropFirst(path.count))
                    let parts = rem.split(separator: "/")
                    return parts.count == 1
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { childPath -> FolderTreeNode in
                    let trimmed = childPath.hasSuffix("/") ? String(childPath.dropLast()) : childPath
                    let childName = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
                    return buildNode(path: childPath, name: childName)
                }
            return FolderTreeNode(
                id: path,
                name: name,
                path: path,
                children: directChildren,
                fileCount: directFileCount[path, default: 0]
            )
        }

        return buildNode(path: "", name: listing?.archiveURL.lastPathComponent ?? "根目录")
    }

    var visibleEntries: [ArchiveEntry] {
        guard let entries = listing?.entries else { return [] }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [ArchiveEntry]

        if !query.isEmpty {
            items = entries.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }
        } else {
            let prefix = currentFolder
            var directByPath: [String: ArchiveEntry] = [:]

            for entry in entries where entry.path.hasPrefix(prefix) && entry.path != prefix {
                let remainder = String(entry.path.dropFirst(prefix.count))
                let parts = remainder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard let first = parts.first else { continue }
                if parts.count == 1 && !entry.isDirectory {
                    directByPath[entry.path] = entry
                } else {
                    let folderPath = prefix + first + "/"
                    if directByPath[folderPath] == nil {
                        directByPath[folderPath] = ArchiveEntry(
                            path: folderPath,
                            isDirectory: true,
                            uncompressedSize: 0,
                            compressedSize: 0,
                            compressionMethodName: "Folder",
                            crc32: 0,
                            modifiedDate: entry.modifiedDate,
                            permissions: 0o755
                        )
                    }
                }
            }
            items = Array(directByPath.values)
        }

        items.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            let cmp: Bool
            switch sortColumn {
            case .name:
                cmp = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .uncompressedSize:
                cmp = lhs.uncompressedSize < rhs.uncompressedSize
            case .compressedSize:
                cmp = lhs.compressedSize < rhs.compressedSize
            case .ratio:
                cmp = lhs.compressionRatioPercent < rhs.compressionRatioPercent
            case .method:
                cmp = lhs.compressionMethodName < rhs.compressionMethodName
            case .modifiedDate:
                cmp = lhs.modifiedDate < rhs.modifiedDate
            }
            return sortAscending ? cmp : !cmp
        }

        return items
    }

    var selectedEntries: [ArchiveEntry] {
        visibleEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    // MARK: - Archive Lifecycle & Actions

    func handleIncomingURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1, let first = urls.first, first.scheme == "boltzip" {
            handleFinderSchemeURL(first)
        } else {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                handleDroppedOrOpenedURLs(fileURLs)
            }
        }
    }

    private func handleFinderSchemeURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        let op = items.first(where: { $0.name == "op" })?.value ?? "openWorkspace"
        let paths = items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }

        switch op {
        case "openWorkspace":
            NSApp.activate(ignoringOtherApps: true)
        case "open":
            if let first = paths.first { openArchive(url: first) }
        case "testIntegrity":
            if let first = paths.first { testIntegrity(archiveURL: first) }
        case "smartExtract":
            if let first = paths.first { quickExtract(mode: .smart, archiveURL: first) }
        case "extractSubfolder":
            if let first = paths.first { quickExtract(mode: .subfolder, archiveURL: first) }
        case "compressZip":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .zip, algorithm: .deflate) }
        case "compressTarZst":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .tarZst, algorithm: .zstd) }
        case "compress7z":
            if !paths.isEmpty { compressImmediate(inputs: paths, format: .sevenZip, algorithm: .xz) }
        case "compressWizard":
            if !paths.isEmpty { activeSheet = .createArchive(paths) }
        default:
            break
        }
    }

    func compressImmediate(inputs: [URL], format: ArchiveFormat, algorithm: CompressionAlgorithm) {
        guard let first = inputs.first else { return }
        let parentDir = first.deletingLastPathComponent()
        let baseName = inputs.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let stem = (inputs.count == 1 && isDirectory(first)) ? first.lastPathComponent : baseName
        var candidate = parentDir.appendingPathComponent("\(stem).\(format.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentDir.appendingPathComponent("\(stem) (\(counter)).\(format.fileExtension)")
            counter += 1
        }
        let opts = CreateArchiveOptions(
            format: format,
            algorithm: algorithm,
            excludeMacJunk: defaultStripMacJunk
        )
        createArchive(inputs: inputs, outputURL: candidate, options: opts)
    }

    func handleDroppedOrOpenedURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        if urls.count == 1, ArchiveFormat.detect(from: first) != nil, !isDirectory(first) {
            openArchive(url: first)
        } else {
            activeSheet = .createArchive(urls)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择要浏览或解压的压缩包"
        if panel.runModal() == .OK, let url = panel.url {
            openArchive(url: url)
        }
    }

    func startNewArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "选择要压缩的文件或文件夹"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            activeSheet = .createArchive(panel.urls)
        }
    }

    func openArchive(url: URL) {
        let encoding = encodingOption
        isBusy = true
        statusMessage = "正在读取 \(url.lastPathComponent)..."
        Task.detached(priority: .userInitiated) {
            do {
                let result = try BoltArchiveEngine.inspect(archiveURL: url, encoding: encoding)
                await MainActor.run {
                    self.listing = result
                    self.currentFolder = ""
                    self.selectedEntryIDs.removeAll()
                    self.searchText = ""
                    self.savedPassword = nil
                    self.isBusy = false
                    self.recordRecent(url)
                    self.statusMessage = "已打开 \(url.lastPathComponent) · 共 \(result.entries.count) 个条目"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "打开压缩包失败"
                }
            }
        }
    }

    func reloadWithEncoding(_ newEncoding: FilenameEncodingOption) {
        encodingOption = newEncoding
        guard let url = listing?.archiveURL else { return }
        openArchive(url: url)
    }

    func closeArchive() {
        listing = nil
        currentFolder = ""
        selectedEntryIDs.removeAll()
        searchText = ""
        savedPassword = nil
        statusMessage = "就绪 · 拖入压缩包浏览，或拖入文件立即打包"
    }

    func createArchive(inputs: [URL], outputURL: URL, options: CreateArchiveOptions) {
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: "准备压缩...")
        statusMessage = "正在创建 \(outputURL.lastPathComponent)..."

        Task.detached(priority: .userInitiated) {
            do {
                let created = try BoltArchiveEngine.createArchive(from: inputs, to: outputURL, options: options) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                let mainCreated = created.last ?? outputURL
                let refreshed = try BoltArchiveEngine.inspect(archiveURL: mainCreated, encoding: options.encoding)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.listing = refreshed
                    self.currentFolder = ""
                    self.selectedEntryIDs.removeAll()
                    self.recordRecent(mainCreated)
                    self.statusMessage = "创建成功：\(created.map(\.lastPathComponent).joined(separator: ", "))"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "创建压缩包失败"
                }
            }
        }
    }

    func quickExtract(mode: ExtractMode, archiveURL overrideURL: URL? = nil) {
        guard let targetArchive = overrideURL ?? listing?.archiveURL else { return }
        let dest = targetArchive.deletingLastPathComponent()
        let opts = ExtractOptions(
            destinationURL: dest,
            mode: mode,
            overwritePolicy: .overwrite,
            password: savedPassword,
            encoding: encodingOption,
            stripMacJunk: defaultStripMacJunk
        )
        runExtract(options: opts, archiveURL: targetArchive)
    }

    func triggerSmartExtractNow() {
        quickExtract(mode: .smart)
    }

    func runExtract(options: ExtractOptions, archiveURL overrideURL: URL? = nil) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: "正在解压...")
        statusMessage = "正在解压 \(archiveURL.lastPathComponent)..."

        Task.detached(priority: .userInitiated) {
            do {
                let outDir = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: options) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if let pw = options.password, !pw.isEmpty {
                        self.savedPassword = pw
                    }
                    self.statusMessage = "解压完成 -> \(outDir.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([outDir])
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.activeSheet = .passwordPrompt(.extract(archiveURL: archiveURL, options: options))
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "解压失败"
                }
            }
        }
    }

    func exportSelectedAsNewZip(entryIDs: Set<String>) {
        guard let sourceArchive = listing?.archiveURL, !entryIDs.isEmpty else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = "Selected_Export.zip"
        savePanel.title = "将选中条目导出为新 ZIP 归档"
        guard savePanel.runModal() == .OK, let destZip = savePanel.url else { return }

        let pw = savedPassword
        let enc = encodingOption
        let strip = defaultStripMacJunk
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0.1, currentItem: "正在抽取选中条目...")

        Task.detached(priority: .userInitiated) {
            let tempStage = FileManager.default.temporaryDirectory
                .appendingPathComponent("BoltZipExport-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempStage) }
            do {
                let extOpts = ExtractOptions(
                    destinationURL: tempStage,
                    mode: .selected(entryIDs),
                    overwritePolicy: .overwrite,
                    password: pw,
                    encoding: enc,
                    stripMacJunk: strip
                )
                _ = try BoltArchiveEngine.extract(archiveURL: sourceArchive, options: extOpts)
                let children = try FileManager.default.contentsOfDirectory(at: tempStage, includingPropertiesForKeys: nil)
                let createOpts = CreateArchiveOptions(format: .zip, algorithm: .deflate, excludeMacJunk: strip)
                _ = try BoltArchiveEngine.createArchive(from: children, to: destZip, options: createOpts)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.statusMessage = "已导出新 ZIP：\(destZip.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([destZip])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func testIntegrity(password: String? = nil, archiveURL overrideURL: URL? = nil) {
        guard let archiveURL = overrideURL ?? listing?.archiveURL else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: "正在校验 CRC32 / HMAC...")
        statusMessage = "正在校验归档完整性..."

        Task.detached(priority: .userInitiated) {
            do {
                let report = try BoltArchiveEngine.testIntegrity(archiveURL: archiveURL, password: pw, encoding: enc) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    if report.skippedEncryptedCount > 0 && pw == nil {
                        self.activeSheet = .passwordPrompt(.testIntegrity(archiveURL: archiveURL))
                    } else {
                        if let pw, !pw.isEmpty { self.savedPassword = pw }
                        self.activeSheet = .integrityReport(report)
                        self.statusMessage = report.isHealthy ? "完整性校验通过 (\(report.passedCount)/\(report.totalEntries))" : "校验发现异常项"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func previewOrOpenEntry(_ entry: ArchiveEntry, password: String? = nil) {
        if entry.isDirectory {
            currentFolder = entry.path
            selectedEntryIDs.removeAll()
            return
        }
        guard let archiveURL = listing?.archiveURL else { return }
        let pw = password ?? savedPassword
        let enc = encodingOption
        let previewRoot = previewTempRoot

        isBusy = true
        statusMessage = "正在提取预览 \(entry.name)..."

        Task.detached(priority: .userInitiated) {
            do {
                let data = try BoltArchiveEngine.readEntryData(
                    archiveURL: archiveURL,
                    entryPath: entry.path,
                    password: pw,
                    encoding: enc
                )
                let subDir = previewRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
                let fileURL = subDir.appendingPathComponent(entry.name)
                try data.write(to: fileURL, options: .atomic)

                await MainActor.run {
                    self.isBusy = false
                    if let pw, !pw.isEmpty { self.savedPassword = pw }
                    self.statusMessage = "正在预览 \(entry.name)"
                    QuickLookPreviewController.shared.preview(url: fileURL)
                }
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                await MainActor.run {
                    self.isBusy = false
                    self.activeSheet = .passwordPrompt(.preview(entry))
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - In-Place ZIP Editing

    func addItemsToCurrentZipPanel(targetFolder: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.title = "选择要添加到归档的文件或文件夹"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let folder = targetFolder ?? currentFolder
            editCurrentZip([.addItems(urls: panel.urls, targetFolder: folder)])
        }
    }

    func addItemsToCurrentZip(_ urls: [URL], targetFolder: String? = nil) {
        editCurrentZip([.addItems(urls: urls, targetFolder: targetFolder ?? currentFolder)])
    }

    func createFolderInZip(parentFolder: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
        guard !trimmed.isEmpty else { return }
        editCurrentZip([.createFolder(path: parentFolder + trimmed + "/")])
    }

    func renamePath(_ oldPath: String, to newName: String) {
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
        guard !cleanNew.isEmpty else { return }
        let isDir = oldPath.hasSuffix("/")
        let trimmedOld = isDir ? String(oldPath.dropLast()) : oldPath
        let parentPrefix: String
        if let idx = trimmedOld.lastIndex(of: "/") {
            parentPrefix = String(trimmedOld[..<idx]) + "/"
        } else {
            parentPrefix = ""
        }
        let newPath = parentPrefix + cleanNew + (isDir ? "/" : "")
        editCurrentZip([.renamePath(oldPath: oldPath, newPath: newPath)])
    }

    func deletePaths(_ targets: Set<String>) {
        guard !targets.isEmpty else { return }
        editCurrentZip([.deletePaths(targets)])
    }

    func deleteSelectedEntries() {
        deletePaths(Set(selectedEntries.map(\.path)))
    }

    private func editCurrentZip(_ ops: [ZipEditOperation]) {
        guard let listing, listing.format.supportsInPlaceEditing else {
            alertMessage = "当前格式暂不支持包内原地编辑，仅 ZIP 格式支持。"
            return
        }
        let url = listing.archiveURL
        let enc = encodingOption
        let opts = CreateArchiveOptions(
            format: .zip,
            algorithm: .deflate,
            encryption: savedPassword == nil ? .none : .aes256,
            password: savedPassword,
            excludeMacJunk: defaultStripMacJunk
        )
        isBusy = true
        progress = OperationProgress(fractionCompleted: 0, currentItem: "正在更新归档...")

        Task.detached(priority: .userInitiated) {
            do {
                try BoltArchiveEngine.editZip(at: url, operations: ops, options: opts, encoding: enc) { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                let updated = try BoltArchiveEngine.inspect(archiveURL: url, encoding: enc)
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.listing = updated
                    self.selectedEntryIDs.removeAll()
                    self.statusMessage = "归档已更新 · 共 \(updated.entries.count) 个条目"
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.progress = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Utilities

    func copyToPasteboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "已复制\(label)：\(text)"
    }

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeRecent(_ url: URL) {
        recentArchivePaths.removeAll { $0 == url.path }
        UserDefaults.standard.set(recentArchivePaths, forKey: recentsKey)
    }

    func openShowcaseWebsite() {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("showcase/index.html"),
            URL(fileURLWithPath: "/Users/xuyang/Codes/BoltZip/showcase/index.html")
        ]
        for case let candidate? in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.open(candidate)
            return
        }
        alertMessage = "未找到展示页面 showcase/index.html"
    }

    private func recordRecent(_ url: URL) {
        var paths = recentArchivePaths.filter { $0 != url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 8 { paths = Array(paths.prefix(8)) }
        recentArchivePaths = paths
        UserDefaults.standard.set(paths, forKey: recentsKey)
    }
}
