import AppKit
import SwiftUI

struct WindowStyleConfigurator: NSViewRepresentable {
    let isTranslucent: Bool
    let backgroundOpacity: Double
    let minWidth: CGFloat
    let minHeight: CGFloat
    @Binding var titlebarHeight: CGFloat

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

        // Use macOS standard unified toolbar style for robust scaling and responsive layout
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        if let tb = window.toolbar, tb.sizeMode != .regular {
            tb.sizeMode = .regular
        }

        let targetMin = NSSize(width: minWidth, height: minHeight)
        if window.contentMinSize != targetMin {
            window.contentMinSize = targetMin
        }
        if window.minSize != targetMin {
            window.minSize = targetMin
        }

        // Standard native macOS titlebar configuration:
        // Do not make titlebar transparent to prevent content from colliding with toolbar items on resize.
        if isTranslucent {
            if window.isOpaque { window.isOpaque = false }
            let alpha = max(0.20, min(0.95, backgroundOpacity * 0.70))
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha)
        } else {
            if !window.isOpaque { window.isOpaque = true }
            window.backgroundColor = NSColor.windowBackgroundColor
        }

        if window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = false
        }
        if window.titlebarSeparatorStyle != .automatic {
            window.titlebarSeparatorStyle = .automatic
        }

        let measuredTB = window.frame.height - window.contentLayoutRect.height
        if measuredTB > 0 && abs(measuredTB - titlebarHeight) > 0.5 {
            titlebarHeight = measuredTB
        }
    }
}
