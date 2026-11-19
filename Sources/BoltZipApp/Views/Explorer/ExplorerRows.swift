import BoltZipCore
import SwiftUI

struct GlassFolderTreeRow: View {
    let node: FolderTreeNode
    let depth: Int
    let selectedFolder: String
    let l: L10n
    let canEditZip: Bool
    let glassEnabled: Bool
    @Binding var expandedPaths: Set<String>
    let vm: WorkspaceViewModel
    @State private var isHovered = false

    private var isSelected: Bool { selectedFolder == node.path }
    private var isExpanded: Bool { expandedPaths.contains(node.path) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            rowView

            if isExpanded && !node.children.isEmpty {
                ForEach(node.children) { child in
                    GlassFolderTreeRow(
                        node: child,
                        depth: depth + 1,
                        selectedFolder: selectedFolder,
                        l: l,
                        canEditZip: canEditZip,
                        glassEnabled: glassEnabled,
                        expandedPaths: $expandedPaths,
                        vm: vm
                    )
                }
            }
        }
    }

    private var rowView: some View {
        HStack(spacing: 4) {
            if !node.children.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        if isExpanded {
                            expandedPaths.remove(node.path)
                        } else {
                            expandedPaths.insert(node.path)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(BoltType.microIcon)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 16)
            }

            Image(systemName: node.path.isEmpty ? "archivebox.fill" : "folder.fill")
                .font(BoltType.subbody)
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (node.path.isEmpty ? Color.indigo : Color.accentColor)
                )

            Text(node.name)
                .font(isSelected ? BoltType.subbodyMedium : BoltType.subbody)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)
        }
        .padding(.leading, CGFloat(depth * 12) + 4)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(node.id)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                    .fill(Color.accentColor.opacity(glassEnabled ? 0.78 : 0.92))
            } else if isHovered {
                RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture {
            vm.navigateToFolder(node.path)
        }
        .contextMenu {
            Button(l.ctxOpenDir) {
                vm.navigateToFolder(node.path)
            }
            if !node.path.isEmpty {
                Button(l.ctxExtractDir) {
                    vm.activeSheet = .extractOptions(.selected([node.path]))
                }
                Button(l.ctxCopyDirPath) {
                    vm.copyToPasteboard(node.path)
                }
            } else {
                Button(l.ctxSmartExtractAll) {
                    vm.quickExtract(mode: .smart)
                }
            }

            if canEditZip {
                Divider()
                Button(l.ctxAddToDir) {
                    vm.addItemsToCurrentZipPanel(targetFolder: node.path)
                }
                Button(l.ctxNewSubfolder) {
                    vm.activeSheet = .createFolder(parentFolder: node.path)
                }
                if !node.path.isEmpty {
                    Button(l.ctxRenameDir) {
                        vm.activeSheet = .renamePath(oldPath: node.path, currentName: node.name)
                    }
                    Button(l.ctxDeleteDir, role: .destructive) {
                        vm.deletePaths([node.path])
                    }
                }
            }
        }
    }
}

struct ToolbarPillIconButton: View {
    let systemImage: String
    let label: String
    let helpText: String
    var isDisabled: Bool = false
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(BoltType.controlIcon)
                .foregroundStyle(
                    isDisabled
                        ? AnyShapeStyle(.tertiary)
                        : (isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                )
                .frame(width: 29, height: 24)
                .background(
                    Capsule()
                        .fill(
                            !isDisabled && isActive
                                ? Color.accentColor.opacity(0.14)
                                : Color.primary.opacity(!isDisabled && isHovered ? 0.10 : 0.0)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(label)
    }
}

struct InfoMetricRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(BoltType.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(BoltType.captionMedium)
                .foregroundStyle(valueColor ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct ExplorerColumnMetrics {
    let origW: CGFloat
    let packedW: CGFloat
    let ratioW: CGFloat
    let methodW: CGFloat
    let modW: CGFloat
    let showMethod: Bool

    init(availableWidth: CGFloat) {
        self.showMethod = availableWidth >= 480
        if availableWidth >= 620 {
            self.origW = 74
            self.packedW = 74
            self.ratioW = 62
            self.methodW = 88
            self.modW = 118
        } else {
            self.origW = 58
            self.packedW = 58
            self.ratioW = 50
            self.methodW = 70
            self.modW = 94
        }
    }
}

struct ExplorerFileRow: View {
    let entry: ArchiveEntry
    let isSelected: Bool
    let cols: ExplorerColumnMetrics
    let dateString: String
    let iconName: String
    let pointerTracker: ExplorerPointerTracker
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(BoltType.subbody)
                    .foregroundStyle(isSelected ? Color.white : (entry.isDirectory ? Color.cyan : Color.secondary))
                Text(entry.name)
                    .font(BoltType.body)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(BoltType.badge)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.isDirectory ? "—" : DropHelper.formatBytes(entry.uncompressedSize))
                .font(BoltType.subbody)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white.opacity(0.90) : Color.secondary)
                .frame(width: cols.origW, alignment: .trailing)

            Text(entry.isDirectory || entry.compressedSize == 0 ? "—" : DropHelper.formatBytes(entry.compressedSize))
                .font(BoltType.subbody)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white.opacity(0.90) : Color.secondary)
                .frame(width: cols.packedW, alignment: .trailing)

            Group {
                if entry.isDirectory || entry.uncompressedSize == 0 {
                    Text("—")
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.6))
                } else {
                    Text(String(format: "%.1f%%", entry.compressionRatioPercent))
                        .foregroundStyle(isSelected ? Color.white : Color.green)
                }
            }
            .font(BoltType.subbody)
            .monospacedDigit()
            .frame(width: cols.ratioW, alignment: .trailing)

            if cols.showMethod {
                let label = entry.isEncrypted ? "\(entry.compressionMethodName) · \(entry.encryptionLabel)" : entry.compressionMethodName
                Text(label)
                    .font(BoltType.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.secondary)
                    .lineLimit(1)
                    .frame(width: cols.methodW, alignment: .leading)
                    .padding(.leading, 6)
            }

            Text(dateString)
                .font(BoltType.caption)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.secondary)
                .lineLimit(1)
                .frame(width: cols.modW, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                    .fill(Color.accentColor.opacity(0.88))
            } else if isHovered {
                RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous))
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                pointerTracker.hoveredEntry = entry
            } else if pointerTracker.hoveredEntry?.id == entry.id {
                pointerTracker.hoveredEntry = nil
            }
        }
        .onTapGesture(perform: onTap)
    }
}
