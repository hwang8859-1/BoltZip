import SwiftUI

/// Single recently opened archive entry with click-to-open body and dedicated trailing delete button.
struct RecentArchiveRow: View {
    @Bindable var vm: WorkspaceViewModel
    let url: URL
    let l: L10n
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BoltRadius.row, style: .continuous)
        HStack(spacing: 6) {
            Button {
                vm.openArchive(url: url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.zipper")
                        .font(BoltType.body)
                        .foregroundStyle(.cyan)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent)
                            .font(BoltType.subbodyMedium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                            .font(BoltType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            BoltCloseIconButton(
                helpText: l.ctxRemoveRecent,
                iconSize: 9.5,
                boxSize: 20
            ) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    vm.removeRecent(url)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            shape.fill(Color.primary.opacity(isHovered ? 0.06 : 0.0))
        )
        .onHover { isHovered = $0 }
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
