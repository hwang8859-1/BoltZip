import AppKit
import SwiftUI

struct WindowStyleConfigurator: NSViewRepresentable {
    let isTranslucent: Bool
    let backgroundOpacity: Double
    let minWidth: CGFloat
    let minHeight: CGFloat

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
        let minSz = NSSize(width: minWidth, height: minHeight)
        window.contentMinSize = minSz
        window.minSize = minSz

        if isTranslucent {
            window.isOpaque = false
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(max(0.02, min(0.95, backgroundOpacity * 0.45)))
            window.titlebarAppearsTransparent = true
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}
