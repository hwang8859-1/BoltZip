import BoltZipCore
import SwiftUI

struct SettingsView: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case general
        case appearance
        case codecs

        var id: Int { rawValue }
    }

    @ObservedObject var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .general
    @State private var feedbackMessage: String?
    @State private var associationFeedback: (text: String, isError: Bool)?

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

            BoltGlassContainer(spacing: 10) {
                HStack {
                    Text(BoltPlatformCapabilities.runtimeVersionSummary(
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.1"
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
                .padding(.horizontal, BoltMetrics.cardFooterHPad)
                .padding(.vertical, BoltMetrics.cardFooterVPad)
                .boltLayeredSurface(
                    glassEnabled: glassEnabled,
                    tone: .regular,
                    in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
                )
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
        .boltWindowContainerBackground(
            glassEnabled ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        )
        .boltWindowToolbarBackgroundVisibility(glassEnabled ? .hidden : .automatic)
        .preferredColorScheme(vm.appTheme.colorScheme)
        .onAppear {
            vm.refreshQuickActionsStatus()
            vm.refreshArchiveAssociations()
        }
    }

    @ViewBuilder
    private func tabPill(tab: Tab, title: String, icon: String, glassEnabled: Bool) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            Label(title, systemImage: icon)
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

    @ViewBuilder
    private func generalTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.settingsTabGeneral, icon: "gearshape.fill", glassEnabled: glassEnabled) {
            Toggle(l.stripMacJunkToggle, isOn: Binding(
                get: { vm.defaultStripMacJunk },
                set: { vm.updateDefaultStripMacJunk($0) }
            ))

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack {
                Text(l.defaultEncodingLabel)
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.encodingOption },
                    set: { vm.encodingOption = $0 }
                )) {
                    ForEach(FilenameEncodingOption.allCases) { enc in
                        Text(l.encodingTitle(enc)).tag(enc)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: BoltMetrics.pickerWidth)
            }
        }

        BoltGlassSectionCard(l.finderIntegrationSection, icon: "contextualmenu.and.cursorarrow", glassEnabled: glassEnabled) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.quickActionsInstalled ? l.finderEnabledSummary : l.finderDisabledSummary)
                            .font(BoltType.subbodyMedium)
                        Text(l.finderBannerSubtitle)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                            feedbackMessage = l.finderDisabledSummary
                        }
                        .controlSize(.small)
                        .boltGlassButton()
                    }
                }
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

        BoltGlassSectionCard(l.defaultAssociationsSection, icon: "doc.badge.gearshape.fill", glassEnabled: glassEnabled) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.defaultAssociationsSummary(activeCommonCount, commonGroups.count))
                            .font(BoltType.subbodyMedium)
                        Text(l.defaultAssociationsSubtitle)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
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
                }

                if let associationFeedback {
                    Text(associationFeedback.text)
                        .font(BoltType.caption)
                        .foregroundStyle(associationFeedback.isError ? .red : .green)
                }
            }

            if !statuses.isEmpty {
                BoltSectionDivider(glassEnabled: glassEnabled)

                VStack(spacing: 6) {
                    ForEach(Array(statuses.enumerated()), id: \.element.id) { idx, status in
                        if idx > 0 {
                            BoltSectionDivider(glassEnabled: glassEnabled)
                        }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.associationGroupTitle(status.group))
                                    .font(BoltType.subbodyMedium)
                                Text(status.group.extensionsSubtitle)
                                    .font(BoltType.monoCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(status.isBoltZipDefault ? l.alreadyDefaultBadge : status.currentAppName)
                                .font(BoltType.caption)
                                .foregroundStyle(status.isBoltZipDefault ? Color.cyan : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .boltLayeredSurface(
                                    glassEnabled: glassEnabled,
                                    tone: .regular,
                                    tint: status.isBoltZipDefault ? .cyan.opacity(0.14) : nil,
                                    in: Capsule()
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

    @ViewBuilder
    private func appearanceTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.languageLabel, icon: "globe", glassEnabled: glassEnabled) {
            HStack {
                Text(l.languageLabel)
                Spacer()
                Picker("", selection: $vm.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativePickerTitle).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: BoltMetrics.pickerWidth)
            }
        }

        BoltGlassSectionCard(l.appearanceTitle, icon: "sparkles", glassEnabled: glassEnabled) {
            HStack {
                Text(l.themeLabel)
                Spacer()
                Picker("", selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(l)).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: BoltMetrics.pickerWidth)
            }

            BoltSectionDivider(glassEnabled: glassEnabled)

            HStack(spacing: 8) {
                Text(l.backgroundColorLabel)
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

            HStack(spacing: 8) {
                Image(nsImage: BoltAppIconRenderer.appIconImage(whiteBackground: vm.useWhiteAppIcon, size: 28))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Toggle(l.whiteAppIconToggle, isOn: $vm.useWhiteAppIcon)
            }

            if vm.supportsLiquidGlass {
                BoltSectionDivider(glassEnabled: glassEnabled)
                Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
                if vm.isWindowTranslucent {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text("\(l.glassIntensityLabel): \(Int((vm.glassIntensity * 100).rounded()))%")
                                .monospacedDigit()
                                .lineLimit(1)
                                .frame(width: 164, alignment: .leading)
                            Slider(value: $vm.glassIntensity, in: 0.0...1.0, step: 0.05)
                        }
                        HStack {
                            Spacer().frame(width: 174)
                            Text(l.glassSoftLabel)
                            Spacer()
                            Text(l.glassStrongLabel)
                        }
                        .font(BoltType.badge)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }

        BoltGlassSectionCard(l.visibleSectionsTitle, icon: "rectangle.3.group", glassEnabled: glassEnabled) {
            Toggle(l.toggleFinderBanner, isOn: $vm.showFinderBanner)
            BoltSectionDivider(glassEnabled: glassEnabled)
            Toggle(l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
            BoltSectionDivider(glassEnabled: glassEnabled)
            Toggle(l.toggleRecentsCard, isOn: $vm.showRecentArchives)
            BoltSectionDivider(glassEnabled: glassEnabled)
            Toggle(l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
            BoltSectionDivider(glassEnabled: glassEnabled)
            Toggle(l.toggleStatusBar, isOn: $vm.showStatusBar)
        }
    }

    @ViewBuilder
    private func codecsTabContent(l: L10n, glassEnabled: Bool) -> some View {
        BoltGlassSectionCard(l.multiCoreTitle, icon: "bolt.horizontal.circle.fill", glassEnabled: glassEnabled) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.multiCoreTitle)
                        .font(BoltType.subbodyMedium)
                    Text(l.multiCoreSubtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(l.multiCoreBadge(CompressionCodec.activeCoreCount))
                    .font(BoltType.monoCaption)
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .boltLayeredSurface(
                        glassEnabled: glassEnabled,
                        tone: .regular,
                        tint: .cyan.opacity(0.16),
                        in: Capsule()
                    )
            }
        }

        BoltGlassSectionCard(l.settingsTabCodecs, icon: "cpu", glassEnabled: glassEnabled) {
            let engines = CompressionCodec.engineVersions()
            ForEach(Array(engines.enumerated()), id: \.element.id) { idx, info in
                if idx > 0 {
                    BoltSectionDivider(glassEnabled: glassEnabled)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(BoltType.subbodyMedium)
                        Text(info.license)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(info.version)
                        .font(BoltType.monoCaption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .boltLayeredSurface(
                            glassEnabled: glassEnabled,
                            tone: .regular,
                            tint: .cyan.opacity(0.14),
                            in: Capsule()
                        )
                }
            }
        }
    }
}
