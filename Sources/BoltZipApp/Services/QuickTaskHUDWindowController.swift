import AppKit
import BoltZipCore
import SwiftUI

private final class QuickHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickTaskHUDWindowController {
    private var panel: QuickHUDPanel?
    private var hostingController: NSHostingController<QuickTaskHUDRootView>?
    private var hideGeneration: Int = 0
    private var hasPositionedOnce: Bool = false

    var isVisible: Bool { panel?.isVisible == true }
    var onDidHide: (() -> Void)?

    func bind(viewModel: WorkspaceViewModel, hudModel: QuickTaskHUDModel) {
        let rootView = QuickTaskHUDRootView(vm: viewModel, hud: hudModel)
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hc = NSHostingController(rootView: rootView)
            hc.sizingOptions = [.preferredContentSize]
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
            self.panel = created
            panel = created
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.sizeThatFits(in: NSSize(width: 436, height: 420))
        if !hasPositionedOnce {
            positionTopRight(panel: panel, size: fitting)
            hasPositionedOnce = true
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
        panel?.makeKeyAndOrderFront(nil)
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

    private func positionTopRight(panel: NSPanel, size: NSSize) {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let margin: CGFloat = 14
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private struct QuickTaskHUDRootView: View {
    let vm: WorkspaceViewModel
    let hud: QuickTaskHUDModel

    var body: some View {
        QuickTaskHUDView(vm: vm, hud: hud)
            .preferredColorScheme(vm.appTheme.colorScheme)
    }
}
