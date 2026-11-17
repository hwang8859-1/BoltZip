import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?
    @State private var availableWidth: CGFloat = 720

    private var isNarrow: Bool { availableWidth < 540 }
    private var hasLowerCards: Bool { vm.showFeatureHighlights || vm.showRecentArchives }

    var body: some View {
        let l = vm.l10n
        Group {
            if hasLowerCards {
                ScrollView {
                    VStack(spacing: 10) {
                        if vm.showFinderBanner {
                            finderBanner(l: l)
                        }
                        heroDropZone(l: l, fillsSpace: false)
                        lowerCards(l: l)
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 10) {
                    if vm.showFinderBanner {
                        finderBanner(l: l)
                    }
                    heroDropZone(l: l, fillsSpace: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            availableWidth = newWidth
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
                        .font(.subheadline)
                        .foregroundStyle(vm.quickActionsInstalled ? .green : .cyan)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if !isNarrow {
                            Text(finderActionToast ?? l.finderBannerSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                            .font(.caption2.weight(.semibold))
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
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
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
                    isDropTargeted ? Color.cyan : Color.white.opacity(0.20),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.0, dash: [7, 5])
                )

            VStack(spacing: isNarrow ? 8 : 10) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.14))
                        .frame(width: isNarrow ? 44 : 52, height: isNarrow ? 44 : 52)
                        .glassEffect(.regular.tint(.cyan.opacity(0.16)), in: Circle())
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: isNarrow ? 20 : 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .indigo, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text(l.dropZoneTitle)
                    .font(isNarrow ? .headline : .title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if !isNarrow {
                    Text(l.dropZoneSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }

                GlassEffectContainer(spacing: 6) {
                    if isNarrow {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                            spacing: 6
                        ) {
                            actionButtons(l: l, fullWidth: true)
                        }
                        .frame(maxWidth: 300)
                    } else {
                        HStack(spacing: 8) {
                            actionButtons(l: l, fullWidth: false)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, isNarrow ? 14 : 18)
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, minHeight: fillsSpace ? 150 : 170, maxHeight: fillsSpace ? .infinity : nil)
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
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .controlSize(isNarrow ? .small : .regular)

        Button {
            vm.openArchivePanel()
        } label: {
            Label(l.openArchive, systemImage: "folder.badge.gearshape")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(isNarrow ? .small : .regular)

        Button {
            vm.activeSheet = .benchmark
        } label: {
            Label(l.benchmark, systemImage: "gauge.with.dots.needle.67percent")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(isNarrow ? .small : .regular)

        Button {
            vm.openShowcaseWebsite()
        } label: {
            Label(l.showcasePage, systemImage: "safari")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(isNarrow ? .small : .regular)
    }

    @ViewBuilder
    private func lowerCards(l: L10n) -> some View {
        let stackVertically = availableWidth < 660
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(l.featuresTitle, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showFeatureHighlights = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
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
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func recentsCard(l: L10n) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(l.recentsTitle, systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !vm.recentArchiveURLs.isEmpty {
                    Text(l.itemCount(vm.recentArchiveURLs.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showRecentArchives = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ForEach(vm.recentArchiveURLs.prefix(5), id: \.path) { url in
                    Button {
                        vm.openArchive(url: url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.zipper")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 7)
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
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.cyan)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
