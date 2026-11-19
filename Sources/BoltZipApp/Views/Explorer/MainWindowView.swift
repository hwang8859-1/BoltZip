import BoltZipCore
import SwiftUI

struct MainWindowView: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var titlebarHeight: CGFloat = 40
    @State private var isFullScreen: Bool = false

    var body: some View {
        let l = vm.l10n
        let minW: CGFloat = vm.listing == nil ? 336 : 560
        let minH: CGFloat = vm.listing == nil ? 192 : 320

        Group {
            if let listing = vm.listing {
                ArchiveExplorerView(vm: vm, listing: listing, titlebarHeight: titlebarHeight)
            } else {
                WelcomeDropZoneView(vm: vm, titlebarHeight: titlebarHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoltUnifiedWindowBacking(vm: vm))
        .background(
            WindowStyleConfigurator(
                isTranslucent: vm.effectiveWindowTranslucency,
                backgroundOpacity: vm.windowBackgroundOpacity,
                minWidth: minW,
                minHeight: minH,
                windowTitle: vm.listing?.archiveURL.lastPathComponent ?? "BoltZip",
                hideWindowTitle: vm.listing != nil,
                titlebarHeight: $titlebarHeight,
                isFullScreen: $isFullScreen
            )
        )
        .frame(minWidth: minW, minHeight: minH)
        .environment(\.boltGlassIntensity, vm.glassIntensity)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .navigationTitle(vm.listing == nil ? "BoltZip" : " ")
        .boltUnifiedWindowContainerBackground(glassEnabled: vm.effectiveWindowTranslucency)
        .toolbar {
            mainToolbarContent(l: l)
        }
        .overlay {
            hudAndBusyOverlay
        }
        .animation(.easeInOut(duration: 0.18), value: vm.inAppTaskHUD.phase == .idle)
        .sheet(item: $vm.activeSheet) { sheet in
            activeSheetView(sheet, l: l)
        }
        .alert(l.alertTitle, isPresented: Binding(
            get: { vm.alertMessage != nil },
            set: { if !$0 { vm.alertMessage = nil } }
        )) {
            Button(l.confirm, role: .cancel) { vm.alertMessage = nil }
        } message: {
            Text(vm.alertMessage ?? "")
        }
        .alert(
            l.extractConflictTitle,
            isPresented: Binding(
                get: { vm.pendingExtractConflict != nil },
                set: { if !$0 { vm.cancelExtractConflict() } }
            ),
            presenting: vm.pendingExtractConflict
        ) { _ in
            Button(l.overwriteExistingBtn, role: .destructive) {
                vm.confirmExtractOverwrite()
            }
            Button(l.keepBothRenameBtn) {
                vm.confirmExtractRename()
            }
            Button(l.cancel, role: .cancel) {
                vm.cancelExtractConflict()
            }
        } message: { conflict in
            Text(l.extractConflictMessage(
                folder: conflict.destinationRoot.lastPathComponent,
                names: conflict.conflictingNames
            ))
        }
        .alert(
            l.batchDropTitle,
            isPresented: Binding(
                get: { vm.pendingBatchArchiveDrop != nil },
                set: { if !$0 { vm.pendingBatchArchiveDrop = nil } }
            ),
            presenting: vm.pendingBatchArchiveDrop
        ) { batch in
            Button(l.batchDropSmartExtractAll) {
                let urls = batch.urls
                vm.pendingBatchArchiveDrop = nil
                vm.executeBatchArchiveDropAction(urls: urls, mode: .smart)
            }
            Button(l.batchDropSubfolderAll) {
                let urls = batch.urls
                vm.pendingBatchArchiveDrop = nil
                vm.executeBatchArchiveDropAction(urls: urls, mode: .subfolder)
            }
            Button(l.batchDropRepack) {
                let urls = batch.urls
                vm.pendingBatchArchiveDrop = nil
                vm.presentStandaloneCompressWizard(inputs: urls)
            }
            Button(l.cancel, role: .cancel) {
                vm.pendingBatchArchiveDrop = nil
            }
        } message: { batch in
            Text(l.batchDropMessage(batch.urls.count))
        }
        .alert(
            l.confirmDeleteTitle,
            isPresented: Binding(
                get: { vm.pendingDeleteConfirmation != nil },
                set: { if !$0 { vm.pendingDeleteConfirmation = nil } }
            ),
            presenting: vm.pendingDeleteConfirmation
        ) { req in
            Button(l.confirmDeleteBtn, role: .destructive) {
                let targets = req.paths
                vm.pendingDeleteConfirmation = nil
                vm.deletePaths(targets)
            }
            Button(l.cancel, role: .cancel) {
                vm.pendingDeleteConfirmation = nil
            }
        } message: { req in
            Text(l.confirmDeleteMessage(req.paths.count))
        }
    }

    @ToolbarContentBuilder
    private func mainToolbarContent(l: L10n) -> some ToolbarContent {
        if let listing = vm.listing {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 1) {
                    if isFullScreen {
                        ToolbarPillIconButton(
                            systemImage: "xmark",
                            label: l.close,
                            helpText: l.closeWindowMenuTitle
                        ) {
                            closeActiveArchiveOrWindow()
                        }

                        toolbarDivider
                    }

                    if let parentFrame = vm.archiveBackStack.last {
                        ToolbarPillIconButton(
                            systemImage: "arrow.uturn.backward",
                            label: l.backToParentArchive(parentFrame.archiveURL.lastPathComponent),
                            helpText: l.backToParentArchive(parentFrame.archiveURL.lastPathComponent)
                        ) {
                            vm.navigateBackFromNestedArchive()
                        }
                    }

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
                        label: l.backToArchiveRoot,
                        helpText: l.backToArchiveRoot,
                        isDisabled: vm.currentFolder.isEmpty && !vm.isSearchingActive
                    ) {
                        vm.returnToArchiveRoot()
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

                    ToolbarPillIconButton(
                        systemImage: "chevron.down",
                        label: l.goDown,
                        helpText: l.goDown,
                        isDisabled: !vm.canNavigateDown
                    ) {
                        vm.navigateDown()
                    }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                }
                .padding(.horizontal, 4)
                .frame(height: 30)
                .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, level: .elevated, tone: .regular, interactive: true, in: Capsule())
            }
            .boltHiddenSharedBackground()

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(BoltType.cardEyebrow)
                            .foregroundStyle(.secondary)
                        TextField(l.searchPlaceholder, text: $vm.searchText)
                            .textFieldStyle(.plain)
                            .font(BoltType.subbody)
                            .frame(width: 92)
                        if !vm.searchText.isEmpty {
                            Button {
                                vm.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(BoltType.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, level: .elevated, tone: .regular, interactive: true, in: Capsule())

                    HStack(spacing: 1) {
                        ToolbarPillIconButton(
                            systemImage: "folder",
                            label: l.open,
                            helpText: l.open
                        ) {
                            vm.openArchivePanel()
                        }

                        toolbarDivider

                        ToolbarPillIconButton(
                            systemImage: "arrow.down.doc.fill",
                            label: l.smartExtract,
                            helpText: l.smartExtractShortcutHint
                        ) {
                            vm.triggerSmartExtractNow()
                        }
                        .keyboardShortcut("e", modifiers: .command)

                        ToolbarPillIconButton(
                            systemImage: "square.and.arrow.down.on.square",
                            label: l.extractTo,
                            helpText: l.extractTo
                        ) {
                            let mode: ExtractMode = vm.selectedEntryIDs.isEmpty ? .smart : .selected(vm.selectedEntryIDs)
                            vm.activeSheet = .extractOptions(mode)
                        }

                        if listing.canEditInPlace {
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
                                systemImage: "text.bubble",
                                label: l.archiveCommentEditBtn,
                                helpText: l.archiveCommentTitle,
                                isActive: !listing.comment.isEmpty
                            ) {
                                vm.activeSheet = .editArchiveComment(current: listing.comment)
                            }
                        }

                        toolbarDivider

                        ToolbarPillIconButton(
                            systemImage: "checkmark.shield",
                            label: l.verify,
                            helpText: l.verify
                        ) {
                            vm.testIntegrity()
                        }

                        ToolbarPillIconButton(
                            systemImage: "info.circle",
                            label: l.inspectorButton,
                            helpText: l.inspectorButton,
                            isActive: vm.showSidebarInspector && vm.columnVisibility != .detailOnly
                        ) {
                            toggleExplorerInspector()
                        }
                        .keyboardShortcut("i", modifiers: .command)
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 30)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, level: .elevated, tone: .regular, interactive: true, in: Capsule())
                }
            }
            .boltHiddenSharedBackground()
        } else {
            if isFullScreen {
                ToolbarItem(placement: .navigation) {
                    ToolbarPillIconButton(
                        systemImage: "xmark",
                        label: l.close,
                        helpText: l.closeWindowMenuTitle
                    ) {
                        closeActiveArchiveOrWindow()
                    }
                    .padding(.horizontal, 2)
                    .frame(height: 30)
                    .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, level: .elevated, tone: .regular, interactive: true, in: Capsule())
                }
                .boltHiddenSharedBackground()
            }

            ToolbarItem(placement: .primaryAction) {
                ToolbarPillIconButton(
                    systemImage: "gearshape",
                    label: l.settingsMenuTitle,
                    helpText: l.settingsMenuTitle
                ) {
                    boltActivateAppToForeground()
                    openSettings()
                }
                .padding(.horizontal, 4)
                .frame(height: 30)
                .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, level: .elevated, tone: .regular, interactive: true, in: Capsule())
            }
            .boltHiddenSharedBackground()
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
    }

    private func toggleExplorerInspector() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            if vm.columnVisibility == .detailOnly {
                vm.columnVisibility = .all
                vm.showSidebarInspector = true
            } else {
                vm.showSidebarInspector.toggle()
            }
        }
    }

    private func closeActiveArchiveOrWindow() {
        if vm.shouldReturnHomeOnWindowClose() {
            vm.closeArchive()
            return
        }
        let targetWindow = NSApp.keyWindow
            ?? NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "") == "boltzip.main" })
        targetWindow?.performClose(nil)
    }

    @ViewBuilder
    private var hudAndBusyOverlay: some View {
        if vm.inAppTaskHUD.phase != .idle {
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                QuickTaskHUDView(vm: vm, hud: vm.inAppTaskHUD, isFloatingWindow: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        } else if vm.isBusy {
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView(value: vm.progress?.fractionCompleted ?? 0.3)
                        .progressViewStyle(.linear)
                        .frame(width: 240)
                    Text(vm.progress?.currentItem ?? vm.statusMessage)
                        .font(BoltType.subbodyMedium)
                        .lineLimit(1)
                }
                .padding(18)
                .boltLayeredSurface(
                    glassEnabled: vm.effectiveWindowTranslucency,
                    level: .card,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous)
                )
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            }
        }
    }

    @ViewBuilder
    private func activeSheetView(_ sheet: ActiveSheet, l: L10n) -> some View {
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
        case .editArchiveComment(let current):
            ArchiveCommentSheet(vm: vm, initialComment: current, canEdit: vm.listing?.canEditInPlace == true)
        case .updateAvailable(let info):
            UpdateAvailableSheet(vm: vm, release: info)
        }
    }
}
