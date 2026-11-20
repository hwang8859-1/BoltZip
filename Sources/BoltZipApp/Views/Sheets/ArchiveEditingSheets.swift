import AppKit
import BoltZipCore
import SwiftUI

struct ArchiveTextEditorSheet: View {
    @Bindable var vm: WorkspaceViewModel
    let document: ArchiveTextDocument
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(vm: WorkspaceViewModel, document: ArchiveTextDocument) {
        self.vm = vm
        self.document = document
        _text = State(initialValue: document.text)
    }

    var body: some View {
        let l = vm.l10n
        VStack(alignment: .leading, spacing: 10) {
            Text(l.editEntryText).font(BoltType.sectionTitle)
            Text(document.entryPath).font(BoltType.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(l.compressionPreservationNotice(document.profile)).font(BoltType.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .disabled(vm.isBusy)
            if let error = vm.archiveEditErrorMessage { Text(error).font(BoltType.caption).foregroundStyle(.red).textSelection(.enabled) }
            BoltSheetFooterBar(glassEnabled: vm.effectiveWindowTranslucency) {
                Button(l.cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(vm.isBusy)
                Spacer()
                if vm.isBusy { ProgressView().controlSize(.small) }
                Button(l.saveBtn) { vm.saveEntryText(document, text: text) }
                    .keyboardShortcut("s", modifiers: .command)
                    .boltGlassProminentButton()
                    .disabled(vm.isBusy || text == document.text)
            }
        }
        .padding(16)
        .frame(width: 760, height: 540)
        .interactiveDismissDisabled(vm.isBusy)
        .boltUnifiedSheetStyle(vm: vm)
    }
}
