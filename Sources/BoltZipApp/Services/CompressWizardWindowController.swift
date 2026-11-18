import AppKit
import SwiftUI

/// Dedicated border-frosted standalone window for Finder right-click compression options,
/// keeping the main Welcome window hidden when launched outside the main studio.
@MainActor
final class CompressWizardWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onDidClose: (() -> Void)?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(viewModel: WorkspaceViewModel, inputs: [URL]) {
        guard !inputs.isEmpty else { return }

        let rootView = CreateArchiveSheet(
            vm: viewModel,
            initialInputs: inputs,
            isStandaloneWindow: true
        ) { [weak self] in
            self?.close()
        }

        let hostingController = NSHostingController(rootView: rootView)
        let targetSize = NSSize(width: 496, height: 536)

        let targetWindow: NSWindow
        if let existing = self.window {
            targetWindow = existing
            existing.contentViewController = hostingController
            existing.title = viewModel.l10n.createArchiveTitle
            existing.setContentSize(targetSize)
        } else {
            let created = NSWindow(
                contentRect: NSRect(origin: .zero, size: targetSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.identifier = NSUserInterfaceItemIdentifier("boltzip.compress")
            created.title = viewModel.l10n.createArchiveTitle
            created.isReleasedWhenClosed = false
            created.isRestorable = false
            created.delegate = self
            created.contentViewController = hostingController
            created.setContentSize(targetSize)
            centerWindowOnActiveScreen(created, contentSize: targetSize)
            self.window = created
            targetWindow = created
        }

        NSApp.activate(ignoringOtherApps: true)
        targetWindow.alphaValue = 1
        targetWindow.makeKeyAndOrderFront(nil)
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow, contentSize: NSSize) {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let origin = NSPoint(
            x: visible.midX - contentSize.width * 0.5,
            y: visible.midY - contentSize.height * 0.5
        )
        window.setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let onClose = onDidClose
        DispatchQueue.main.async {
            onClose?()
        }
    }
}
