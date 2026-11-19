import AppKit
import BoltZipCore
import SwiftUI

struct AboutView: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? BoltZipVersion.current

        VStack(spacing: 12) {
            BoltLogoBadge(
                size: 64,
                whiteBackground: vm.effectiveWhiteAppIcon(for: colorScheme),
                glassEnabled: glassEnabled
            )

            VStack(spacing: 4) {
                Text("BoltZip")
                    .font(BoltType.displayTitle)
                Text(BoltPlatformCapabilities.runtimeVersionSummary(appVersion: appVersion))
                    .font(BoltType.monoCaption)
                    .foregroundStyle(.secondary)
            }

            Text(l.slogan)
                .font(BoltType.sectionTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )

            Text(l.aboutDesc)
                .font(BoltType.subbody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                Text(l.openSourceEnginesLine)
                    .font(BoltType.monoCaption)
                    .foregroundStyle(.secondary)
                Text(l.copyrightLine)
                    .font(BoltType.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)

            Button {
                dismiss()
                vm.onRequestShowMainWindow?()
                vm.activeSheet = .benchmark
            } label: {
                Label(l.benchmark, systemImage: "gauge.with.dots.needle.67percent")
            }
            .buttonStyle(.link)

            BoltGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        if let url = URL(string: "https://github.com/hwang8859-1/BoltZip") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(l.openGitHub, systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .boltGlassProminentButton()

                    Button {
                        vm.openShowcaseWebsite()
                    } label: {
                        Label(l.showcasePage, systemImage: "safari")
                    }
                    .boltGlassButton()

                    Button {
                        dismiss()
                        vm.onRequestShowMainWindow?()
                        vm.checkForUpdates(userInitiated: true)
                    } label: {
                        Label(l.checkForUpdatesBtn, systemImage: "arrow.triangle.2.circlepath")
                    }
                    .boltGlassButton()

                    Button(l.close) {
                        NSApp.keyWindow?.performClose(nil)
                        dismiss()
                    }
                    .boltGlassButton()
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(18)
        .frame(width: 440)
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
    }
}
