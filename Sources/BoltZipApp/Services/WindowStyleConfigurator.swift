import AppKit
import SwiftUI

struct WindowStyleConfigurator: NSViewRepresentable {
    let isTranslucent: Bool
    let backgroundOpacity: Double
    let minWidth: CGFloat
    let minHeight: CGFloat
    var windowTitle: String = "BoltZip"
    var hideWindowTitle: Bool = false
    @Binding var titlebarHeight: CGFloat
    @Binding var isFullScreen: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @MainActor
    final class Coordinator: NSObject {
        weak var observedWindow: NSWindow?
        var enterObserver: NSObjectProtocol?
        var exitObserver: NSObjectProtocol?
        var onFullScreenChanged: (@MainActor (Bool) -> Void)?

        func observe(window: NSWindow, onChanged: @escaping @MainActor (Bool) -> Void) {
            self.onFullScreenChanged = onChanged
            guard observedWindow !== window else { return }
            removeObservers()
            observedWindow = window
            let nc = NotificationCenter.default
            enterObserver = nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onFullScreenChanged?(true)
                }
            }
            exitObserver = nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onFullScreenChanged?(false)
                }
            }
            onChanged(window.styleMask.contains(.fullScreen))
        }

        func removeObservers() {
            let nc = NotificationCenter.default
            if let enterObserver { nc.removeObserver(enterObserver) }
            if let exitObserver { nc.removeObserver(exitObserver) }
            enterObserver = nil
            exitObserver = nil
            observedWindow = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleApply(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleApply(for: nsView, coordinator: context.coordinator)
    }

    private func scheduleApply(for view: NSView, coordinator: Coordinator) {
        let allowTranslucency = isTranslucent && !reduceTransparency
        DispatchQueue.main.async {
            if let win = view.window {
                coordinator.observe(window: win) { full in
                    if isFullScreen != full {
                        isFullScreen = full
                    }
                }
            }
            apply(to: view.window, allowTranslucency: allowTranslucency)
        }
    }

    private func apply(to window: NSWindow?, allowTranslucency: Bool) {
        guard let window else { return }

        let nowFull = window.styleMask.contains(.fullScreen)
        if isFullScreen != nowFull {
            isFullScreen = nowFull
        }

        let targetTitle = hideWindowTitle ? " " : windowTitle
        if window.title != targetTitle {
            window.title = targetTitle
        }
        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }
        if window.toolbarStyle != .unifiedCompact {
            window.toolbarStyle = .unifiedCompact
        }
        if let tb = window.toolbar, tb.sizeMode != .regular {
            tb.sizeMode = .regular
        }
        let measuredTB = window.frame.height - window.contentLayoutRect.height
        if measuredTB > 20 && abs(measuredTB - titlebarHeight) > 0.5 {
            titlebarHeight = measuredTB
        }

        let targetMin = NSSize(width: minWidth, height: minHeight)
        if window.contentMinSize != targetMin {
            window.contentMinSize = targetMin
        }
        if window.minSize != targetMin {
            window.minSize = targetMin
        }

        if !window.inLiveResize && !nowFull {
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

        applyBoltWindowTranslucency(allowTranslucency, to: window)
    }
}
