import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveExplorerView: View {
    @Bindable var vm: WorkspaceViewModel
    let listing: ArchiveListing
    let titlebarHeight: CGFloat

    @State private var isTableDropTargeted = false
    @State private var sidebarWidth: CGFloat = 195
    @State private var dragStartSidebarWidth: CGFloat?
    @State private var isDividerHovered = false
    @State private var expandedFolderPaths: Set<String> = [""]
    @State private var lastTappedEntryID: String?
    @State private var lastTapTime: Date = .distantPast
    @State private var selectionAnchorID: String?
    @State private var pointerTracker = ExplorerPointerTracker()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        let l = vm.l10n
        let isSidebarVisible = vm.columnVisibility != .detailOnly
        let glassEnabled = vm.effectiveWindowTranslucency

        GeometryReader { geo in
            let w = geo.size.width
            let topOffset = max(40, titlebarHeight)
            let clampedSidebarWidth = min(max(168, sidebarWidth), max(168, w * 0.40))

            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        leftGlassSidebar(l: l, glassEnabled: glassEnabled)
                            .frame(width: clampedSidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        sidebarResizeDivider(currentWidth: clampedSidebarWidth, maxWidth: max(200, w * 0.40))
                    }

                    rightGlassWorkspace(l: l, glassEnabled: glassEnabled)
                }
                .padding(.horizontal, 10)
                .padding(.top, topOffset + 4)
                .padding(.bottom, 10)
                .frame(width: w, height: geo.size.height)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            seedExpandedFolders(from: vm.folderTree)
            expandAncestors(for: vm.currentFolder)
        }
        .onChange(of: listing.archiveURL) { _, _ in
            pointerTracker.hoveredEntry = nil
            seedExpandedFolders(from: vm.folderTree)
            expandAncestors(for: vm.currentFolder)
        }
        .onChange(of: vm.currentFolder) { _, newPath in
            pointerTracker.hoveredEntry = nil
            expandAncestors(for: newPath)
        }
        .onChange(of: vm.selectedEntryIDs) { _, _ in
            vm.scheduleDebouncedQuickLookUpdateIfVisible()
        }
    }

    @ViewBuilder
    private func leftGlassSidebar(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassContainer(spacing: 8) {
            VStack(spacing: 8) {
                ScrollViewReader { treeProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            GlassFolderTreeRow(
                                node: vm.folderTree,
                                depth: 0,
                                selectedFolder: vm.currentFolder,
                                l: l,
                                canEditZip: listing.canEditInPlace,
                                glassEnabled: glassEnabled,
                                expandedPaths: $expandedFolderPaths,
                                vm: vm
                            )
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }
                    .boltTopScrollHeaderBar(glassEnabled: glassEnabled, dividerEdge: .bottom) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(BoltType.captionMedium)
                                .foregroundStyle(.cyan)
                            Text(l.folderTreeSection)
                                .font(BoltType.cardEyebrow)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: BoltMetrics.headerHeight)
                    }
                    .onChange(of: vm.currentFolder) { _, newPath in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            treeProxy.scrollTo(newPath, anchor: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )

                if vm.showSidebarInspector {
                    sidebarSummaryCard(l: l, glassEnabled: glassEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSummaryCard(l: L10n, glassEnabled: Bool) -> some View {
        let selected = vm.selectedEntries
        VStack(alignment: .leading, spacing: 5) {
            if selected.count == 1, let entry = selected.first {
                singleEntryInspectorSection(entry: entry, l: l, glassEnabled: glassEnabled)
            } else if selected.count > 1 {
                multiSelectionInspectorSection(count: selected.count, l: l, glassEnabled: glassEnabled)
            } else {
                archiveOverviewInspectorSection(l: l, glassEnabled: glassEnabled)
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack {
                Text(l.filenameEncoding)
                    .font(BoltType.caption)
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
        .boltLayeredSurface(
            glassEnabled: glassEnabled,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private func archiveOverviewInspectorSection(l: L10n, glassEnabled: Bool) -> some View {
        HStack {
            BoltReadOnlyBadge(text: listing.format.displayName, isEmphasized: true)
            Spacer()
            if listing.hasEncryptedEntries {
                Label(l.encryptedBadge, systemImage: "lock.fill")
                    .font(BoltType.badge)
                    .foregroundStyle(.orange)
            }
        }

        InfoMetricRow(label: l.totalEntries, value: l.itemCount(listing.entries.count))
        InfoMetricRow(label: l.originalSize, value: DropHelper.formatBytes(listing.totalUncompressedBytes))
        InfoMetricRow(label: l.packedSize, value: DropHelper.formatBytes(listing.totalCompressedBytes))
        InfoMetricRow(
            label: l.spaceSaved,
            value: String(format: "%.1f%%", listing.overallCompressionRatioPercent),
            valueColor: .green
        )

        if !listing.comment.isEmpty || listing.canEditInPlace {
            HStack(spacing: 6) {
                Text(l.archiveCommentTitle)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    vm.activeSheet = .editArchiveComment(current: listing.comment)
                } label: {
                    Text(listing.comment.isEmpty ? l.archiveCommentEditBtn : listing.comment)
                        .font(BoltType.caption)
                        .foregroundStyle(listing.comment.isEmpty ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func singleEntryInspectorSection(entry: ArchiveEntry, l: L10n, glassEnabled: Bool) -> some View {
        let ext = (entry.name as NSString).pathExtension.uppercased()
        let kindLabel = entry.isDirectory
            ? l.inspectorFolderType
            : (ext.isEmpty ? l.inspectorGenericFile : l.inspectorFileExt(ext))

        HStack(spacing: 6) {
            Image(systemName: BoltFileIconCatalog.sfSymbolName(for: entry))
                .font(BoltType.subbody)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(BoltType.captionMedium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(kindLabel)
                    .font(BoltType.badge)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.isEncrypted {
                Image(systemName: "lock.fill")
                    .font(BoltType.badge)
                    .foregroundStyle(.orange)
                    .help(entry.encryptionLabel)
            }
        }

        InfoMetricRow(label: l.colOriginalSize, value: entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
        InfoMetricRow(label: l.colPackedSize, value: entry.isDirectory ? "—" : DropHelper.formatBytes(entry.compressedSize))
        InfoMetricRow(
            label: l.spaceSaved,
            value: (entry.isDirectory || entry.uncompressedSize == 0) ? "—" : String(format: "%.1f%%", entry.compressionRatioPercent),
            valueColor: (entry.isDirectory || entry.uncompressedSize == 0) ? nil : .green
        )
        InfoMetricRow(label: l.colMethod, value: entry.isEncrypted ? "\(entry.compressionMethodName) · \(entry.encryptionLabel)" : entry.compressionMethodName)
        if !entry.isDirectory {
            InfoMetricRow(label: "CRC32", value: entry.crc32 == 0 ? "0x00000000" : String(format: "0x%08X", entry.crc32))
        }
        InfoMetricRow(label: l.colModified, value: Self.dateFormatter.string(from: entry.modifiedDate))

        HStack(spacing: 5) {
            Button(entry.isDirectory ? l.ctxOpenFolder : l.quickLookShort) {
                vm.previewOrOpenEntry(entry)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button(l.extractSelectedShort) {
                vm.quickExtract(mode: .selected([entry.id]))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Spacer(minLength: 0)

            Button(l.moreDetailsShort) {
                vm.activeSheet = .entryProperties(entry)
            }
            .buttonStyle(.plain)
            .font(BoltType.caption)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func multiSelectionInspectorSection(count: Int, l: L10n, glassEnabled: Bool) -> some View {
        HStack {
            BoltReadOnlyBadge(text: l.selectedMultiTitle(count), isEmphasized: true)
            Spacer()
        }

        InfoMetricRow(label: l.colOriginalSize, value: DropHelper.formatBytes(vm.selectedTotalUncompressedBytes))
        InfoMetricRow(label: l.totalEntries, value: l.itemCount(listing.entries.count))

        HStack(spacing: 6) {
            Button(l.extractSelectedShort) {
                vm.quickExtract(mode: .selected(vm.selectedEntryIDs))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button(l.ctxExportNewZip) {
                vm.exportSelectedAsNewZip(entryIDs: vm.selectedEntryIDs)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .lineLimit(1)
        }
        .padding(.top, 2)
    }

    private func sidebarResizeDivider(currentWidth: CGFloat, maxWidth: CGFloat) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.primary.opacity(isDividerHovered ? 0.25 : 0.08))
                .frame(width: 3, height: isDividerHovered ? 44 : 28)
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isDividerHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartSidebarWidth == nil {
                        dragStartSidebarWidth = currentWidth
                    }
                    let base = dragStartSidebarWidth ?? currentWidth
                    sidebarWidth = min(max(168, base + value.translation.width), maxWidth)
                }
                .onEnded { _ in
                    dragStartSidebarWidth = nil
                }
        )
    }

    @ViewBuilder
    private func rightGlassWorkspace(l: L10n, glassEnabled: Bool) -> some View {
        VStack(spacing: 8) {
            GeometryReader { paneGeo in
                let cols = ExplorerColumnMetrics(availableWidth: paneGeo.size.width)
                let selectedIDs = vm.selectedEntryIDs
                ScrollViewReader { fileProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 2) {
                            Color.clear
                                .frame(height: 0)
                                .id("EXPLORER_TOP")

                            ForEach(vm.visibleEntries) { entry in
                                ExplorerFileRow(
                                    entry: entry,
                                    isSelected: selectedIDs.contains(entry.id),
                                    cols: cols,
                                    dateString: Self.dateFormatter.string(from: entry.modifiedDate),
                                    iconName: BoltFileIconCatalog.sfSymbolName(for: entry),
                                    pointerTracker: pointerTracker,
                                    onTap: { handleRowTap(entry) }
                                )
                                .contextMenu {
                                    let targetIDs: Set<String> = vm.selectedEntryIDs.contains(entry.id)
                                        ? vm.selectedEntryIDs
                                        : [entry.id]
                                    rowContextMenu(ids: targetIDs, listing: listing, l: l)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .boltTopScrollHeaderBar(glassEnabled: glassEnabled, dividerEdge: .bottom) {
                        fileListColumnHeader(l: l, cols: cols)
                    }
                    .onChange(of: vm.currentFolder) { _, _ in
                        fileProxy.scrollTo("EXPLORER_TOP", anchor: .top)
                    }
                    .onChange(of: vm.searchText) { _, _ in
                        fileProxy.scrollTo("EXPLORER_TOP", anchor: .top)
                    }
                    .onChange(of: vm.sortColumn) { _, _ in
                        fileProxy.scrollTo("EXPLORER_TOP", anchor: .top)
                    }
                    .onChange(of: vm.sortAscending) { _, _ in
                        fileProxy.scrollTo("EXPLORER_TOP", anchor: .top)
                    }
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.selectedEntryIDs.removeAll()
                            }
                            .contextMenu {
                                emptySpaceContextMenu(listing: listing, l: l)
                            }
                    }
                }
                .background {
                    ExplorerListDragHost(
                        vm: vm,
                        pointerTracker: pointerTracker,
                        headerHeight: BoltMetrics.headerHeight,
                        rowPitch: 32
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .onKeyPress(.space) { previewSelectedOrReturnIgnored() }
            .onKeyPress(.return) { previewSelectedOrReturnIgnored() }
            .onKeyPress(.upArrow) { moveSelection(delta: -1) }
            .onKeyPress(.downArrow) { moveSelection(delta: 1) }
            .overlay {
                if isTableDropTargeted && listing.canEditInPlace {
                    RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                        .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))
                        .overlay {
                            Label(l.dropToAddLabel(vm.currentFolder.isEmpty ? l.rootLabel : vm.currentFolder), systemImage: "plus.circle.fill")
                                .font(BoltType.sectionTitle)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .boltLayeredSurface(glassEnabled: glassEnabled, level: .elevated, tone: .regular, tint: .cyan.opacity(0.22), in: Capsule())
                        }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTableDropTargeted) { providers in
                guard listing.canEditInPlace else { return false }
                return DropHelper.extractFileURLs(from: providers) { urls in
                    vm.addItemsToCurrentZip(urls)
                }
            }

            if vm.showStatusBar {
                bottomBreadcrumbBar(l: l, glassEnabled: glassEnabled)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: vm.showStatusBar)
    }

    @ViewBuilder
    private func fileListColumnHeader(l: L10n, cols: ExplorerColumnMetrics) -> some View {
        HStack(spacing: 12) {
            sortableColumnHeader(l.colName, column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            sortableColumnHeader(l.colOriginalSize, column: .uncompressedSize, alignment: .trailing)
                .frame(width: cols.origW, alignment: .trailing)

            sortableColumnHeader(l.colPackedSize, column: .compressedSize, alignment: .trailing)
                .frame(width: cols.packedW, alignment: .trailing)

            sortableColumnHeader(l.colRatio, column: .ratio, alignment: .trailing)
                .frame(width: cols.ratioW, alignment: .trailing)

            if cols.showMethod {
                sortableColumnHeader(l.colMethod, column: .method, alignment: .leading)
                    .frame(width: cols.methodW, alignment: .leading)
                    .padding(.leading, 6)
            }

            sortableColumnHeader(l.colModified, column: .modifiedDate, alignment: .trailing)
                .frame(width: cols.modW, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: BoltMetrics.headerHeight)
    }

    @ViewBuilder
    private func bottomBreadcrumbBar(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassContainer(spacing: 8) {
            HStack(spacing: 10) {
                if let parentFrame = vm.archiveBackStack.last {
                    Button {
                        vm.navigateBackFromNestedArchive()
                    } label: {
                        Label(l.backToParentArchive(parentFrame.archiveURL.lastPathComponent), systemImage: "arrow.uturn.backward")
                            .font(BoltType.captionMedium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .boltLayeredSurface(
                        glassEnabled: glassEnabled,
                        level: .elevated,
                        tone: .regular,
                        tint: .orange.opacity(0.18),
                        interactive: true,
                        in: Capsule()
                    )
                }

                ScrollViewReader { crumbProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(Array(vm.breadcrumbComponents.enumerated()), id: \.offset) { idx, crumb in
                                if idx > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(BoltType.microIcon)
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    vm.searchText = ""
                                    vm.navigateToFolder(crumb.path)
                                } label: {
                                    HStack(spacing: 4) {
                                        if idx == 0 {
                                            Image(systemName: "archivebox.fill")
                                                .font(BoltType.caption)
                                        }
                                        Text(crumb.title)
                                    }
                                    .font(crumb.path == vm.currentFolder ? BoltType.captionMedium : BoltType.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                }
                                .id(crumb.path)
                                .buttonStyle(.plain)
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    level: crumb.path == vm.currentFolder ? .elevated : .card,
                                    tone: .regular,
                                    tint: crumb.path == vm.currentFolder ? .cyan.opacity(0.16) : nil,
                                    interactive: true,
                                    in: Capsule()
                                )
                            }
                        }
                    }
                    .defaultScrollAnchor(.trailing)
                    .onChange(of: vm.currentFolder) { _, newPath in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            crumbProxy.scrollTo(newPath, anchor: .trailing)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text(l.selectedSummary(
                    vm.selectedEntryIDs.count,
                    DropHelper.formatBytes(vm.selectedTotalUncompressedBytes)
                ))
                .font(BoltType.captionMedium)
                .monospacedDigit()
                .foregroundStyle(vm.selectedEntryIDs.isEmpty ? Color.secondary : Color.cyan)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func sortableColumnHeader(_ title: String, column: SortColumn, alignment: Alignment) -> some View {
        let isActive = vm.sortColumn == column
        Button {
            vm.toggleSortColumn(column)
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title).lineLimit(1)
                if isActive {
                    Image(systemName: vm.sortAscending ? "chevron.up" : "chevron.down")
                        .font(BoltType.microIcon)
                        .foregroundStyle(Color.accentColor)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .font(isActive ? BoltType.cardEyebrow : BoltType.captionMedium)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewSelectedOrReturnIgnored() -> KeyPress.Result {
        guard let firstID = vm.selectedEntryIDs.first,
              let entry = vm.visibleEntryByID[firstID] else { return .ignored }
        vm.previewOrOpenEntry(entry)
        return .handled
    }

    private func handleRowTap(_ entry: ArchiveEntry) {
        let now = Date()
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if vm.selectedEntryIDs.contains(entry.id) {
                vm.selectedEntryIDs.remove(entry.id)
            } else {
                vm.selectedEntryIDs.insert(entry.id)
            }
            selectionAnchorID = entry.id
            lastTappedEntryID = entry.id
            lastTapTime = now
            return
        }
        if flags.contains(.shift),
           let anchorID = selectionAnchorID,
           let anchorIdx = vm.visibleEntries.firstIndex(where: { $0.id == anchorID }),
           let targetIdx = vm.visibleEntries.firstIndex(where: { $0.id == entry.id }) {
            let lo = min(anchorIdx, targetIdx)
            let hi = max(anchorIdx, targetIdx)
            vm.selectedEntryIDs = Set(vm.visibleEntries[lo...hi].map(\.id))
            lastTappedEntryID = entry.id
            lastTapTime = now
            return
        }

        let isDoubleClick = (lastTappedEntryID == entry.id) && (now.timeIntervalSince(lastTapTime) < 0.35)
        vm.selectedEntryIDs = [entry.id]
        selectionAnchorID = entry.id
        lastTappedEntryID = entry.id
        lastTapTime = now
        if isDoubleClick {
            lastTappedEntryID = nil
            vm.previewOrOpenEntry(entry)
        }
    }

    private func moveSelection(delta: Int) -> KeyPress.Result {
        let entries = vm.visibleEntries
        guard !entries.isEmpty else { return .ignored }
        if let firstID = vm.selectedEntryIDs.first,
           let idx = entries.firstIndex(where: { $0.id == firstID }) {
            let nextIdx = min(max(0, idx + delta), entries.count - 1)
            let target = entries[nextIdx]
            vm.selectedEntryIDs = [target.id]
            selectionAnchorID = target.id
        } else {
            let target = delta >= 0 ? entries.first! : entries.last!
            vm.selectedEntryIDs = [target.id]
            selectionAnchorID = target.id
        }
        return .handled
    }

    private func seedExpandedFolders(from root: FolderTreeNode) {
        var expanded: Set<String> = [root.path]
        if root.children.count == 1, let singleTop = root.children.first {
            // Auto-expand single top-level wrapper folder so inner root structure is immediately visible
            expanded.insert(singleTop.path)
            for grandChild in singleTop.children.prefix(24) {
                if expanded.count >= 26 { break }
                expanded.insert(grandChild.path)
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
            acc += part + "/"
            expandedFolderPaths.insert(acc)
        }
    }
}
