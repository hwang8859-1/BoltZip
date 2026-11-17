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
        let targetMin = NSSize(width: minWidth, height: minHeight)
        if window.contentMinSize != targetMin {
            window.contentMinSize = targetMin
        }
        if window.minSize != targetMin {
            window.minSize = targetMin
        }

        // Only clamp frame if transitioning into a larger minimum outside active drag resize
        if !window.inLiveResize {
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
        }

        if isTranslucent {
            if window.isOpaque { window.isOpaque = false }
            let alpha = max(0.02, min(0.95, backgroundOpacity * 0.45))
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha)
        } else {
            if !window.isOpaque { window.isOpaque = true }
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}
