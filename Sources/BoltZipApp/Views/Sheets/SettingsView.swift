import BoltZipCore
import SwiftUI

struct SettingsView: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case general
        case appearance
        case codecs

        var id: Int { rawValue }
    }

    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab
    @State private var feedbackMessage: String?
    @State private var associationFeedback: (text: String, isError: Bool)?

    init(vm: WorkspaceViewModel, initialTab: Tab = .general) {
        self.vm = vm
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        VStack(spacing: 12) {
            BoltGlassContainer(spacing: 6) {
                HStack(spacing: 6) {
                    tabPill(tab: .general, title: l.settingsTabGeneral, icon: "gearshape.fill", glassEnabled: glassEnabled)
                    tabPill(tab: .appearance, title: l.settingsTabAppearance, icon: "slider.horizontal.3", glassEnabled: glassEnabled)
                    tabPill(tab: .codecs, title: l.settingsTabCodecs, icon: "cpu", glassEnabled: glassEnabled)
                }
                .padding(5)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    level: .elevated,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
                )
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .general:
                        generalTabContent(l: l, glassEnabled: glassEnabled)
                    case .appearance:
                        appearanceTabContent(l: l, glassEnabled: glassEnabled)
                    case .codecs:
                        codecsTabContent(l: l, glassEnabled: glassEnabled)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous))

            BoltSheetFooterBar(glassEnabled: glassEnabled) {
                Text(BoltPlatformCapabilities.runtimeVersionSummary(
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? BoltZipVersion.current
                ))
                .font(BoltType.monoCaption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(l.close) {
                    NSApp.keyWindow?.performClose(nil)
                    dismiss()
                }
                .boltGlassProminentButton()
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 500, height: 500)
        .background(BoltUnifiedWindowBacking(vm: vm))
        .background(
            BoltAuxiliaryWindowStyleBridge(
                isTranslucent: glassEnabled,
                backgroundOpacity: vm.windowBackgroundOpacity
            )
        )
        .environment(\.boltGlassIntensity, vm.glassIntensity)
        .boltUnifiedWindowContainerBackground(glassEnabled: glassEnabled)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .onAppear {
            vm.refreshQuickActionsStatus()
            vm.refreshArchiveAssociations()
        }
    }

    // MARK: - Top Tab Pill

    @ViewBuilder
    private func tabPill(tab: Tab, title: String, icon: String, glassEnabled: Bool) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            Label(title, systemImage: icon)
                .symbolRenderingMode(.monochrome)
                .font(isActive ? BoltType.subbodyMedium : BoltType.subbody)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: BoltRadius.badge, style: .continuous)
                            .fill(Color.accentColor.opacity(glassEnabled ? 0.18 : 0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: BoltRadius.badge, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75)
                            )
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: BoltRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: General

    @ViewBuilder
    private func generalTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(
            l.settingsGeneralArchiveSection,
            icon: "archivebox.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled
        ) {
            BoltFormSwitchRow(
                title: l.stripMacJunkTitle,
                subtitle: l.stripMacJunkSubtitle,
                isOn: Binding(
                    get: { vm.defaultStripMacJunk },
                    set: { vm.updateDefaultStripMacJunk($0) }
                )
            )

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormMenuRow(
                title: l.defaultEncodingLabel,
                selectedTitle: l.encodingCompactTitle(vm.encodingOption)
            ) {
                ForEach(FilenameEncodingOption.allCases) { enc in
                    BoltMenuOptionButton(
                        title: l.encodingTitle(enc),
                        isSelected: vm.encodingOption == enc
                    ) {
                        vm.encodingOption = enc
                    }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormMenuRow(
                title: l.defaultExtractDestLabel,
                selectedTitle: vm.defaultExtractDestination.title(l)
            ) {
                ForEach(DefaultExtractDestination.allCases) { dest in
                    BoltMenuOptionButton(
                        title: dest.title(l),
                        isSelected: vm.defaultExtractDestination == dest
                    ) {
                        vm.defaultExtractDestination = dest
                    }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormMenuRow(
                title: l.defaultExtractModeLabel,
                selectedTitle: vm.defaultExtractMode.title(l)
            ) {
                ForEach(DefaultExtractModePreference.allCases) { modePref in
                    BoltMenuOptionButton(
                        title: modePref.title(l),
                        isSelected: vm.defaultExtractMode == modePref
                    ) {
                        vm.defaultExtractMode = modePref
                    }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormSwitchRow(
                title: l.preserveSymlinksTitle,
                subtitle: l.preserveSymlinksSubtitle,
                isOn: Binding(
                    get: { vm.preserveSymlinksOnCreate },
                    set: { vm.preserveSymlinksOnCreate = $0 }
                )
            )

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormSwitchRow(
                title: l.restoreSymlinksTitle,
                subtitle: l.restoreSymlinksSubtitle,
                isOn: Binding(
                    get: { vm.restoreSymlinksOnExtract },
                    set: { vm.restoreSymlinksOnExtract = $0 }
                )
            )

            BoltSectionDivider(glassEnabled: glassEnabled)

            BoltFormSwitchRow(
                title: l.autoCheckUpdatesTitle,
                subtitle: l.autoCheckUpdatesSubtitle,
                isOn: Binding(
                    get: { vm.autoCheckForUpdates },
                    set: { vm.autoCheckForUpdates = $0 }
                )
            )

            HStack {
                Spacer()
                Button {
                    vm.checkForUpdates(userInitiated: true)
                } label: {
                    if vm.isCheckingUpdates {
                        Label(l.checkingUpdatesLabel, systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(l.checkForUpdatesBtn, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .controlSize(.small)
                .boltGlassButton()
                .disabled(vm.isCheckingUpdates)
            }
        }

        BoltGlassSectionCard(
            l.finderIntegrationSection,
            icon: "contextualmenu.and.cursorarrow",
            iconColor: .accentColor,
            glassEnabled: glassEnabled
        ) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.finderRowTitle)
                        .font(BoltType.subbodyMedium)
                    Text(l.settingsFinderSubtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                BoltReadOnlyBadge(
                    text: vm.quickActionsInstalled ? l.statusEnabledBadge : l.statusDisabledBadge,
                    dotColor: vm.quickActionsInstalled ? .green : .secondary.opacity(0.55),
                    isEmphasized: vm.quickActionsInstalled
                )
            }

            HStack(spacing: 6) {
                Button(l.extensionSettings) {
                    vm.openFinderExtensionSettings()
                }
                .controlSize(.small)
                .boltGlassButton()

                Button(vm.quickActionsInstalled ? l.reinstallOrSync : l.installNow) {
                    feedbackMessage = vm.installFinderQuickActions()
                }
                .controlSize(.small)
                .boltGlassProminentButton()

                if vm.quickActionsInstalled {
                    Button(l.disableNow) {
                        vm.uninstallFinderQuickActions()
                        feedbackMessage = l.statusDisabledBadge
                    }
                    .controlSize(.small)
                    .boltGlassButton()
                }

                Spacer()
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(BoltType.caption)
                    .foregroundStyle(.green)
            }
        }

        defaultAssociationsCard(l: l, glassEnabled: glassEnabled)
    }

    @ViewBuilder
    private func defaultAssociationsCard(l: L10n, glassEnabled: Bool) -> some View {
        let statuses = vm.associationStatuses
        let commonGroups = Set(ArchiveAssociationGroup.commonArchiveGroups)
        let activeCommonCount = statuses.filter { commonGroups.contains($0.group) && $0.isBoltZipDefault }.count

        BoltGlassSectionCard(
            l.defaultAssociationsSection,
            icon: "doc.badge.gearshape.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 6
        ) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.defaultAssociationsTitle)
                        .font(BoltType.subbodyMedium)
                    Text(l.defaultAssociationsSummary(activeCommonCount, commonGroups.count))
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(l.restoreSystemDefaultsBtn) {
                    Task {
                        let res = await vm.setArchiveAssociation(
                            groups: ArchiveAssociationGroup.allCases,
                            toBoltZip: false
                        )
                        associationFeedback = (res.message, res.isError)
                    }
                }
                .controlSize(.small)
                .boltGlassButton()
                .disabled(vm.isUpdatingAssociations)

                Button(l.setAllDefaultsBtn) {
                    Task {
                        let res = await vm.setArchiveAssociation(
                            groups: ArchiveAssociationGroup.commonArchiveGroups,
                            toBoltZip: true
                        )
                        associationFeedback = (res.message, res.isError)
                    }
                }
                .controlSize(.small)
                .boltGlassProminentButton()
                .disabled(vm.isUpdatingAssociations)
            }

            if let associationFeedback {
                Text(associationFeedback.text)
                    .font(BoltType.caption)
                    .foregroundStyle(associationFeedback.isError ? .red : .green)
            }

            if !statuses.isEmpty {
                BoltSectionDivider(glassEnabled: glassEnabled)

                VStack(spacing: 5) {
                    ForEach(Array(statuses.enumerated()), id: \.element.id) { idx, status in
                        if idx > 0 {
                            BoltSectionDivider(glassEnabled: glassEnabled)
                        }
                        HStack(spacing: 8) {
                            BoltDocumentIconView(
                                kind: status.group.documentIconKind,
                                appTheme: vm.appTheme,
                                renderSize: 32,
                                displaySize: 26
                            )
                            .opacity(status.isBoltZipDefault ? 1.0 : 0.72)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.associationGroupTitle(status.group))
                                    .font(BoltType.subbodyMedium)
                                Text(status.group.extensionsSubtitle)
                                    .font(BoltType.monoCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            BoltReadOnlyBadge(
                                text: status.isBoltZipDefault ? l.alreadyDefaultBadge : status.currentAppName,
                                dotColor: status.isBoltZipDefault ? .green : nil,
                                isEmphasized: status.isBoltZipDefault
                            )
                            Toggle("", isOn: Binding(
                                get: { status.isBoltZipDefault },
                                set: { enableBolt in
                                    Task {
                                        let res = await vm.setArchiveAssociation(
                                            groups: [status.group],
                                            toBoltZip: enableBolt
                                        )
                                        associationFeedback = (res.message, res.isError)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(vm.isUpdatingAssociations)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Appearance

    @ViewBuilder
    private func appearanceTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(
            l.appearanceTitle,
            icon: "sparkles",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 7
        ) {
            BoltFormMenuRow(
                title: l.languageLabel,
                selectedTitle: l.languageCompactTitle(vm.appLanguage)
            ) {
                ForEach(AppLanguage.allCases) { lang in
                    BoltMenuOptionButton(
                        title: lang.nativePickerTitle,
                        isSelected: vm.appLanguage == lang
                    ) {
                        vm.appLanguage = lang
                    }
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack {
                Text(l.themeLabel)
                    .font(BoltType.subbodyMedium)
                Spacer()
                Picker("", selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(l)).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 196)
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack(spacing: 8) {
                Text(l.backgroundColorLabel)
                    .font(BoltType.subbodyMedium)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(AppBackgroundColor.presets) { preset in
                        let isSelected = vm.appBackgroundColor == preset
                        Button {
                            vm.appBackgroundColor = preset
                        } label: {
                            Circle()
                                .fill(preset.swatchColor())
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.22),
                                            lineWidth: isSelected ? 2 : 0.75
                                        )
                                )
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(BoltType.microIcon)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.title(l))
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1, height: 14)

                    ColorPicker("", selection: Binding(
                        get: { vm.customSwiftUIColorBinding },
                        set: { vm.setCustomBackgroundColor($0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .fixedSize()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                vm.appBackgroundColor == .custom ? Color.accentColor : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .help(l.bgColorCustom)
                }
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    BoltAppIconView(
                        style: vm.appIconStyle,
                        appTheme: vm.appTheme,
                        renderSize: 28,
                        displaySize: 22
                    )
                    Text(l.appIconStyleLabel)
                        .font(BoltType.subbodyMedium)
                    Spacer()
                    Picker("", selection: $vm.appIconStyle) {
                        ForEach(AppIconStyle.allCases) { style in
                            Text(style.title(l)).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 196)
                }

                Text(l.appIconStyleHint)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vm.supportsLiquidGlass {
                BoltSectionDivider(glassEnabled: glassEnabled)

                BoltFormSwitchRow(
                    title: l.enableTranslucency,
                    isOn: $vm.isWindowTranslucent
                )

                if vm.isWindowTranslucent {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(l.glassIntensityLabel)
                                .font(BoltType.subbodyMedium)
                            Spacer()
                            BoltReadOnlyBadge(
                                text: "\(Int((vm.glassIntensity * 100).rounded()))%"
                            )
                        }

                        HStack(spacing: 8) {
                            Text(l.glassSoftLabel)
                                .font(BoltType.caption)
                                .foregroundStyle(.tertiary)
                            Slider(value: $vm.glassIntensity, in: 0.0...1.0, step: 0.05)
                                .controlSize(.small)
                            Text(l.glassStrongLabel)
                                .font(BoltType.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }

        BoltGlassSectionCard(
            l.visibleSectionsTitle,
            icon: "rectangle.3.group",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 6
        ) {
            BoltFormSwitchRow(title: l.toggleFinderBanner, isOn: $vm.showFinderBanner)
            BoltSectionDivider(glassEnabled: glassEnabled)
            BoltFormSwitchRow(title: l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
            BoltSectionDivider(glassEnabled: glassEnabled)
            BoltFormSwitchRow(title: l.toggleRecentsCard, isOn: $vm.showRecentArchives)
            BoltSectionDivider(glassEnabled: glassEnabled)
            BoltFormSwitchRow(title: l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
            BoltSectionDivider(glassEnabled: glassEnabled)
            BoltFormSwitchRow(title: l.toggleStatusBar, isOn: $vm.showStatusBar)
        }
    }

    // MARK: - Tab 3: Performance & Codecs

    @ViewBuilder
    private func codecsTabContent(l: L10n, glassEnabled: Bool) -> some View {
        let hwCores = vm.hardwareCoreCount
        let autoWorkers = vm.autoWorkerCount
        let isAuto = vm.isMultiCoreAuto

        BoltGlassSectionCard(
            l.multiCoreTitle,
            icon: "bolt.horizontal.circle.fill",
            iconColor: .accentColor,
            glassEnabled: glassEnabled
        ) {
            BoltFormMenuRow(
                title: l.multiCoreCountLabel,
                subtitle: l.multiCoreBenefitSubtitle,
                selectedTitle: vm.multiCoreStatusSummary(l)
            ) {
                BoltMenuOptionButton(
                    title: l.multiCoreMenuAuto(autoWorkers),
                    isSelected: isAuto
                ) {
                    vm.setMultiCoreAuto(true)
                }

                Divider()

                ForEach(1...hwCores, id: \.self) { cores in
                    BoltMenuOptionButton(
                        title: l.multiCoreMenuCoreOption(cores, total: hwCores),
                        isSelected: !isAuto && vm.selectedManualCoreCount == cores
                    ) {
                        vm.selectedManualCoreCount = cores
                    }
                }
            }
        }

        BoltGlassSectionCard(
            l.settingsCodecsSection,
            icon: "cpu",
            iconColor: .accentColor,
            glassEnabled: glassEnabled,
            contentSpacing: 5
        ) {
            let engines = CompressionCodec.engineVersions()
            ForEach(Array(engines.enumerated()), id: \.element.id) { idx, info in
                if idx > 0 {
                    BoltSectionDivider(glassEnabled: glassEnabled)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name)
                            .font(BoltType.subbodyMedium)
                        Text(info.license)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    BoltReadOnlyBadge(text: shortEngineVersion(info.version))
                }
            }
        }
    }

    private func shortEngineVersion(_ raw: String) -> String {
        let head = raw.split(separator: ",").first.map(String.init) ?? raw
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
