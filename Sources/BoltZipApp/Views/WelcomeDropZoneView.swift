import BoltZipCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeDropZoneView: View {
    @Bindable var vm: WorkspaceViewModel
    @State private var isDropTargeted = false
    @State private var finderActionToast: String?

    var body: some View {
        ZStack {
            BoltAmbientBackdrop()

            ScrollView {
                VStack(spacing: 22) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: vm.quickActionsInstalled ? "checkmark.circle.fill" : "contextualmenu.and.cursorarrow")
                                .font(.title3)
                                .foregroundStyle(vm.quickActionsInstalled ? .green : .cyan)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.quickActionsInstalled ? "访达一级右键目录「Bolt >」已启用" : "将高频功能添加到访达右键一级目录「Bolt >」")
                                    .font(.subheadline.weight(.semibold))
                                Text(finderActionToast ?? "直接显示在右键顶层：智能解压 · 解压到文件夹 · 压缩 ZIP / TAR.ZST / 7z · 加密打包")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("扩展设置") {
                                vm.openFinderExtensionSettings()
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)

                            if vm.quickActionsInstalled {
                                Button("重新同步") {
                                    finderActionToast = vm.installFinderQuickActions()
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            } else {
                                Button("一键启用 Bolt 菜单") {
                                    finderActionToast = vm.installFinderQuickActions()
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(
                            .regular.tint((vm.quickActionsInstalled ? Color.green : Color.cyan).opacity(0.10)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.cyan : Color.white.opacity(0.22),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.2, dash: [8, 6])
                            )

                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.cyan.opacity(0.14))
                                    .frame(width: 78, height: 78)
                                    .glassEffect(.regular.tint(.cyan.opacity(0.16)), in: Circle())
                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.cyan, .indigo, .yellow],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            Text("拖放压缩包直接浏览，或拖入文件立即打包")
                                .font(.title2.weight(.semibold))

                            Text("macOS 27.3 液态玻璃原生体验 · 支持 ZIP / 7z / TAR.ZST / TAR.XZ / TAR.GZ / LZ4 · AE-2 AES-256 与 GBK 自动纠偏")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            GlassEffectContainer(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        vm.startNewArchivePanel()
                                    } label: {
                                        Label("新建压缩包", systemImage: "plus.rectangle.on.folder.fill")
                                            .padding(.horizontal, 6)
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.large)

                                    Button {
                                        vm.openArchivePanel()
                                    } label: {
                                        Label("打开压缩包", systemImage: "folder.badge.gearshape")
                                            .padding(.horizontal, 4)
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.large)

                                    Button {
                                        vm.activeSheet = .benchmark
                                    } label: {
                                        Label("算法跑分", systemImage: "gauge.with.dots.needle.67percent")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.large)

                                    Button {
                                        vm.openShowcaseWebsite()
                                    } label: {
                                        Label("展示页面", systemImage: "safari")
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.large)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 34)
                        .padding(.horizontal, 24)
                    }
                    .frame(minHeight: 270)
                    .glassEffect(
                        .regular
                            .tint((isDropTargeted ? Color.cyan : Color.indigo).opacity(isDropTargeted ? 0.22 : 0.08))
                            .interactive(),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        DropHelper.extractFileURLs(from: providers) { urls in
                            vm.handleDroppedOrOpenedURLs(urls)
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Windows Zip 经典能力全覆盖", systemImage: "sparkles")
                                .font(.headline)

                            FeatureRow(icon: "folder.fill.badge.plus", title: "包内直览 & 右键全菜单", detail: "双击/空格预览，右键直接解压、单独导出 ZIP、重命名与删改")
                            FeatureRow(icon: "wand.and.stars", title: "智能解压 (Smart Extract)", detail: "单目录不套娃，多文件自动归入同名子目录")
                            FeatureRow(icon: "character.book.closed.fill", title: "Windows GBK 自动修复", detail: "自动识别 CP936/GB18030 中文文件名，告别乱码")
                            FeatureRow(icon: "lock.shield.fill", title: "WinZip AE-2 AES-256 & 分卷", detail: "高强度加密与 .z01 分卷跨平台完美互通")
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("最近打开的归档（右键支持快捷操作）", systemImage: "clock.arrow.circlepath")
                                    .font(.headline)
                                Spacer()
                                if !vm.recentArchiveURLs.isEmpty {
                                    Text("\(vm.recentArchiveURLs.count) 项")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if vm.recentArchiveURLs.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "archivebox")
                                        .font(.title)
                                        .foregroundStyle(.tertiary)
                                    Text("暂无最近打开的压缩包")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 165)
                            } else {
                                ForEach(vm.recentArchiveURLs, id: \.path) { url in
                                    Button {
                                        vm.openArchive(url: url)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.zipper")
                                                .foregroundStyle(.cyan)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(url.lastPathComponent)
                                                    .font(.body.weight(.medium))
                                                    .lineLimit(1)
                                                Text(url.deletingLastPathComponent().path)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contextMenu {
                                        Button("打开浏览") { vm.openArchive(url: url) }
                                        Divider()
                                        Button("智能解压到所在目录") { vm.quickExtract(mode: .smart, archiveURL: url) }
                                        Button("解压到同名子文件夹") { vm.quickExtract(mode: .subfolder, archiveURL: url) }
                                        Button("完整性校验") { vm.testIntegrity(archiveURL: url) }
                                        Divider()
                                        Button("在访达中显示") { vm.showInFinder(url) }
                                        Button("从最近记录移除", role: .destructive) { vm.removeRecent(url) }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(26)
            }
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
