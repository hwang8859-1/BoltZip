import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?
    @State private var containerSize: CGSize = CGSize(width: 720, height: 460)

    private var isNarrow: Bool { containerSize.width < 540 }
    private var isCompactHeight: Bool { containerSize.height < 350 }
    private var showBannerHere: Bool { vm.showFinderBanner && containerSize.height >= 330 }
    private var showLowerCardsHere: Bool { (vm.showFeatureHighlights || vm.showRecentArchives) && containerSize.height >= 390 }

    var body: some View {
        let l = vm.l10n
        Group {
            if showLowerCardsHere {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        if showBannerHere {
                            finderBanner(l: l)
                        }
                        heroDropZone(l: l, fillsSpace: false)
                        lowerCards(l: l)
                    }
                    .padding(12)
                    .frame(width: max(300, containerSize.width), alignment: .top)
                }
            } else {
                // Compact / Minimal height mode: only keep the main interface, zero overflow
                VStack(spacing: 10) {
                    if showBannerHere {
                        finderBanner(l: l)
                    }
                    heroDropZone(l: l, fillsSpace: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            containerSize = newSize
        }
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }

    @ViewBuilder
    private func finderBanner(l: L10n) -> some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: vm.quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow")
                        .font(.system(size: 14))
                        .foregroundStyle(vm.quickActionsInstalled ? .green : .cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        if !isNarrow {
                            Text(finderActionToast ?? l.finderBannerSubtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 4)

                    if !isNarrow {
                        bannerButtons(l: l)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            vm.showFinderBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l.hideThisSection)
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
            .glassEffect(
                .regular.tint((vm.quickActionsInstalled ? Color.green : Color.cyan).opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func bannerButtons(l: L10n) -> some View {
        Button(l.extensionSettings) {
            vm.openFinderExtensionSettings()
        }
        .buttonStyle(.glass)
        .controlSize(.small)

        if vm.quickActionsInstalled {
            Button(l.resync) {
                finderActionToast = vm.installFinderQuickActions()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        } else {
            Button(l.enableBoltMenu) {
                finderActionToast = vm.installFinderQuickActions()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func heroDropZone(l: L10n, fillsSpace: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.cyan : Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.0, dash: [7, 5])
                )

            VStack(spacing: isCompactHeight ? 7 : 10) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.14))
                        .frame(width: isCompactHeight ? 42 : 52, height: isCompactHeight ? 42 : 52)
                        .glassEffect(.regular.tint(.cyan.opacity(0.16)), in: Circle())
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: isCompactHeight ? 19 : 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .indigo, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text(l.dropZoneTitle)
                    .font(.system(size: isNarrow ? 15.5 : 18.5, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)

                if !isCompactHeight {
                    Text(l.dropZoneSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                }

                GlassEffectContainer(spacing: 7) {
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
        .glassEffect(
            .regular
                .tint((isDropTargeted ? Color.cyan : Color.indigo).opacity(isDropTargeted ? 0.22 : 0.08))
                .interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .controlSize(isNarrow ? .regular : .regular)

        Button {
            vm.openArchivePanel()
        } label: {
            Label(l.openArchive, systemImage: "folder.badge.gearshape")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)

        Button {
            vm.activeSheet = .benchmark
        } label: {
            Label(l.benchmark, systemImage: "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)

        Button {
            vm.openShowcaseWebsite()
        } label: {
            Label(l.showcasePage, systemImage: "safari")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }

    @ViewBuilder
    private func lowerCards(l: L10n) -> some View {
        let stackVertically = containerSize.width < 660
        if stackVertically {
            VStack(spacing: 10) {
                if vm.showFeatureHighlights { featuresCard(l: l) }
                if vm.showRecentArchives { recentsCard(l: l) }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                if vm.showFeatureHighlights { featuresCard(l: l) }
                if vm.showRecentArchives { recentsCard(l: l) }
            }
        }
    }

    @ViewBuilder
    private func featuresCard(l: L10n) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.featuresTitle, systemImage: "sparkles")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showFeatureHighlights = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l.hideThisSection)
            }

            FeatureRow(icon: "folder.fill.badge.plus", title: l.featBrowseTitle, detail: l.featBrowseDesc)
            FeatureRow(icon: "wand.and.stars", title: l.featSmartTitle, detail: l.featSmartDesc)
            FeatureRow(icon: "character.book.closed.fill", title: l.featEncodingTitle, detail: l.featEncodingDesc)
            FeatureRow(icon: "lock.shield.fill", title: l.featCryptoTitle, detail: l.featCryptoDesc)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func recentsCard(l: L10n) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.recentsTitle, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Spacer()
                if !vm.recentArchiveURLs.isEmpty {
                    Text(l.itemCount(vm.recentArchiveURLs.count))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showRecentArchives = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l.hideThisSection)
            }

            if vm.recentArchiveURLs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(l.noRecents)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                ForEach(vm.recentArchiveURLs.prefix(5), id: \.path) { url in
                    Button {
                        vm.openArchive(url: url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 13))
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contextMenu {
                        Button(l.ctxOpenBrowse) { vm.openArchive(url: url) }
                        Divider()
                        Button(l.ctxSmartExtractAll) { vm.quickExtract(mode: .smart, archiveURL: url) }
                        Button(l.ctxExtractAllSubfolder) { vm.quickExtract(mode: .subfolder, archiveURL: url) }
                        Button(l.ctxVerifyArchive) { vm.testIntegrity(archiveURL: url) }
                        Divider()
                        Button(l.ctxShowInFinder) { vm.showInFinder(url) }
                        Button(l.ctxRemoveRecent, role: .destructive) { vm.removeRecent(url) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.cyan)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
