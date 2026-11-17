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

        // Ensure current frame respects updated minimum height/width cleanly
        var frame = window.frame
        var needsResize = false
        if frame.size.width < minWidth {
            frame.size.width = minWidth
            needsResize = true
        }
        if frame.size.height < minHeight {
            let delta = minHeight - frame.size.height
            frame.origin.y -= delta
            frame.size.height = minHeight
            needsResize = true
        }
        if needsResize {
            window.setFrame(frame, display: true, animate: false)
        }

        if isTranslucent {
            window.isOpaque = false
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(max(0.02, min(0.95, backgroundOpacity * 0.45)))
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}
