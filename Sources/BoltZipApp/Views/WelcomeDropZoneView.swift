import AppKit
import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    let titlebarHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?

    var body: some View {
        let l = vm.l10n
        let glassEnabled = vm.effectiveWindowTranslucency

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. FinderSync Extension Quick Action Banner
                if vm.showFinderBanner {
                    finderBanner(l: l, glassEnabled: glassEnabled)
                }

                // 2. Focused Hero Drop Zone
                heroDropZone(l: l, glassEnabled: glassEnabled)

                // 3. Recent Archives (if enabled)
                if vm.showRecentArchives {
                    recentsCard(l: l, glassEnabled: glassEnabled)
                }

                // 4. Subtle Footnote (Clean Packing & Integration info)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("打包与解压默认净化 .DS_Store 及 __MACOSX 资源叉")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.refreshQuickActionsStatus()
        }
    }

    // MARK: - Finder Banner
    @ViewBuilder
    private func finderBanner(l: L10n, glassEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vm.quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow")
                .font(.system(size: 15))
                .foregroundStyle(vm.quickActionsInstalled ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(vm.quickActionsInstalled ? l.finderBannerEnabledTitle : l.finderBannerDisabledTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(finderActionToast ?? l.finderBannerSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(l.extensionSettings) {
                vm.openFinderExtensionSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if vm.quickActionsInstalled {
                Button(l.resync) {
                    finderActionToast = vm.installFinderQuickActions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(l.enableBoltMenu) {
                    finderActionToast = vm.installFinderQuickActions()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    vm.showFinderBanner = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(l.hideThisSection)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Hero Drop Zone
    @ViewBuilder
    private func heroDropZone(l: L10n, glassEnabled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.2, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
                )

            VStack(spacing: 14) {
                BoltLogoBadge(size: 54)

                VStack(spacing: 4) {
                    Text(l.dropZoneTitle)
                        .font(.system(size: 17, weight: .semibold))

                    Text(l.dropZoneSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    Button {
                        vm.startNewArchivePanel()
                    } label: {
                        Label(l.newArchive, systemImage: "plus.rectangle.on.folder.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button {
                        vm.openArchivePanel()
                    } label: {
                        Label(l.openArchive, systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
        }
        .frame(minHeight: 200)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            DropHelper.extractFileURLs(from: providers) { urls in
                vm.handleDroppedOrOpenedURLs(urls)
            }
        }
    }

    // MARK: - Recent Archives Card
    @ViewBuilder
    private func recentsCard(l: L10n, glassEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l.recentsTitle, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.recentArchiveURLs.isEmpty {
                    Text(l.itemCount(vm.recentArchiveURLs.count))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        vm.showRecentArchives = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(l.hideThisSection)
            }
            .padding(.horizontal, 4)

            if vm.recentArchiveURLs.isEmpty {
                VStack(spacing: 4) {
                    Text(l.noRecents)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 1) {
                    ForEach(vm.recentArchiveURLs.prefix(5), id: \.path) { url in
                        Button {
                            vm.openArchive(url: url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.0001)) // hit target
                        )
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
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                )
            }
        }
    }
}
