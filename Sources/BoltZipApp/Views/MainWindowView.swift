import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isTableDropTargeted = false
    @State private var showAppearancePopover = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        let l = vm.l10n
        let minW: CGFloat = vm.listing == nil ? 380 : 500
        let minH: CGFloat = vm.listing == nil ? 285 : 340
        Group {
            if let listing = vm.listing {
                archiveExplorer(listing: listing, l: l)
            } else {
                WelcomeDropZoneView(vm: vm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(windowBackingLayer)
        .background(
            WindowStyleConfigurator(
                isTranslucent: vm.isWindowTranslucent,
                backgroundOpacity: vm.windowBackgroundOpacity,
                minWidth: minW,
                minHeight: minH
            )
        )
        .frame(minWidth: minW, minHeight: minH)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .containerBackground(
            vm.isWindowTranslucent ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)),
            for: .window
        )
        .toolbarBackgroundVisibility(vm.isWindowTranslucent ? .hidden : .automatic, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if vm.listing != nil {
                    Button {
                        vm.closeArchive()
                    } label: {
                        Label(l.backHome, systemImage: "house")
                    }

                    Button {
                        vm.navigateUp()
                    } label: {
                        Label(l.goUp, systemImage: "chevron.up")
                    }
                    .disabled(!vm.canNavigateUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.startNewArchivePanel()
                } label: {
                    Label(l.newCompress, systemImage: "plus.rectangle.on.folder")
                }

                Button {
                    vm.openArchivePanel()
                } label: {
                    Label(l.open, systemImage: "folder")
                }

                if let listing = vm.listing {
                    Divider()

                    Button {
                        vm.triggerSmartExtractNow()
                    } label: {
                        Label(l.smartExtract, systemImage: "arrow.down.doc.fill")
                    }

                    Button {
                        let mode: ExtractMode = vm.selectedEntryIDs.isEmpty ? .smart : .selected(vm.selectedEntryIDs)
                        vm.activeSheet = .extractOptions(mode)
                    } label: {
                        Label(l.extractTo, systemImage: "square.and.arrow.down.on.square")
                    }

                    if listing.format.supportsInPlaceEditing {
                        Button {
                            vm.addItemsToCurrentZipPanel()
                        } label: {
                            Label(l.addInside, systemImage: "doc.badge.plus")
                        }

                        Button {
                            vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
                        } label: {
                            Label(l.newFolder, systemImage: "folder.badge.plus")
                        }

                        Button {
                            vm.deleteSelectedEntries()
                        } label: {
                            Label(l.delete, systemImage: "trash")
                        }
                        .disabled(vm.selectedEntryIDs.isEmpty)
                    }

                    Button {
                        vm.testIntegrity()
                    } label: {
                        Label(l.verify, systemImage: "checkmark.shield")
                    }

                    Divider()
                }

                Button {
                    showAppearancePopover.toggle()
                } label: {
                    Label(l.layoutMenuTitle, systemImage: "slider.horizontal.3")
                }
                .help(l.appearanceTitle)
                .popover(isPresented: $showAppearancePopover, arrowEdge: .bottom) {
                    AppearancePopoverView(vm: vm)
                }
            }
        }
        .overlay {
            if vm.isBusy {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView(value: vm.progress?.fractionCompleted ?? 0.3)
                            .progressViewStyle(.linear)
                            .frame(width: 240)
                        Text(vm.progress?.currentItem ?? vm.statusMessage)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(18)
                    .glassEffect(.regular.tint(.cyan.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(radius: 16)
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
                IntegrityReportSheet(vm: vm, report: report)
            case .benchmark:
                BenchmarkSheet(vm: vm)
            case .passwordPrompt(let purpose):
                PasswordPromptSheet(vm: vm, purpose: purpose)
            case .createFolder(let parentFolder):
                SimpleNamePromptSheet(
                    vm: vm,
                    title: l.createFolderTitle,
                    placeholder: "docs",
                    confirmLabel: l.createBtn
                ) { name in
                    vm.createFolderInZip(parentFolder: parentFolder, name: name)
                }
            case .renamePath(let oldPath, let currentName):
                SimpleNamePromptSheet(
                    vm: vm,
                    title: l.renameEntryTitle,
                    initialValue: currentName,
                    placeholder: l.colName,
                    confirmLabel: l.renameBtn
                ) { newName in
                    vm.renamePath(oldPath, to: newName)
                }
            case .entryProperties(let entry):
                EntryPropertiesSheet(vm: vm, entry: entry)
            }
        }
        .alert(l.alertTitle, isPresented: Binding(
            get: { vm.alertMessage != nil },
            set: { if !$0 { vm.alertMessage = nil } }
        )) {
            Button(l.confirm, role: .cancel) { vm.alertMessage = nil }
        } message: {
            Text(vm.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var windowBackingLayer: some View {
        if vm.isWindowTranslucent {
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

    @ViewBuilder
    private func archiveExplorer(listing: ArchiveListing, l: L10n) -> some View {
        NavigationSplitView(columnVisibility: $vm.columnVisibility) {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: Binding(
                    get: { vm.currentFolder },
                    set: { newValue in
                        if let newValue {
                            vm.currentFolder = newValue
                            vm.selectedEntryIDs.removeAll()
                        }
                    }
                )) {
                    Section(l.folderTreeSection) {
                        FolderTreeRow(
                            node: vm.folderTree,
                            vm: vm,
                            canEditZip: listing.format.supportsInPlaceEditing
                        )
                    }
                }
                .listStyle(.sidebar)

                if vm.showSidebarInspector {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(listing.format.displayName)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(.cyan.opacity(0.18)), in: Capsule())
                            Spacer()
                            if listing.hasEncryptedEntries {
                                Label(l.encryptedBadge, systemImage: "lock.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }

                        InfoMetricRow(label: l.totalEntries, value: l.itemCount(listing.entries.count))
                        InfoMetricRow(label: l.originalSize, value: DropHelper.formatBytes(listing.totalUncompressedBytes))
                        InfoMetricRow(label: l.packedSize, value: DropHelper.formatBytes(listing.totalCompressedBytes))
                        InfoMetricRow(label: l.spaceSaved, value: String(format: "%.1f%%", listing.overallCompressionRatioPercent))

                        Divider()

                        HStack {
                            Text(l.filenameEncoding)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { vm.encodingOption },
                                set: { vm.reloadWithEncoding($0) }
                            )) {
                                ForEach(FilenameEncodingOption.allCases) { enc in
                                    Text(l.encodingTitle(enc)).tag(enc)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.mini)
                        }
                    }
                    .padding(10)
                    .glassEffect(.regular.tint(.cyan.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding([.horizontal, .bottom], 8)
                }
            }
            .navigationSplitViewColumnWidth(min: 165, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 8) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
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
                                        .font(.system(size: 12.5, weight: crumb.path == vm.currentFolder ? .semibold : .regular, design: .rounded))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
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

                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            TextField(l.searchPlaceholder, text: $vm.searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .frame(minWidth: 90, maxWidth: 160)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)

                Table(vm.visibleEntries, selection: $vm.selectedEntryIDs) {
                    TableColumn(l.colName) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile(entry.name))
                                .foregroundStyle(entry.isDirectory ? Color.cyan : Color.secondary)
                            Text(entry.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            if entry.isEncrypted {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .width(min: 110, ideal: 220)

                    TableColumn(l.colOriginalSize) { entry in
                        Text(entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 55, ideal: 75)

                    TableColumn(l.colPackedSize) { entry in
                        Text(entry.isDirectory || entry.compressedSize == 0 ? "—" : DropHelper.formatBytes(entry.compressedSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 55, ideal: 75)

                    TableColumn(l.colRatio) { entry in
                        if entry.isDirectory || entry.uncompressedSize == 0 {
                            Text("—").foregroundStyle(.tertiary)
                        } else {
                            Text(String(format: "%.1f%%", entry.compressionRatioPercent))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }
                    .width(min: 48, ideal: 60)

                    TableColumn(l.colMethod) { entry in
                        let label = entry.isEncrypted ? "\(entry.compressionMethodName) · \(entry.encryptionLabel)" : entry.compressionMethodName
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 65, ideal: 100)

                    TableColumn(l.colModified) { entry in
                        Text(Self.dateFormatter.string(from: entry.modifiedDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 110)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 10)
                .padding(.bottom, vm.showStatusBar ? 0 : 10)
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.isEmpty {
                        emptySpaceContextMenu(listing: listing, l: l)
                    } else {
                        rowContextMenu(ids: ids, listing: listing, l: l)
                    }
                } primaryAction: { ids in
                    guard let firstID = ids.first,
                          let entry = vm.visibleEntries.first(where: { $0.id == firstID }) else { return }
                    vm.previewOrOpenEntry(entry)
                }
                .onKeyPress(.space) {
                    guard let firstID = vm.selectedEntryIDs.first,
                          let entry = vm.visibleEntries.first(where: { $0.id == firstID }) else { return .ignored }
                    vm.previewOrOpenEntry(entry)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let firstID = vm.selectedEntryIDs.first,
                          let entry = vm.visibleEntries.first(where: { $0.id == firstID }) else { return .ignored }
                    vm.previewOrOpenEntry(entry)
                    return .handled
                }
                .overlay {
                    if isTableDropTargeted && listing.format.supportsInPlaceEditing {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                            .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                Label(l.dropToAddLabel(vm.currentFolder.isEmpty ? l.rootLabel : vm.currentFolder), systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .glassEffect(.regular.tint(.cyan.opacity(0.22)).interactive(), in: Capsule())
                            }
                            .padding(.horizontal, 10)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTableDropTargeted) { providers in
                    guard listing.format.supportsInPlaceEditing else { return false }
                    return DropHelper.extractFileURLs(from: providers) { urls in
                        vm.addItemsToCurrentZip(urls)
                    }
                }

                if vm.showStatusBar {
                    HStack(spacing: 12) {
                        Text(vm.statusMessage)
                            .lineLimit(1)
                        Spacer()
                        if !vm.selectedEntryIDs.isEmpty {
                            let selBytes = vm.selectedEntries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
                            Text(l.selectedSummary(vm.selectedEntryIDs.count, DropHelper.formatBytes(selBytes)))
                                .foregroundStyle(.cyan)
                        }
                        if listing.format.supportsInPlaceEditing {
                            Text(l.editableHint)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding([.horizontal, .bottom], 10)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func rowContextMenu(ids: Set<String>, listing: ArchiveListing, l: L10n) -> some View {
        let picked = vm.visibleEntries.filter { ids.contains($0.id) }
        if let first = picked.first, picked.count == 1 {
            Button(first.isDirectory ? l.ctxOpenFolder : l.ctxQuickLook) {
                vm.previewOrOpenEntry(first)
            }
            Button(l.ctxProperties) {
                vm.activeSheet = .entryProperties(first)
            }
            Divider()
            Button("\(l.ctxCopyName) (\(first.name))") {
                vm.copyToPasteboard(first.name)
            }
            Button(l.ctxCopyPath) {
                vm.copyToPasteboard(first.path)
            }
            Divider()
        }

        Button(l.ctxExtractSelHere) {
            vm.quickExtract(mode: .selected(ids))
        }
        Button(l.ctxExtractSelTo) {
            vm.activeSheet = .extractOptions(.selected(ids))
        }
        Button(l.ctxExportNewZip) {
            vm.exportSelectedAsNewZip(entryIDs: ids)
        }

        Divider()

        Button(l.ctxVerifyArchive) {
            vm.testIntegrity()
        }

        if listing.format.supportsInPlaceEditing {
            Divider()
            Button(l.ctxAddHere) {
                vm.addItemsToCurrentZipPanel()
            }
            Button(l.ctxNewFolderHere) {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
            if let single = picked.first, picked.count == 1 {
                Button(l.ctxRename) {
                    vm.activeSheet = .renamePath(oldPath: single.path, currentName: single.name)
                }
            }
            Button(l.ctxDeleteFromArchive, role: .destructive) {
                vm.selectedEntryIDs = ids
                vm.deleteSelectedEntries()
            }
        }
    }

    @ViewBuilder
    private func emptySpaceContextMenu(listing: ArchiveListing, l: L10n) -> some View {
        Button(l.ctxSmartExtractAll) {
            vm.quickExtract(mode: .smart)
        }
        Button(l.ctxExtractAllSubfolder) {
            vm.quickExtract(mode: .subfolder)
        }
        Button(l.ctxExtractAllTo) {
            vm.activeSheet = .extractOptions(.smart)
        }

        if listing.format.supportsInPlaceEditing {
            Divider()
            Button(l.ctxAddHere) {
                vm.addItemsToCurrentZipPanel()
            }
            Button(l.ctxNewFolderHere) {
                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
            }
        }

        Divider()

        Button(l.ctxVerifyAll) {
            vm.testIntegrity()
        }

        Menu(l.ctxSwitchEncoding) {
            ForEach(FilenameEncodingOption.allCases) { enc in
                Button {
                    vm.reloadWithEncoding(enc)
                } label: {
                    if vm.encodingOption == enc {
                        Label(l.encodingTitle(enc), systemImage: "checkmark")
                    } else {
                        Text(l.encodingTitle(enc))
                    }
                }
            }
        }

        Menu(l.ctxSortBy) {
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
                        Label(l.sortColumnTitle(col), systemImage: vm.sortAscending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(l.sortColumnTitle(col))
                    }
                }
            }
        }

        Divider()
        Button(l.ctxShowInFinder) {
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
        let l = vm.l10n
        return Label(node.name, systemImage: node.path.isEmpty ? "archivebox.fill" : "folder.fill")
            .tag(node.path)
            .contextMenu {
                Button(l.ctxOpenDir) {
                    vm.currentFolder = node.path
                    vm.selectedEntryIDs.removeAll()
                }
                if !node.path.isEmpty {
                    Button(l.ctxExtractDir) {
                        vm.activeSheet = .extractOptions(.selected([node.path]))
                    }
                    Button(l.ctxCopyDirPath) {
                        vm.copyToPasteboard(node.path)
                    }
                } else {
                    Button(l.ctxSmartExtractAll) {
                        vm.quickExtract(mode: .smart)
                    }
                }

                if canEditZip {
                    Divider()
                    Button(l.ctxAddToDir) {
                        vm.addItemsToCurrentZipPanel(targetFolder: node.path)
                    }
                    Button(l.ctxNewSubfolder) {
                        vm.activeSheet = .createFolder(parentFolder: node.path)
                    }
                    if !node.path.isEmpty {
                        Button(l.ctxRenameDir) {
                            vm.activeSheet = .renamePath(oldPath: node.path, currentName: node.name)
                        }
                        Button(l.ctxDeleteDir, role: .destructive) {
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
    }
}
