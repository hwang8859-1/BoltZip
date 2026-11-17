import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isTableDropTargeted = false
    @State private var showAppearancePopover = false
    @State private var titlebarHeight: CGFloat = 40
    @State private var sidebarWidth: CGFloat = 215
    @State private var dragStartSidebarWidth: CGFloat?
    @State private var isDividerHovered = false
    @State private var expandedFolderPaths: Set<String> = [""]

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
                WelcomeDropZoneView(vm: vm, titlebarHeight: titlebarHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(windowBackingLayer)
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
        .boltWindowContainerBackground(
            vm.effectiveWindowTranslucency ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .boltWindowToolbarBackgroundVisibility(vm.effectiveWindowTranslucency ? .hidden : .automatic)
        .toolbar {
            if let listing = vm.listing {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 1) {
                        ToolbarPillIconButton(
                            systemImage: "sidebar.left",
                            label: l.folderTreeSection,
                            helpText: l.folderTreeSection
                        ) {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                vm.columnVisibility = (vm.columnVisibility == .detailOnly) ? .all : .detailOnly
                            }
                        }

                        ToolbarPillIconButton(
                            systemImage: "house",
                            label: l.backHome,
                            helpText: l.backHome
                        ) {
                            vm.closeArchive()
                        }

                        ToolbarPillIconButton(
                            systemImage: "chevron.up",
                            label: l.goUp,
                            helpText: l.goUp,
                            isDisabled: !vm.canNavigateUp
                        ) {
                            vm.navigateUp()
                        }
                        .keyboardShortcut(.upArrow, modifiers: .command)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 30)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
                }
                .boltHiddenSharedBackground()

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 1) {
                        ToolbarPillIconButton(
                            systemImage: "plus.rectangle.on.folder",
                            label: l.newCompress,
                            helpText: l.newCompress
                        ) {
                            vm.startNewArchivePanel()
                        }

                        ToolbarPillIconButton(
                            systemImage: "folder",
                            label: l.open,
                            helpText: l.open
                        ) {
                            vm.openArchivePanel()
                        }

                        pillSeparator

                        ToolbarPillIconButton(
                            systemImage: "arrow.down.doc.fill",
                            label: l.smartExtract,
                            helpText: l.smartExtract
                        ) {
                            vm.triggerSmartExtractNow()
                        }

                        ToolbarPillIconButton(
                            systemImage: "square.and.arrow.down.on.square",
                            label: l.extractTo,
                            helpText: l.extractTo
                        ) {
                            let mode: ExtractMode = vm.selectedEntryIDs.isEmpty ? .smart : .selected(vm.selectedEntryIDs)
                            vm.activeSheet = .extractOptions(mode)
                        }

                        if listing.format.supportsInPlaceEditing {
                            ToolbarPillIconButton(
                                systemImage: "doc.badge.plus",
                                label: l.addInside,
                                helpText: l.addInside
                            ) {
                                vm.addItemsToCurrentZipPanel()
                            }

                            ToolbarPillIconButton(
                                systemImage: "folder.badge.plus",
                                label: l.newFolder,
                                helpText: l.newFolder
                            ) {
                                vm.activeSheet = .createFolder(parentFolder: vm.currentFolder)
                            }

                            ToolbarPillIconButton(
                                systemImage: "trash",
                                label: l.delete,
                                helpText: l.delete,
                                isDisabled: vm.selectedEntryIDs.isEmpty
                            ) {
                                vm.deleteSelectedEntries()
                            }
                        }

                        ToolbarPillIconButton(
                            systemImage: "checkmark.shield",
                            label: l.verify,
                            helpText: l.verify
                        ) {
                            vm.testIntegrity()
                        }

                        pillSeparator

                        ToolbarPillIconButton(
                            systemImage: "slider.horizontal.3",
                            label: l.layoutMenuTitle,
                            helpText: l.appearanceTitle
                        ) {
                            showAppearancePopover.toggle()
                        }
                        .popover(isPresented: $showAppearancePopover, arrowEdge: .bottom) {
                            AppearancePopoverView(vm: vm)
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 30)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
                }
                .boltHiddenSharedBackground()
            } else {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 1) {
                        ToolbarPillIconButton(
                            systemImage: "plus.rectangle.on.folder",
                            label: l.newCompress,
                            helpText: l.newArchive
                        ) {
                            vm.startNewArchivePanel()
                        }

                        ToolbarPillIconButton(
                            systemImage: "folder",
                            label: l.open,
                            helpText: l.openArchive
                        ) {
                            vm.openArchivePanel()
                        }

                        ToolbarPillIconButton(
                            systemImage: "slider.horizontal.3",
                            label: l.layoutMenuTitle,
                            helpText: l.appearanceTitle
                        ) {
                            showAppearancePopover.toggle()
                        }
                        .popover(isPresented: $showAppearancePopover, arrowEdge: .bottom) {
                            AppearancePopoverView(vm: vm)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 30)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
                }
                .boltHiddenSharedBackground()
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
                    .boltGlassSurface(.regular, tint: .cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        if vm.effectiveWindowTranslucency {
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
        let isSidebarVisible = vm.columnVisibility != .detailOnly
        let glassEnabled = vm.effectiveWindowTranslucency

        GeometryReader { geo in
            let w = geo.size.width
            let topOffset = max(40, titlebarHeight)
            let clampedSidebarWidth = min(max(168, sidebarWidth), max(168, w * 0.40))

            ZStack(alignment: .top) {
                // Layer 2: Floating glass directory sidebar & file browser over Layer 1 backdrop
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        leftGlassSidebar(listing: listing, l: l, glassEnabled: glassEnabled)
                            .frame(width: clampedSidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        sidebarResizeDivider(currentWidth: clampedSidebarWidth, maxWidth: max(200, w * 0.40))
                    }

                    rightGlassWorkspace(listing: listing, l: l, glassEnabled: glassEnabled)
                }
                .padding(.horizontal, 10)
                .padding(.top, topOffset + 4)
                .padding(.bottom, 10)
                .frame(width: w, height: geo.size.height)

                // Layer 3: Unified full-width glass menu/title bar matching welcome screen height
                explorerTitlebarOverlay(width: w, height: topOffset, glassEnabled: glassEnabled)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
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

    @ViewBuilder
    private func explorerTitlebarOverlay(width: CGFloat, height: CGFloat, glassEnabled: Bool) -> some View {
        let isDark = colorScheme == .dark
        Group {
            if glassEnabled {
                Rectangle()
                    .fill(Color.clear)
                    .boltGlassSurface(
                        .regular,
                        tint: Color.white.opacity(isDark ? 0.04 : 0.10),
                        in: Rectangle()
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(isDark ? 0.10 : 0.28))
                            .frame(height: 0.5)
                    }
            } else {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func leftGlassSidebar(listing: ArchiveListing, l: L10n, glassEnabled: Bool) -> some View {
        let isDark = colorScheme == .dark
        BoltGlassContainer(spacing: 8) {
            VStack(spacing: 8) {
                // Directory Tree Glass Card
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text(l.folderTreeSection)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                        .opacity(glassEnabled ? 0.30 : 0.65)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            GlassFolderTreeRow(
                                node: vm.folderTree,
                                depth: 0,
                                vm: vm,
                                canEditZip: listing.format.supportsInPlaceEditing,
                                glassEnabled: glassEnabled,
                                expandedPaths: $expandedFolderPaths
                            )
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    tint: Color.cyan.opacity(isDark ? 0.04 : 0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                // Archive Summary Inspector Glass Card
                if vm.showSidebarInspector {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(listing.format.displayName)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    tone: .regular,
                                    tint: .cyan.opacity(0.18),
                                    in: Capsule()
                                )
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

                        Divider().opacity(glassEnabled ? 0.35 : 0.7)

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
                    .boltLayeredSurface(
                        glassEnabled: glassEnabled,
                        tone: .regular,
                        tint: .cyan.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
            }
        }
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
    private func rightGlassWorkspace(listing: ArchiveListing, l: L10n, glassEnabled: Bool) -> some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 8) {
            BoltGlassContainer(spacing: 8) {
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
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    tone: crumb.path == vm.currentFolder ? .regular : .clear,
                                    tint: crumb.path == vm.currentFolder ? .cyan.opacity(0.18) : nil,
                                    interactive: true,
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
                    .boltLayeredSurface(glassEnabled: glassEnabled, tone: .regular, in: Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

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
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                tint: Color.white.opacity(isDark ? 0.02 : 0.04),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
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
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            Label(l.dropToAddLabel(vm.currentFolder.isEmpty ? l.rootLabel : vm.currentFolder), systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .boltLayeredSurface(glassEnabled: glassEnabled, tone: .regular, tint: .cyan.opacity(0.22), interactive: true, in: Capsule())
                        }
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
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

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

    private var pillSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
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

private struct GlassFolderTreeRow: View {
    let node: FolderTreeNode
    let depth: Int
    @Bindable var vm: WorkspaceViewModel
    let canEditZip: Bool
    let glassEnabled: Bool
    @Binding var expandedPaths: Set<String>
    @State private var isHovered = false

    private var isSelected: Bool { vm.currentFolder == node.path }
    private var isExpanded: Bool { expandedPaths.contains(node.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            rowView

            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    GlassFolderTreeRow(
                        node: child,
                        depth: depth + 1,
                        vm: vm,
                        canEditZip: canEditZip,
                        glassEnabled: glassEnabled,
                        expandedPaths: $expandedPaths
                    )
                }
            }
        }
    }

    private var rowView: some View {
        let l = vm.l10n
        return HStack(spacing: 4) {
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
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 16)
            }

            Image(systemName: node.path.isEmpty ? "archivebox.fill" : "folder.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (node.path.isEmpty ? Color.indigo : Color.accentColor)
                )

            Text(node.name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)
        }
        .padding(.leading, CGFloat(depth * 12) + 4)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(glassEnabled ? 0.78 : 0.92))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct ToolbarPillIconButton: View {
    let systemImage: String
    let label: String
    let helpText: String
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(isDisabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(width: 32, height: 24)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(!isDisabled && isHovered ? 0.10 : 0.0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(label)
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
