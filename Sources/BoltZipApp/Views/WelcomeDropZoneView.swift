import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?

    var body: some View {
        let l = vm.l10n
        ScrollView {
            VStack(spacing: 12) {
                // Top Finder Right-Click Integration Liquid Glass Banner (dismissible!)
                if vm.showFinderBanner {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: vm.quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow")
                                .font(.body)
                                .foregroundStyle(vm.quickActionsInstalled ? .green : .cyan)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(finderActionToast ?? l.finderBannerSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

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

                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    vm.showFinderBanner = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(l.hideThisSection)
                            .padding(.leading, 4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .glassEffect(
                            .regular.tint((vm.quickActionsInstalled ? Color.green : Color.cyan).opacity(0.10)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }

                // Compact Hero Liquid Glass Drop Zone
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.cyan : Color.white.opacity(0.20),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.0, dash: [7, 5])
                        )

                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.14))
                                .frame(width: 56, height: 56)
                                .glassEffect(.regular.tint(.cyan.opacity(0.16)), in: Circle())
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, .indigo, .yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        Text(l.dropZoneTitle)
                            .font(.title3.weight(.semibold))

                        Text(l.dropZoneSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    vm.startNewArchivePanel()
                                } label: {
                                    Label(l.newArchive, systemImage: "plus.rectangle.on.folder.fill")
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.regular)

                                Button {
                                    vm.openArchivePanel()
                                } label: {
                                    Label(l.openArchive, systemImage: "folder.badge.gearshape")
                                }
                                .buttonStyle(.glass)
                                .controlSize(.regular)

                                Button {
                                    vm.activeSheet = .benchmark
                                } label: {
                                    Label(l.benchmark, systemImage: "gauge.with.dots.needle.67percent")
                                }
                                .buttonStyle(.glass)
                                .controlSize(.regular)

                                Button {
                                    vm.openShowcaseWebsite()
                                } label: {
                                    Label(l.showcasePage, systemImage: "safari")
                                }
                                .buttonStyle(.glass)
                                .controlSize(.regular)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 18)
                }
                .frame(minHeight: 185)
                .glassEffect(
                    .regular
                        .tint((isDropTargeted ? Color.cyan : Color.indigo).opacity(isDropTargeted ? 0.22 : 0.08))
                        .interactive(),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    DropHelper.extractFileURLs(from: providers) { urls in
                        vm.handleDroppedOrOpenedURLs(urls)
                    }
                }

                // Toggleable Feature Highlights & Recent Archives Cards
                if vm.showFeatureHighlights || vm.showRecentArchives {
                    HStack(alignment: .top, spacing: 12) {
                        if vm.showFeatureHighlights {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(l.featuresTitle, systemImage: "sparkles")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
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
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if vm.showRecentArchives {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(l.recentsTitle, systemImage: "clock.arrow.circlepath")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if !vm.recentArchiveURLs.isEmpty {
                                        Text(l.itemCount(vm.recentArchiveURLs.count))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
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
                                            .font(.title2)
                                            .foregroundStyle(.tertiary)
                                        Text(l.noRecents)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 120)
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
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.cyan)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
