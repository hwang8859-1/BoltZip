import AppKit
import BoltZipCore
import SwiftUI

private final class QuickHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickTaskHUDWindowController: NSObject, NSWindowDelegate {
    private enum PositionKeys {
        static let hasSaved = "BoltZip.QuickHUDHasSavedPosition"
        static let originX = "BoltZip.QuickHUDLastOriginX"
        static let maxY = "BoltZip.QuickHUDLastMaxY"
    }

    private var panel: QuickHUDPanel?
    private var hostingController: NSHostingController<QuickTaskHUDRootView>?
    private var hideGeneration: Int = 0
    private var hasPositionedOnce: Bool = false
    private var isProgrammaticFrameUpdate: Bool = false
    private var isResizeScheduled: Bool = false

    var isVisible: Bool { panel?.isVisible == true }
    var onDidHide: (() -> Void)?

    func bind(viewModel: WorkspaceViewModel, hudModel: QuickTaskHUDModel) {
        let rootView = QuickTaskHUDRootView(vm: viewModel, hud: hudModel)
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hc = NSHostingController(rootView: rootView)
            // Keep sizingOptions empty: `.preferredContentSize` triggers recursive
            // `NSHostingView.windowDidLayout() -> updateAnimatedWindowSize` on macOS 26+.
            hc.sizingOptions = []
            self.hostingController = hc
        }

        hudModel.onPresentRequested = { [weak self] in
            self?.show(needsKeyFocus: false)
        }
        hudModel.onDismissRequested = { [weak self] in
            self?.hide()
        }
        hudModel.onKeyFocusRequested = { [weak self] in
            self?.makeKeyIfPasswordNeeded()
        }
        hudModel.onLayoutNeedsUpdate = { [weak self] in
            self?.scheduleResizeToFit()
        }
    }

    func show(needsKeyFocus: Bool = false) {
        guard let hostingController else { return }

        hideGeneration &+= 1

        let panel: QuickHUDPanel
        if let existing = self.panel {
            panel = existing
        } else {
            let created = QuickHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 436, height: 184),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.contentViewController = hostingController
            created.identifier = NSUserInterfaceItemIdentifier("boltzip.quickhud")
            created.isFloatingPanel = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            created.isMovableByWindowBackground = true
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.becomesKeyOnlyIfNeeded = true
            created.delegate = self
            self.panel = created
            panel = created
        }

        let fitting = measuredFittingSize(using: hostingController)
        if !hasPositionedOnce {
            positionInitialFrame(panel: panel, size: fitting)
            hasPositionedOnce = true
        } else {
            resizePanelIfNeeded(panel, to: fitting)
        }

        let wasVisible = panel.isVisible && panel.alphaValue > 0.05
        if needsKeyFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        if !wasVisible {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    func makeKeyIfPasswordNeeded() {
        scheduleResizeToFit()
        panel?.makeKeyAndOrderFront(nil)
    }

    private func scheduleResizeToFit() {
        guard !isResizeScheduled else { return }
        isResizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isResizeScheduled = false
            guard let panel = self.panel, panel.isVisible, let hostingController = self.hostingController else { return }
            let fitting = self.measuredFittingSize(using: hostingController)
            self.resizePanelIfNeeded(panel, to: fitting)
        }
    }

    private func measuredFittingSize(using hostingController: NSHostingController<QuickTaskHUDRootView>) -> NSSize {
        hostingController.view.layoutSubtreeIfNeeded()
        let raw = hostingController.sizeThatFits(in: NSSize(width: 436, height: 420))
        return NSSize(
            width: max(380, ceil(raw.width)),
            height: max(100, ceil(raw.height))
        )
    }

    private func resizePanelIfNeeded(_ panel: NSPanel, to fitting: NSSize) {
        let current = panel.frame
        if abs(current.width - fitting.width) > 1.0 || abs(current.height - fitting.height) > 1.0 {
            let topLeftOrigin = NSPoint(x: current.origin.x, y: current.maxY - fitting.height)
            let clamped = clampedOrigin(topLeftOrigin, size: fitting, preferredScreen: panel.screen ?? activeScreen())
            applyProgrammaticFrame(NSRect(origin: clamped, size: fitting), to: panel)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else {
            hasPositionedOnce = false
            onDidHide?()
            return
        }

        hideGeneration &+= 1
        let gen = hideGeneration

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.hideGeneration == gen else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.hasPositionedOnce = false
                self.onDidHide?()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameUpdate, hasPositionedOnce, let panel, panel.isVisible else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(panel.frame.origin.x), forKey: PositionKeys.originX)
        defaults.set(Double(panel.frame.maxY), forKey: PositionKeys.maxY)
        defaults.set(true, forKey: PositionKeys.hasSaved)
    }

    private func activeScreen() -> NSScreen? {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        return mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func positionInitialFrame(panel: NSPanel, size: NSSize) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: PositionKeys.hasSaved) {
            let savedX = defaults.double(forKey: PositionKeys.originX)
            let savedMaxY = defaults.double(forKey: PositionKeys.maxY)
            let probeCenter = NSPoint(x: savedX + size.width * 0.5, y: savedMaxY - size.height * 0.5)
            let savedScreen = NSScreen.screens.first { NSMouseInRect(probeCenter, $0.visibleFrame, false) }
                ?? activeScreen()
            let origin = clampedOrigin(
                NSPoint(x: savedX, y: savedMaxY - size.height),
                size: size,
                preferredScreen: savedScreen
            )
            applyProgrammaticFrame(NSRect(origin: origin, size: size), to: panel)
            return
        }

        guard let visible = activeScreen()?.visibleFrame else { return }
        let centered = NSPoint(
            x: visible.midX - size.width * 0.5,
            y: visible.midY - size.height * 0.5
        )
        applyProgrammaticFrame(NSRect(origin: centered, size: size), to: panel)
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, preferredScreen: NSScreen?) -> NSPoint {
        guard let visible = preferredScreen?.visibleFrame else { return origin }
        let margin: CGFloat = 8
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - size.width - margin)
        let minY = visible.minY + margin
        let maxY = max(minY, visible.maxY - size.height - margin)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func applyProgrammaticFrame(_ frame: NSRect, to panel: NSPanel) {
        isProgrammaticFrameUpdate = true
        panel.setFrame(frame, display: true)
        isProgrammaticFrameUpdate = false
    }
}

private struct QuickTaskHUDRootView: View {
    let vm: WorkspaceViewModel
    let hud: QuickTaskHUDModel

    var body: some View {
        QuickTaskHUDView(vm: vm, hud: hud)
            .environment(\.boltGlassIntensity, vm.glassIntensity)
            .preferredColorScheme(vm.appTheme.colorScheme)
    }
}
