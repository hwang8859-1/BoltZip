import AppKit
import BoltZipCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExplorerPointerTracker {
    var hoveredEntry: ArchiveEntry?
}

@MainActor
private final class DragBatchPasswordState {
    var resolvedPassword: String?
    var didPromptOrResolve = false
    private var rejectedPassword: String?
    private var cancelled = false

    func resolvePasswordIfNeeded(archiveURL: URL, initialPassword: String?, hasEncrypted: Bool, l: L10n) -> (password: String?, cancelled: Bool) {
        if let initialPassword, !initialPassword.isEmpty, initialPassword != rejectedPassword, !cancelled {
            resolvedPassword = initialPassword
            didPromptOrResolve = true
            return (initialPassword, false)
        }
        if didPromptOrResolve {
            return (resolvedPassword, cancelled)
        }
        didPromptOrResolve = true
        guard hasEncrypted else {
            return (nil, false)
        }

        boltActivateAppToForeground()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = l.passwordPromptTitle
        alert.informativeText = "\(archiveURL.lastPathComponent) — \(l.passwordPromptDesc)"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = l.passwordPlaceholder
        alert.accessoryView = field
        alert.addButton(withTitle: l.confirm)
        alert.addButton(withTitle: l.cancel)
        if alert.runModal() == .alertFirstButtonReturn {
            let pw = field.stringValue
            resolvedPassword = pw.isEmpty ? nil : pw
            return (resolvedPassword, false)
        }
        cancelled = true
        return (nil, true)
    }

    func reject(_ password: String?) {
        rejectedPassword = password
        resolvedPassword = nil
        didPromptOrResolve = false
    }
}

/// Stored on `NSFilePromiseProvider.userInfo` so we never subclass `NSFilePromiseProvider`,
/// avoiding AppKit's `-initWithFileType:delegate:` -> `[self init]` unimplemented-initializer trap.
private final class BoltDragOutPayload: @unchecked Sendable {
    let entry: ArchiveEntry
    let archiveURL: URL
    let encoding: FilenameEncodingOption
    let stripMacJunk: Bool
    let restoreSymlinks: Bool
    let initialPassword: String?
    let hasEncryptedEntries: Bool
    let batchPasswordState: DragBatchPasswordState
    weak var vm: WorkspaceViewModel?

    init(
        entry: ArchiveEntry,
        archiveURL: URL,
        encoding: FilenameEncodingOption,
        stripMacJunk: Bool,
        restoreSymlinks: Bool,
        initialPassword: String?,
        hasEncryptedEntries: Bool,
        batchPasswordState: DragBatchPasswordState,
        vm: WorkspaceViewModel?
    ) {
        self.entry = entry
        self.archiveURL = archiveURL
        self.encoding = encoding
        self.stripMacJunk = stripMacJunk
        self.restoreSymlinks = restoreSymlinks
        self.initialPassword = initialPassword
        self.hasEncryptedEntries = hasEncryptedEntries
        self.batchPasswordState = batchPasswordState
        self.vm = vm
    }
}

private struct PromiseCompletionBox: @unchecked Sendable {
    let finish: (Error?) -> Void
}

final class DragOutCoordinator: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.boltzip.dragout"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        guard let payload = filePromiseProvider.userInfo as? BoltDragOutPayload else {
            return "ExportedItem"
        }
        let clean = payload.entry.name.replacingOccurrences(of: "/", with: "_")
        return clean.isEmpty ? "ExportedItem" : clean
    }

    nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let payload = filePromiseProvider.userInfo as? BoltDragOutPayload else {
            completionHandler(nil)
            return
        }
        let completion = PromiseCompletionBox(finish: completionHandler)

        Task { @MainActor in
            let vm = payload.vm
            let needsPw = payload.entry.isEncrypted || (payload.entry.isDirectory && payload.hasEncryptedEntries)
            let pwResult = payload.batchPasswordState.resolvePasswordIfNeeded(
                archiveURL: payload.archiveURL,
                initialPassword: vm?.savedPassword ?? payload.initialPassword,
                hasEncrypted: needsPw,
                l: vm?.l10n ?? L10n(language: .system)
            )
            if pwResult.cancelled {
                completion.finish(BoltZipError.cancelled)
                return
            }
            let entry = payload.entry
            let archiveURL = payload.archiveURL
            let enc = payload.encoding
            let strip = payload.stripMacJunk
            let restoreLinks = payload.restoreSymlinks
            let password = pwResult.password
            let destFileURL = url

            vm?.isBusy = true
            vm?.progress = OperationProgress(fractionCompleted: 0.1, currentItem: entry.name)

            do {
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    let stageRoot = fm.temporaryDirectory.appendingPathComponent("BoltZipDragOut-\(UUID().uuidString)", isDirectory: true)
                    try fm.createDirectory(at: stageRoot, withIntermediateDirectories: true)
                    defer { try? fm.removeItem(at: stageRoot) }

                    let opts = ExtractOptions(
                        destinationURL: stageRoot,
                        mode: .selected([entry.path]),
                        overwritePolicy: .overwrite,
                        password: password,
                        encoding: enc,
                        stripMacJunk: strip,
                        restoreSymlinks: restoreLinks
                    )
                    _ = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts) { prog in
                        Task { @MainActor in
                            vm?.progress = prog
                        }
                    }

                    let cleanRel = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                    let stagedItemURL = stageRoot.appendingPathComponent(cleanRel)
                    guard fm.fileExists(atPath: stagedItemURL.path) else {
                        throw BoltZipError.entryNotFound(entry.path)
                    }
                    try BoltArchiveEngine.publishPromisedItem(
                        from: stagedItemURL, to: destFileURL,
                        protectedSources: BoltArchiveEngine.extractionSourceURLs(archiveURL: archiveURL, password: password)
                    )
                }.value
                if let password, vm?.listing?.archiveURL == archiveURL { vm?.savedPassword = password }
                vm?.isBusy = false
                vm?.progress = nil
                vm?.statusMessage = "-> \(destFileURL.lastPathComponent)"
                completion.finish(nil)
            } catch {
                if let archiveError = error as? BoltZipError {
                    switch archiveError {
                    case .wrongPassword, .passwordRequired:
                        payload.batchPasswordState.reject(password)
                        if vm?.listing?.archiveURL == archiveURL, vm?.savedPassword == password { vm?.savedPassword = nil }
                    default: break
                    }
                }
                vm?.isBusy = false
                vm?.progress = nil
                if case BoltZipError.cancelled = error {
                    // Cancelled by user
                } else {
                    vm?.alertMessage = vm?.l10n.operationErrorMessage(error)
                }
                completion.finish(error)
            }
        }
    }
}

/// Single container-level AppKit drag bridge avoiding N per-row `NSViewRepresentable` / `NSTrackingArea` overhead.
struct ExplorerListDragHost: NSViewRepresentable {
    let vm: WorkspaceViewModel
    let pointerTracker: ExplorerPointerTracker
    let headerHeight: CGFloat
    let rowPitch: CGFloat

    func makeCoordinator() -> DragOutCoordinator {
        DragOutCoordinator()
    }

    func makeNSView(context: Context) -> ExplorerDragHostNSView {
        let view = ExplorerDragHostNSView(frame: .zero)
        view.coordinator = context.coordinator
        view.vm = vm
        view.pointerTracker = pointerTracker
        view.headerHeight = headerHeight
        view.rowPitch = rowPitch
        return view
    }

    func updateNSView(_ nsView: ExplorerDragHostNSView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.vm = vm
        nsView.pointerTracker = pointerTracker
        nsView.headerHeight = headerHeight
        nsView.rowPitch = rowPitch
    }
}

final class ExplorerDragHostNSView: NSView {
    weak var vm: WorkspaceViewModel?
    weak var pointerTracker: ExplorerPointerTracker?
    var coordinator: DragOutCoordinator?
    var headerHeight: CGFloat = 30
    var rowPitch: CGFloat = 32

    private var eventMonitor: Any?
    private var dragOriginWindow: NSPoint?
    private var pressedEntry: ArchiveEntry?
    private var didBeginDrag = false

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func installMonitorIfNeeded() {
        guard window != nil, eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event) ?? event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        resetDragTracking()
    }

    private func resetDragTracking() {
        dragOriginWindow = nil
        pressedEntry = nil
        didBeginDrag = false
    }

    private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else {
            return event
        }
        if window.firstResponder is NSTextView {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            resetDragTracking()
            guard event.clickCount == 1,
                  !event.modifierFlags.contains(.control),
                  let vm,
                  vm.activeSheet == nil,
                  vm.pendingBatchArchiveDrop == nil,
                  vm.pendingDeleteConfirmation == nil,
                  vm.pendingExtractConflict == nil,
                  !vm.isBusy else {
                return event
            }
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local),
                  local.y > headerHeight,
                  local.x < bounds.width - 15 else {
                return event
            }
            if let entry = pointerTracker?.hoveredEntry ?? fallbackEntry(atLocalPoint: local, vm: vm) {
                dragOriginWindow = event.locationInWindow
                pressedEntry = entry
            }
            return event

        case .leftMouseDragged:
            guard !didBeginDrag,
                  let origin = dragOriginWindow,
                  let entry = pressedEntry,
                  let vm,
                  !vm.isBusy,
                  let listing = vm.listing,
                  let coordinator,
                  self.window != nil else {
                return event
            }
            let curWindow = event.locationInWindow
            guard hypot(curWindow.x - origin.x, curWindow.y - origin.y) >= 5.0 else {
                return event
            }

            didBeginDrag = true
            pressedEntry = nil

            let draggedEntries: [ArchiveEntry]
            if vm.selectedEntryIDs.contains(entry.id), vm.selectedEntries.count > 1 {
                draggedEntries = vm.selectedEntries
            } else {
                vm.selectedEntryIDs = [entry.id]
                draggedEntries = [entry]
            }

            let curLocal = convert(curWindow, from: nil)
            let batchState = DragBatchPasswordState()
            let dragSize = NSSize(width: 28, height: 28)
            let draggingItems: [NSDraggingItem] = draggedEntries.prefix(256).enumerated().map { idx, itemEntry in
                let utType: UTType = itemEntry.isDirectory ? .folder : .data
                let payload = BoltDragOutPayload(
                    entry: itemEntry,
                    archiveURL: listing.archiveURL,
                    encoding: vm.encodingOption,
                    stripMacJunk: vm.defaultStripMacJunk,
                    restoreSymlinks: vm.restoreSymlinksOnExtract,
                    initialPassword: vm.savedPassword,
                    hasEncryptedEntries: listing.hasEncryptedEntries,
                    batchPasswordState: batchState,
                    vm: vm
                )
                let promiseProvider = NSFilePromiseProvider(fileType: utType.identifier, delegate: coordinator)
                promiseProvider.userInfo = payload

                let dragItem = NSDraggingItem(pasteboardWriter: promiseProvider)
                let baseIcon: NSImage
                if itemEntry.isDirectory {
                    baseIcon = NSWorkspace.shared.icon(for: .folder)
                } else {
                    let ext = (itemEntry.name as NSString).pathExtension
                    let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
                    baseIcon = NSWorkspace.shared.icon(for: type)
                }
                let iconCopy = (baseIcon.copy() as? NSImage) ?? baseIcon
                iconCopy.size = dragSize
                let frameOrigin = NSPoint(x: curLocal.x - 14 + CGFloat(idx * 4), y: curLocal.y - 14 + CGFloat(idx * 4))
                dragItem.setDraggingFrame(NSRect(origin: frameOrigin, size: dragSize), contents: iconCopy)
                return dragItem
            }

            guard !draggingItems.isEmpty else { return event }
            beginDraggingSession(with: draggingItems, event: event, source: coordinator)
            return nil

        case .leftMouseUp:
            resetDragTracking()
            return event

        default:
            return event
        }
    }

    private func fallbackEntry(atLocalPoint local: NSPoint, vm: WorkspaceViewModel) -> ArchiveEntry? {
        guard let scrollView = findSiblingScrollView(),
              let docView = scrollView.documentView else {
            return nil
        }
        let docPoint = convert(local, to: docView)
        let topPadding: CGFloat = 4
        let yOffset = docView.isFlipped ? (docPoint.y - topPadding) : ((docView.bounds.height - docPoint.y) - topPadding)
        guard yOffset >= 0 else { return nil }
        let idx = Int(floor(yOffset / rowPitch))
        let entries = vm.visibleEntries
        guard idx >= 0 && idx < entries.count else { return nil }
        return entries[idx]
    }

    private func findSiblingScrollView() -> NSScrollView? {
        guard let container = superview else { return nil }
        var queue: [NSView] = container.subviews
        var i = 0
        while i < queue.count {
            let v = queue[i]
            i += 1
            if let sv = v as? NSScrollView {
                return sv
            }
            queue.append(contentsOf: v.subviews)
        }
        return nil
    }
}
