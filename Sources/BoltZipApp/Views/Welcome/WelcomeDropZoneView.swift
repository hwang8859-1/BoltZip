import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

private struct FeaturesCardHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct WelcomeDropZoneView: View {
    @ObservedObject var vm: WorkspaceViewModel
    let titlebarHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?
    @State private var featuresCardHeight: CGFloat = 0

    var body: some View {
        let l = vm.l10n
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let topOffset = max(36, titlebarHeight)
            let isNarrow = w < 540
            let isCompactHeight = h < (topOffset + 345)
            let showBannerHere = vm.showFinderBanner && h >= (topOffset + 330)
            let showLowerCardsHere = (vm.showFeatureHighlights || vm.showRecentArchives) && h >= (topOffset + 390)
            let contentWidth = max(280, w - 24)

            ZStack(alignment: .top) {
                if showLowerCardsHere {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 10) {
                            if showBannerHere {
                                finderBanner(l: l, isNarrow: isNarrow)
                            }
                            heroDropZone(l: l, isNarrow: isNarrow, isCompactHeight: isCompactHeight, fillsSpace: false)
                            lowerCards(l: l, availableWidth: w)
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .padding(.horizontal, 12)
                        .padding(.top, topOffset + 4)
                        .padding(.bottom, 12)
                    }
                    .boltScrollTopMargin(topOffset, includeContent: false)
                    .boltSoftTopScrollEdgeEffect()
                    .frame(width: w, height: h)
                } else {
                    VStack(spacing: 10) {
                        if showBannerHere {
                            finderBanner(l: l, isNarrow: isNarrow)
                        }
                        heroDropZone(l: l, isNarrow: isNarrow, isCompactHeight: isCompactHeight, fillsSpace: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, topOffset + 4)
                    .padding(.bottom, 12)
                    .frame(width: w, height: h)
                }

                titlebarGlassOverlay(width: w, height: topOffset)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }

    @ViewBuilder
    private func titlebarGlassOverlay(width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .boltWithinWindowGlassCover(glassEnabled: vm.effectiveWindowTranslucency, dividerEdge: .bottom)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func finderBanner(l: L10n, isNarrow: Bool) -> some View {
        let accent: Color = vm.quickActionsInstalled ? .green : .orange
        BoltGlassContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: vm.quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow")
                        .font(BoltType.windowTitle)
                        .foregroundStyle(vm.quickActionsInstalled ? .green : .cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle)
                            .font(BoltType.subbodyMedium)
                            .fixedSize(horizontal: false, vertical: true)
                        if !isNarrow {
                            Text(finderActionToast ?? l.finderBannerSubtitle)
                                .font(BoltType.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 4)

                    if !isNarrow {
                        bannerButtons(l: l)
                    }

                    BoltCloseIconButton(helpText: l.hideThisSection) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            vm.showFinderBanner = false
                        }
                    }
                }

                if isNarrow {
                    HStack(spacing: 6) {
                        bannerButtons(l: l)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                accent.opacity(0.13),
                in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
            )
            .boltGlassSurface(
                .regular,
                tint: accent.opacity(0.22),
                in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
                    .strokeBorder(accent.opacity(0.26), lineWidth: 0.75)
            )
        }
    }

    @ViewBuilder
    private func bannerButtons(l: L10n) -> some View {
        Button(l.extensionSettings) {
            vm.openFinderExtensionSettings()
        }
        .boltGlassButton()
        .controlSize(.small)

        if vm.quickActionsInstalled {
            Button(l.resync) {
                finderActionToast = vm.installFinderQuickActions()
            }
            .boltGlassButton()
            .controlSize(.small)
        } else {
            Button(l.enableBoltMenu) {
                finderActionToast = vm.installFinderQuickActions()
            }
            .boltGlassProminentButton()
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func heroDropZone(l: L10n, isNarrow: Bool, isCompactHeight: Bool, fillsSpace: Bool) -> some View {
        let isDark = colorScheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.cyan : Color.primary.opacity(isDark ? 0.14 : 0.10),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.0, dash: [7, 5])
                )

            VStack(spacing: isCompactHeight ? 7 : 10) {
                BoltLogoBadge(
                    size: isCompactHeight ? 42 : 52,
                    whiteBackground: vm.useWhiteAppIcon
                )

                Text(l.dropZoneTitle)
                    .font(BoltType.heroTitle(compact: isNarrow))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)

                if !isCompactHeight {
                    Text(l.dropZoneSubtitle)
                        .font(BoltType.subbody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                }

                BoltGlassContainer(spacing: 7) {
                    if isNarrow {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                            spacing: 7
                        ) {
                            actionButtons(l: l, fullWidth: true)
                        }
                        .frame(maxWidth: 320)
                    } else {
                        HStack(spacing: 8) {
                            actionButtons(l: l, fullWidth: false)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, isCompactHeight ? 10 : 16)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: fillsSpace ? 155 : 165, maxHeight: fillsSpace ? .infinity : nil)
        .boltLayeredSurface(
            glassEnabled: vm.effectiveWindowTranslucency,
            tone: .regular,
            tint: isDropTargeted ? Color.cyan.opacity(0.18) : nil,
            interactive: true,
            in: RoundedRectangle(cornerRadius: BoltRadius.hero, style: .continuous)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            DropHelper.extractFileURLs(from: providers) { urls in
                vm.handleDroppedOrOpenedURLs(urls)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(l: L10n, fullWidth: Bool) -> some View {
        Button {
            vm.startNewArchivePanel()
        } label: {
            Label(l.newArchive, systemImage: "plus.rectangle.on.folder.fill")
                .font(BoltType.subbodyMedium)
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .boltGlassProminentButton()
        .controlSize(.regular)

        Button {
            vm.openArchivePanel()
        } label: {
            Label(l.openArchive, systemImage: "folder.badge.gearshape")
                .font(BoltType.subbodyMedium)
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .boltGlassButton()
        .controlSize(.regular)

        Button {
            vm.activeSheet = .benchmark
        } label: {
            Label(l.benchmark, systemImage: "gauge.with.dots.needle.67percent")
                .font(BoltType.subbodyMedium)
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .boltGlassButton()
        .controlSize(.regular)

        Button {
            vm.openShowcaseWebsite()
        } label: {
            Label(l.showcasePage, systemImage: "safari")
                .font(BoltType.subbodyMedium)
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .boltGlassButton()
        .controlSize(.regular)
    }

    @ViewBuilder
    private func lowerCards(l: L10n, availableWidth: CGFloat) -> some View {
        let stackVertically = availableWidth < 660
        let matchedRecentsHeight: CGFloat? = (!stackVertically && vm.showFeatureHighlights && featuresCardHeight > 120)
            ? featuresCardHeight
            : nil

        Group {
            if stackVertically {
                VStack(spacing: 10) {
                    if vm.showFeatureHighlights { featuresCard(l: l) }
                    if vm.showRecentArchives { recentsCard(l: l, matchedHeight: nil) }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if vm.showFeatureHighlights { featuresCard(l: l) }
                    if vm.showRecentArchives { recentsCard(l: l, matchedHeight: matchedRecentsHeight) }
                }
            }
        }
        .onPreferenceChange(FeaturesCardHeightKey.self) { height in
            if abs(featuresCardHeight - height) > 0.5 {
                featuresCardHeight = height
            }
        }
    }

    @ViewBuilder
    private func featuresCard(l: L10n) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.featuresTitle, systemImage: "sparkles")
                    .font(BoltType.sectionTitle)
                Spacer()
                BoltCloseIconButton(helpText: l.hideThisSection) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showFeatureHighlights = false
                    }
                }
            }

            FeatureRow(icon: "folder.fill.badge.plus", title: l.featBrowseTitle, detail: l.featBrowseDesc)
            FeatureRow(icon: "wand.and.stars", title: l.featSmartTitle, detail: l.featSmartDesc)
            FeatureRow(icon: "trash.slash.fill", title: l.featMacJunkTitle, detail: l.featMacJunkDesc)
            FeatureRow(icon: "character.book.closed.fill", title: l.featEncodingTitle, detail: l.featEncodingDesc)
            FeatureRow(icon: "lock.shield.fill", title: l.featCryptoTitle, detail: l.featCryptoDesc)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FeaturesCardHeightKey.self, value: geo.size.height)
            }
        )
        .boltLayeredSurface(
            glassEnabled: vm.effectiveWindowTranslucency,
            tone: .regular,
            in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private func recentsCard(l: L10n, matchedHeight: CGFloat?) -> some View {
        let recents = vm.recentArchiveURLs
        let fallbackMaxHeight: CGFloat? = (matchedHeight == nil && recents.count > 4) ? 260 : nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(l.recentsTitle, systemImage: "clock.arrow.circlepath")
                    .font(BoltType.sectionTitle)
                    .lineLimit(1)
                Spacer()
                if !recents.isEmpty {
                    Text(l.itemCount(recents.count))
                        .font(BoltType.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                BoltCloseIconButton(helpText: l.hideThisSection) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showRecentArchives = false
                    }
                }
            }

            if recents.isEmpty {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(systemName: "archivebox")
                        .font(BoltType.heroTitle(compact: false))
                        .foregroundStyle(.tertiary)
                    Text(l.noRecents)
                        .font(BoltType.subbody)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 88, maxHeight: matchedHeight != nil ? .infinity : nil)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(recents, id: \.path) { url in
                            RecentArchiveRow(vm: vm, url: url, l: l)
                        }
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: matchedHeight != nil ? .infinity : fallbackMaxHeight)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: matchedHeight)
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
