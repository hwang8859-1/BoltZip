import SwiftUI

struct AppearancePopoverView: View {
    @Bindable var vm: WorkspaceViewModel

    var body: some View {
        let l = vm.l10n
        VStack(alignment: .leading, spacing: 11) {
            Text(l.appearanceTitle)
                .font(.headline)

            // Dark / Light / System Theme Switcher
            VStack(alignment: .leading, spacing: 4) {
                Text(l.themeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(l)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Language Switcher
            VStack(alignment: .leading, spacing: 4) {
                Text(l.languageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $vm.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativePickerTitle).tag(lang)
                    }
                }
                .labelsHidden()
            }

            if vm.supportsLiquidGlass {
                Divider()

                // Translucency & Opacity Control
                Toggle(l.enableTranslucency, isOn: $vm.isWindowTranslucent)
                    .font(.callout)

                if vm.isWindowTranslucent {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(l.opacityLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((vm.windowBackgroundOpacity * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $vm.windowBackgroundOpacity, in: 0.25...1.0, step: 0.05)
                    }
                }
            }

            Divider()

            // Modular Panel Toggles
            Text(l.visibleSectionsTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(l.toggleFinderBanner, isOn: $vm.showFinderBanner)
                Toggle(l.toggleFeatureCard, isOn: $vm.showFeatureHighlights)
                Toggle(l.toggleRecentsCard, isOn: $vm.showRecentArchives)
                Toggle(l.toggleSidebarInspector, isOn: $vm.showSidebarInspector)
                Toggle(l.toggleStatusBar, isOn: $vm.showStatusBar)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 310)
    }
}
