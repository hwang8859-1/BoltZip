import AppKit
import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showInspector: Bool = true
    @State private var isTableDropTargeted = false
    @State private var showAppearancePopover = false
    @State private var titlebarHeight: CGFloat = 40
    @State private var sidebarWidth: CGFloat = 210
    @State private var inspectorWidth: CGFloat = 260
    @State private var dragStartSidebarWidth: CGFloat?
    @State private var dragStartInspectorWidth: CGFloat?
    @State private var isSidebarDividerHovered = false
    @State private var isInspectorDividerHovered = false
    @State private var expandedFolderPaths: Set<String> = [""]

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        let l = vm.l10n
        let minW: CGFloat = vm.listing == nil ? 440 : 680
        let minH: CGFloat = vm.listing == nil ? 320 : 420

        Group {
            if let listing = vm.listing {
                archiveExplorer(listing: listing, l: l)
            } else {
                WelcomeDropZoneView(vm: vm, titlebarHeight: titlebarHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            WindowStyleConfigurator(
                isTranslucent: vm.effectiveWindowTranslucency,
                backgroundOpacity: vm.windowBackgroundOpacity,
                minWidth: minW,
                minHeight: minH,
                titlebarHeight: $titlebarHeight
            )
        )
        .frame(minWidth: minW, minHeight: minH)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .toolbar {
            if let listing = vm.listing {
                // Navigation Section
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            vm.columnVisibility = (vm.columnVisibility == .detailOnly) ? .all : .detailOnly
                        }
                    } label: {
                        Label(l.folderTreeSection, systemImage: "sidebar.left")
                    }
                    .help(l.folderTreeSection)

                    Button {
                        vm.closeArchive()
                    } label: {
                        Label(l.backHome, systemImage: "house")
                    }
                    .help(l.backHome)

                    Button {
                        vm.navigateUp()
                    } label: {
                        Label(l.goUp, systemImage: "chevron.up")
                    }
                    .disabled(!vm.canNavigateUp)
                    .help(l.goUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                }

                // Principal Title Section
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)

                        Text(listing.archiveURL.lastPathComponent)
                            .font(.system(.body, design: .default).weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(listing.format.displayName)
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())

                        if listing.hasEncryptedEntries {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .help(l.encryptedBadge)
                        }
                    }
                    .frame(maxWidth: 320)
                }

                // Primary Action Section
                ToolbarItemGroup(placement: .primaryAction) {
                    // Extract Split Menu
                    Menu {
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
                    } label: {
                        Label(l.smartExtract, systemImage: "arrow.down.doc.fill")
                    } primaryAction: {
                        vm.triggerSmartExtractNow()
                    }
                    .help(l.smartExtract)
                    .keyboardShortcut("e", modifiers: .command)

                    if listing.format.supportsInPlaceEditing {
                        // Edit & Add Menu
                        Menu {
                            Button {
                                vm.addItemsToCurrentZipPanel()
                            } label: {
                                Label(l.addInside, systemImage: "plus")
                            }

                            Button {
                                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
                            } label: {
                                Label(l.newFolder, systemImage: "folder.badge.plus")
                            }

                            if !vm.selectedEntryIDs.isEmpty {
                                Divider()
                                Button(role: .destructive) {
                                    vm.deleteSelectedEntries()
                                } label: {
                                    Label(l.delete, systemImage: "trash")
                                }
                            }
                        } label: {
                            Label(l.addInside, systemImage: "plus")
                        } primaryAction: {
                            vm.addItemsToCurrentZipPanel()
                        }
                        .help(l.addInside)
                    }

                    Button {
                        vm.testIntegrity()
                    } label: {
                        Label(l.verify, systemImage: "checkmark.shield")
                    }
                    .help(l.verify)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showInspector.toggle()
                        }
                    } label: {
                        Label("显示简介", systemImage: "info.circle")
                    }
                    .help("显示/隐藏属性检查器 (⌘I)")
                    .keyboardShortcut("i", modifiers: .command)

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
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        vm.startNewArchivePanel()
                    } label: {
                        Label(l.newCompress, systemImage: "plus")
                    }
                    .help(l.newArchive)

                    Button {
                        vm.openArchivePanel()
                    } label: {
                        Label(l.open, systemImage: "folder")
                    }
                    .help(l.openArchive)

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
        }
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: l.searchPlaceholder)
        .overlay {
            if vm.isBusy {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(value: vm.progress?.fractionCompleted ?? 0.3)
                            .progressViewStyle(.linear)
                            .frame(width: 240)
                        Text(vm.progress?.currentItem ?? vm.statusMessage)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: Color.black.opacity(0.18), radius: 18)
                    )
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

    // MARK: - Archive Explorer View (3-Column Layout)
    @ViewBuilder
    private func archiveExplorer(listing: ArchiveListing, l: L10n) -> some View {
        let isSidebarVisible = vm.columnVisibility != .detailOnly

        GeometryReader { geo in
            let w = geo.size.width
            let clampedSidebarWidth = min(max(170, sidebarWidth), max(170, w * 0.35))
            let clampedInspectorWidth = min(max(220, inspectorWidth), max(220, w * 0.38))

            HStack(spacing: 0) {
                // Column 1: Native Sidebar
                if isSidebarVisible {
                    nativeSidebar(listing: listing, l: l)
                        .frame(width: clampedSidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    sidebarResizeDivider(currentWidth: clampedSidebarWidth, maxWidth: max(200, w * 0.40))
                }

                // Column 2: Center Table Workspace
                centerWorkspace(listing: listing, l: l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Column 3: Native Inspector (Collapsible)
                if showInspector && vm.showSidebarInspector {
                    inspectorResizeDivider(currentWidth: clampedInspectorWidth, maxWidth: max(240, w * 0.40))

                    nativeInspector(listing: listing, l: l)
                        .frame(width: clampedInspectorWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: w, height: geo.size.height)
        }
        .onAppear {
            seedExpandedFolders(from: vm.folderTree)
            expandAncestors(for: vm.currentFolder)
        }
        .onChange(of: listing.archiveURL) { _, _ in
            seedExpandedFolders(from: vm.folderTree)
            expandAncestors(for: vm.currentFolder)
        }
        .onChange(of: vm.currentFolder) { _, newPath in
            expandAncestors(for: newPath)
        }
    }

    // MARK: - Column 1: Native Sidebar
    @ViewBuilder
    private func nativeSidebar(listing: ArchiveListing, l: L10n) -> some View {
        VStack(spacing: 0) {
            // Directory Tree Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Text(l.folderTreeSection)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Directory Tree Rows
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    NativeFolderTreeRow(
                        node: vm.folderTree,
                        depth: 0,
                        vm: vm,
                        canEditZip: listing.format.supportsInPlaceEditing,
                        expandedPaths: $expandedFolderPaths
                    )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }

            Divider()

            // Footer Section: Clean Packing Badge & Encoding
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("自动隔离 .DS_Store / __MACOSX")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(l.filenameEncoding)
                        .font(.system(size: 11))
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
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }

    // MARK: - Column 2: Center Table Workspace
    @ViewBuilder
    private func centerWorkspace(listing: ArchiveListing, l: L10n) -> some View {
        VStack(spacing: 0) {
            // Path Bar (Finder-Style Breadcrumbs)
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(vm.breadcrumbComponents.enumerated()), id: \.offset) { idx, crumb in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                vm.currentFolder = crumb.path
                                vm.selectedEntryIDs.removeAll()
                            } label: {
                                HStack(spacing: 4) {
                                    if idx == 0 { Image(systemName: "archivebox.fill").font(.system(size: 11)) }
                                    Text(crumb.title)
                                }
                                .font(.system(size: 11.5, weight: crumb.path == vm.currentFolder ? .semibold : .regular))
                                .foregroundStyle(crumb.path == vm.currentFolder ? Color.primary : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    crumb.path == vm.currentFolder
                                        ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08))
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text("按 Space 快速预览")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(height: 28)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.40))

            Divider()

            // Main Files Table
            Table(vm.visibleEntries, selection: $vm.selectedEntryIDs) {
                TableColumn(l.colName) { entry in
                    HStack(spacing: 7) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile(entry.name))
                            .font(.system(size: 13))
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)

                        Text(entry.name)
                            .font(.system(size: 12.5))
                            .lineLimit(1)

                        if entry.isEncrypted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .width(min: 140, ideal: 240)

                TableColumn(l.colOriginalSize) { entry in
                    Text(entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(min: 65, ideal: 85)

                TableColumn(l.colPackedSize) { entry in
                    Text(entry.isDirectory || entry.compressedSize == 0 ? "—" : DropHelper.formatBytes(entry.compressedSize))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(min: 65, ideal: 85)

                TableColumn(l.colRatio) { entry in
                    if entry.isDirectory || entry.uncompressedSize == 0 {
                        Text("—").foregroundStyle(.tertiary)
                    } else {
                        Text(String(format: "%.1f%%", entry.compressionRatioPercent))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                .width(min: 55, ideal: 70)

                TableColumn(l.colMethod) { entry in
                    let label = entry.isEncrypted ? "\(entry.compressionMethodName) · \(entry.encryptionLabel)" : entry.compressionMethodName
                    Text(label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .width(min: 75, ideal: 110)

                TableColumn(l.colModified) { entry in
                    Text(Self.dateFormatter.string(from: entry.modifiedDate))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .width(min: 85, ideal: 120)
            }
            .alternatingRowBackgrounds(.enabled)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                        .background(Color.accentColor.opacity(0.08))
                        .overlay {
                            Label(l.dropToAddLabel(vm.currentFolder.isEmpty ? l.rootLabel : vm.currentFolder), systemImage: "plus.circle.fill")
                                .font(.headline)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .shadow(radius: 6)
                                )
                        }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTableDropTargeted) { providers in
                guard listing.format.supportsInPlaceEditing else { return false }
                return DropHelper.extractFileURLs(from: providers) { urls in
                    vm.addItemsToCurrentZip(urls)
                }
            }

            Divider()

            // Bottom Status Bar
            if vm.showStatusBar {
                HStack(spacing: 12) {
                    Text(vm.statusMessage)
                        .lineLimit(1)
                    Spacer()
                    if !vm.selectedEntryIDs.isEmpty {
                        let selBytes = vm.selectedEntries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
                        Text(l.selectedSummary(vm.selectedEntryIDs.count, DropHelper.formatBytes(selBytes)))
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.medium)
                    }
                    if listing.format.supportsInPlaceEditing {
                        Text(l.editableHint)
                            .foregroundStyle(.tertiary)
                    }
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.40))
            }
        }
    }

    // MARK: - Column 3: Native Inspector (显示简介)
    @ViewBuilder
    private func nativeInspector(listing: ArchiveListing, l: L10n) -> some View {
        let selected = vm.selectedEntries.first
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Text("显示简介")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showInspector = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("关闭检查器 (⌘I)")
                }

                if let entry = selected {
                    // Item Preview Card
                    VStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile(entry.name))
                            .font(.system(size: 38))
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                            .padding(.top, 4)

                        Text(entry.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text(entry.isDirectory ? "文件夹" : (entry.name as NSString).pathExtension.uppercased() + " 文件")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        Button {
                            vm.previewOrOpenEntry(entry)
                        } label: {
                            Label("Quick Look 预览", systemImage: "eye")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                            )
                    )

                    // Entry Properties
                    VStack(spacing: 7) {
                        inspectorMetricRow(label: "原始体积", value: entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
                        inspectorMetricRow(label: "压缩后体积", value: entry.isDirectory ? "—" : DropHelper.formatBytes(entry.compressedSize))
                        inspectorMetricRow(label: "空间节省", value: entry.isDirectory ? "—" : String(format: "%.1f%%", entry.compressionRatioPercent), isGreen: true)
                        inspectorMetricRow(label: "压缩引擎", value: entry.compressionMethodName)
                        inspectorMetricRow(label: "加密状态", value: entry.isEncrypted ? entry.encryptionLabel : "未加密")
                        inspectorMetricRow(label: "CRC32 校验", value: String(format: "0x%08X", entry.crc32))
                        inspectorMetricRow(label: "修改时间", value: Self.dateFormatter.string(from: entry.modifiedDate))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )

                    // Single Item Actions
                    VStack(spacing: 6) {
                        Button {
                            vm.quickExtract(mode: .selected([entry.id]))
                        } label: {
                            Text("单独解压选中项")
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if listing.format.supportsInPlaceEditing {
                            Button(role: .destructive) {
                                vm.deleteSelectedEntries()
                            } label: {
                                Text("从归档中删除")
                                    .font(.system(size: 11.5))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    // Whole Archive Overview Card
                    VStack(spacing: 8) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 4)

                        Text(listing.archiveURL.lastPathComponent)
                            .font(.system(size: 12.5, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text(listing.format.displayName)
                            .font(.system(size: 10.5, weight: .bold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                            )
                    )

                    // Archive Metrics
                    VStack(spacing: 7) {
                        inspectorMetricRow(label: l.totalEntries, value: l.itemCount(listing.entries.count))
                        inspectorMetricRow(label: l.originalSize, value: DropHelper.formatBytes(listing.totalUncompressedBytes))
                        inspectorMetricRow(label: l.packedSize, value: DropHelper.formatBytes(listing.totalCompressedBytes))
                        inspectorMetricRow(label: l.spaceSaved, value: String(format: "%.1f%%", listing.overallCompressionRatioPercent), isGreen: true)
                        inspectorMetricRow(label: "加密防护", value: listing.hasEncryptedEntries ? "AES-256 加密" : "未加密")
                        inspectorMetricRow(label: "纯净保护", value: "已剔除 .DS_Store")
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )

                    Button {
                        vm.triggerSmartExtractNow()
                    } label: {
                        Text("智能解压全部文件")
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func inspectorMetricRow(label: String, value: String, isGreen: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: isGreen ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isGreen ? Color.green : Color.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Resizable Splitters
    private func sidebarResizeDivider(currentWidth: CGFloat, maxWidth: CGFloat) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.primary.opacity(isSidebarDividerHovered ? 0.25 : 0.08))
                .frame(width: 3, height: isSidebarDividerHovered ? 40 : 24)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isSidebarDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartSidebarWidth == nil { dragStartSidebarWidth = currentWidth }
                    let base = dragStartSidebarWidth ?? currentWidth
                    sidebarWidth = min(max(170, base + value.translation.width), maxWidth)
                }
                .onEnded { _ in dragStartSidebarWidth = nil }
        )
    }

    private func inspectorResizeDivider(currentWidth: CGFloat, maxWidth: CGFloat) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.primary.opacity(isInspectorDividerHovered ? 0.25 : 0.08))
                .frame(width: 3, height: isInspectorDividerHovered ? 40 : 24)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isInspectorDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartInspectorWidth == nil { dragStartInspectorWidth = currentWidth }
                    let base = dragStartInspectorWidth ?? currentWidth
                    inspectorWidth = min(max(220, base - value.translation.width), maxWidth)
                }
                .onEnded { _ in dragStartInspectorWidth = nil }
        )
    }

    // MARK: - Directory Tree Utilities
    private func seedExpandedFolders(from root: FolderTreeNode) {
        var expanded: Set<String> = [root.path]
        var queue: [FolderTreeNode] = [root]
        var index = 0
        while index < queue.count && expanded.count < 140 {
            let current = queue[index]
            index += 1
            for child in current.children where expanded.count < 140 {
                expanded.insert(child.path)
                queue.append(child)
            }
        }
        expandedFolderPaths = expanded
    }

    private func expandAncestors(for folderPath: String) {
        expandedFolderPaths.insert("")
        guard !folderPath.isEmpty else { return }
        let parts = folderPath.split(separator: "/").map(String.init)
        var acc = ""
        for part in parts {
            acc = acc.isEmpty ? part : "\(acc)/\(part)"
            expandedFolderPaths.insert(acc)
        }
    }

    // MARK: - Context Menus
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
        case "zip", "7z", "tar", "gz", "zst", "xz", "rar": return "doc.zipper"
        case "mp4", "mov": return "film"
        case "mp3", "wav", "m4a": return "waveform"
        default: return "doc"
        }
    }
}

// MARK: - Native Folder Tree Row
private struct NativeFolderTreeRow: View {
    let node: FolderTreeNode
    let depth: Int
    @Bindable var vm: WorkspaceViewModel
    let canEditZip: Bool
    @Binding var expandedPaths: Set<String>
    @State private var isHovered = false

    private var isSelected: Bool { vm.currentFolder == node.path }
    private var isExpanded: Bool { expandedPaths.contains(node.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            rowView

            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    NativeFolderTreeRow(
                        node: child,
                        depth: depth + 1,
                        vm: vm,
                        canEditZip: canEditZip,
                        expandedPaths: $expandedPaths
                    )
                }
            }
        }
    }

    private var rowView: some View {
        let l = vm.l10n
        return HStack(spacing: 5) {
            if !node.children.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        if isExpanded {
                            expandedPaths.remove(node.path)
                        } else {
                            expandedPaths.insert(node.path)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            Image(systemName: node.path.isEmpty ? "archivebox.fill" : "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (node.path.isEmpty ? Color.indigo : Color.accentColor)
                )

            Text(node.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if node.fileCount > 0 {
                Text("\(node.fileCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
            }
        }
        .padding(.leading, CGFloat(depth * 10) + 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture {
            vm.currentFolder = node.path
            vm.selectedEntryIDs.removeAll()
        }
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
