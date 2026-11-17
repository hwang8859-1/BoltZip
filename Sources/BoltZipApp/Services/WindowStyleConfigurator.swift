import AppKit
import SwiftUI

struct WindowStyleConfigurator: NSViewRepresentable {
    let isTranslucent: Bool
    let backgroundOpacity: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView.window)
        }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        if isTranslucent {
            window.isOpaque = false
            // Keep window background subtle so SwiftUI Liquid Glass & material layer shine through
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(max(0.02, min(0.95, backgroundOpacity * 0.45)))
            window.titlebarAppearsTransparent = true
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}
