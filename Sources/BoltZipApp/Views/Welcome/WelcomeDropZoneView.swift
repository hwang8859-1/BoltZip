import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    let titlebarHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let l = vm.l10n
        GeometryReader { geometry in
            let topBarHeight = max(42, titlebarHeight)
            let contentHeight = max(0, geometry.size.height - topBarHeight)
            let compact = contentHeight < 310
            let cardInset: CGFloat = 16
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !compact && vm.showFinderBanner {
                        finderBanner(l: l)
                    }
                    dropCard(l: l, minHeight: compact ? max(0, contentHeight - 2 * cardInset) : nil)
                    if !compact {
                        sections(l: l, wide: geometry.size.width >= 660)
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, cardInset)
                .padding(.vertical, compact ? cardInset : 12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                DropHelper.extractFileURLs(from: providers) { urls in
                    vm.handleDroppedOrOpenedURLs(urls)
                }
            }
            .boltTitlebarScrollEdgeBar(
                height: topBarHeight,
                glassEnabled: vm.effectiveWindowTranslucency
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { vm.refreshQuickActionsStatus() }
    }

    private func hideButton(_ label: String, action: @escaping () -> Void) -> some View {
        BoltCloseIconButton(helpText: label, boxSize: 24) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                action()
            }
        }
    }

    private func dropCard(l: L10n, minHeight: CGFloat?) -> some View {
        let shape = RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous)
        return VStack(spacing: 12) {
            BoltLogoBadge(size: 48, whiteBackground: vm.effectiveWhiteAppIcon(for: colorScheme),
                          glassEnabled: vm.effectiveWindowTranslucency)
                .accessibilityHidden(true)

            Text(l.dropZoneTitle)
                .font(BoltType.sectionTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { archiveButtons(l: l) }
                VStack(spacing: 6) { archiveButtons(l: l) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, minHeight == nil ? 18 : 14)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background {
            shape.fill(
                RadialGradient(colors: [.cyan.opacity(colorScheme == .dark ? 0.12 : 0.08), .clear],
                               center: .top, startRadius: 12, endRadius: 235)
            )
            .allowsHitTesting(false)
        }
        .boltLayeredSurface(glassEnabled: vm.effectiveWindowTranslucency, tone: .regular, in: shape)
        .overlay {
            shape.strokeBorder(
                isDropTargeted ? Color.cyan : Color.primary.opacity(0.16),
                style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5, 4])
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func archiveButtons(l: L10n) -> some View {
        Button {
            vm.openArchivePanel()
        } label: {
            Label(l.openArchive, systemImage: "folder")
        }
        .boltGlassProminentButton()

        Button {
            vm.startNewArchivePanel()
        } label: {
            Label(l.newArchive, systemImage: "plus.rectangle.on.folder")
        }
        .boltGlassButton()
    }

    private func finderBanner(l: L10n) -> some View {
        HStack(spacing: 8) {
            Image(systemName: vm.quickActionsInstalled ? "checkmark.circle" : "contextualmenu.and.cursorarrow")
                .foregroundStyle(vm.quickActionsInstalled ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(finderActionToast ?? (vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle))
                .font(BoltType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !vm.quickActionsInstalled {
                Button(l.enableBoltMenu) { finderActionToast = vm.installFinderQuickActions() }
                    .controlSize(.small)
                    .boltGlassButton()
            }
            hideButton(l.hideThisSection) { vm.showFinderBanner = false }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sections(l: L10n, wide: Bool) -> some View {
        if wide && vm.showRecentArchives && vm.showFeatureHighlights {
            HStack(alignment: .top, spacing: 12) {
                recentsCard(l: l)
                featuresCard(l: l)
                    .frame(maxWidth: 310)
            }
        } else {
            if vm.showRecentArchives { recentsCard(l: l) }
            if vm.showFeatureHighlights { featuresCard(l: l) }
        }
    }

    @ViewBuilder
    private func featuresCard(l: L10n) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.featuresTitle, systemImage: "sparkles")
                    .font(BoltType.sectionTitle)
                Spacer()
                hideButton(l.hideThisSection) { vm.showFeatureHighlights = false }
            }

            FeatureRow(icon: "archivebox", title: l.featFormatsTitle, detail: l.featFormatsDesc)
            FeatureRow(icon: "folder.fill.badge.plus", title: l.featBrowseTitle, detail: l.featBrowseDesc)
            FeatureRow(icon: "wand.and.stars", title: l.featSmartTitle, detail: l.featSmartDesc)
            FeatureRow(icon: "trash.slash.fill", title: l.featMacJunkTitle, detail: l.featMacJunkDesc)
            FeatureRow(icon: "character.book.closed.fill", title: l.featEncodingTitle, detail: l.featEncodingDesc)
            FeatureRow(icon: "lock.shield.fill", title: l.featCryptoTitle, detail: l.featCryptoDesc)
            FeatureRow(icon: "sparkle", title: l.featGlassTitle, detail: l.featGlassDesc)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boltLayeredSurface(
            glassEnabled: vm.effectiveWindowTranslucency,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

    private func recentsCard(l: L10n) -> some View {
        let recents = vm.recentArchiveURLs

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(l.recentsTitle, systemImage: "clock")
                    .font(BoltType.sectionTitle)
                Spacer()
                if !recents.isEmpty {
                    Button(l.clearRecentsBtn) { vm.clearRecents() }
                        .controlSize(.small)
                        .boltGlassButton()
                }
                hideButton(l.hideThisSection) { vm.showRecentArchives = false }
            }

            if recents.isEmpty {
                Text(l.noRecents)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 3) {
                    ForEach(recents, id: \.path) { url in
                        RecentArchiveRow(vm: vm, url: url, l: l)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .boltLayeredSurface(
            glassEnabled: vm.effectiveWindowTranslucency,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(BoltType.body)
                .foregroundStyle(.cyan)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BoltType.subbodyMedium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(BoltType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
