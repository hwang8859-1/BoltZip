import AppKit
import SwiftUI

/// Lightweight NSWindowController hosting auxiliary SwiftUI windows (`About`, `Settings`)
/// consistently across macOS 12 through macOS 26+.
@MainActor
final class AuxiliaryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onDidClose: (() -> Void)?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show<Content: View>(
        identifier: String,
        title: String,
        contentSize: NSSize,
        rootView: Content
    ) {
        let hosting = NSHostingController(rootView: rootView)

        let targetWindow: NSWindow
        if let existing = self.window {
            targetWindow = existing
            existing.contentViewController = hosting
            existing.title = title
            existing.setContentSize(contentSize)
        } else {
            let created = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.identifier = NSUserInterfaceItemIdentifier(identifier)
            created.title = title
            created.isReleasedWhenClosed = false
            created.isRestorable = false
            created.delegate = self
            created.contentViewController = hosting
            created.setContentSize(contentSize)
            centerWindowOnActiveScreen(created, contentSize: contentSize)
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
