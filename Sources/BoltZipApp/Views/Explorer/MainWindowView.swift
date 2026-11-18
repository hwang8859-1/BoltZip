import BoltZipCore
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var vm: WorkspaceViewModel
    @State private var titlebarHeight: CGFloat = 40
    @State private var isFullScreen: Bool = false

    var body: some View {
        let l = vm.l10n
        let minW: CGFloat = vm.listing == nil ? 350 : 540
        let minH: CGFloat = vm.listing == nil ? 270 : 320

        applyingMainToolbar(l: l) {
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
            .preferredColorScheme(vm.appTheme.colorScheme)
            .navigationTitle(vm.listing == nil ? "BoltZip" : " ")
            .boltWindowContainerBackground(
                vm.effectiveWindowTranslucency ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            )
            .boltWindowToolbarBackgroundVisibility(vm.effectiveWindowTranslucency ? .hidden : .automatic)
        }
        .overlay {
            InAppHUDBusyOverlay(vm: vm, hud: vm.inAppTaskHUD)
        }
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
    }

    @ViewBuilder
    private func applyingMainToolbar<Content: View>(
        l: L10n,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            content().toolbar {
                liquidGlassToolbarContent(l: l)
            }
        } else if let listing = vm.listing {
            content().toolbar {
                legacyArchiveToolbarContent(listing: listing, l: l)
            }
        } else if isFullScreen {
            content().toolbar {
                legacyWelcomeFullScreenToolbarContent(l: l)
            }
        } else {
            content().toolbar {
                legacyWelcomeToolbarContent(l: l)
            }
        }
    }

    @available(macOS 26.0, *)
    @ToolbarContentBuilder
    private func liquidGlassToolbarContent(l: L10n) -> some ToolbarContent {
        if let listing = vm.listing {
            ToolbarItem(placement: .navigation) {
                archiveNavigationToolbarContent(l: l)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .primaryAction) {
                archivePrimaryToolbarContent(listing: listing, l: l)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            if isFullScreen {
                ToolbarItem(placement: .navigation) {
                    welcomeFullScreenCloseContent(l: l)
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem(placement: .primaryAction) {
                welcomePrimaryToolbarContent(l: l)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    @ToolbarContentBuilder
    private func legacyArchiveToolbarContent(listing: ArchiveListing, l: L10n) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            archiveNavigationToolbarContent(l: l)
        }

        ToolbarItem(placement: .primaryAction) {
            archivePrimaryToolbarContent(listing: listing, l: l)
        }
    }

    @ToolbarContentBuilder
    private func legacyWelcomeFullScreenToolbarContent(l: L10n) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            welcomeFullScreenCloseContent(l: l)
        }

        ToolbarItem(placement: .primaryAction) {
            welcomePrimaryToolbarContent(l: l)
        }
    }

    @ToolbarContentBuilder
    private func legacyWelcomeToolbarContent(l: L10n) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            welcomePrimaryToolbarContent(l: l)
        }
    }

    private func archiveNavigationToolbarContent(l: L10n) -> some View {
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

            ToolbarPillIconButton(
                systemImage: "sidebar.left",
                label: l.folderTreeSection,
                helpText: l.folderTreeSection
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    vm.isSidebarVisible.toggle()
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
        .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
    }

    private func archivePrimaryToolbarContent(listing: ArchiveListing, l: L10n) -> some View {
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
            .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())

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
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 30)
            .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
        }
    }

    private func welcomeFullScreenCloseContent(l: L10n) -> some View {
        ToolbarPillIconButton(
            systemImage: "xmark",
            label: l.close,
            helpText: l.closeWindowMenuTitle
        ) {
            closeActiveArchiveOrWindow()
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
        .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
    }

    private func welcomePrimaryToolbarContent(l: L10n) -> some View {
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
                systemImage: "gearshape",
                label: l.settingsMenuTitle,
                helpText: l.settingsMenuTitle
            ) {
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.delegate as? BoltZipAppDelegate)?.openSettingsWindow()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 30)
        .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, interactive: true, in: Capsule())
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
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
        }
    }
}

private struct InAppHUDBusyOverlay: View {
    @ObservedObject var vm: WorkspaceViewModel
    @ObservedObject var hud: QuickTaskHUDModel

    var body: some View {
        Group {
            if hud.phase != .idle {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                    QuickTaskHUDView(vm: vm, hud: hud, isFloatingWindow: false)
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
                    .shadow(radius: 16)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: hud.phase == .idle)
    }
}
