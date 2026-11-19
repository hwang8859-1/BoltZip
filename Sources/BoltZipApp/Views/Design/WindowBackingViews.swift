import AppKit
import SwiftUI

/// Reliably activates BoltZip to the foreground under macOS 14–26 cooperative activation
/// (cold-launch document opens, Finder extensions, and minimized/occluded windows).
@MainActor
func boltActivateAppToForeground(bringing window: NSWindow? = nil) {
    if NSApp.isHidden {
        NSApp.unhide(nil)
    }
    NSRunningApplication.current.activate(options: .activateAllWindows)
    NSApp.activate()
    if let window {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Shared AppKit window translucency configuration used by both `WindowStyleConfigurator` and `BoltAuxiliaryWindowStyleBridge`.
@MainActor
func applyBoltWindowTranslucency(_ isTranslucent: Bool, to window: NSWindow) {
    let allowTranslucency = isTranslucent && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    if allowTranslucency {
        if window.isOpaque { window.isOpaque = false }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if window.backgroundColor != .clear { window.backgroundColor = .clear }
    } else {
        if !window.isOpaque { window.isOpaque = true }
        if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = false }
        if window.titlebarSeparatorStyle != .automatic { window.titlebarSeparatorStyle = .automatic }
        if window.backgroundColor != NSColor.windowBackgroundColor {
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}

/// Layer 1 window glass. Exactly one `NSGlassEffectView` surface, with no legacy blur view or secondary material.
struct BoltBehindWindowBlurView: NSViewRepresentable {
    var glassIntensity: Double = 0.75
    var tintColor: NSColor = NSColor.windowBackgroundColor

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let glass = NSGlassEffectView()
        glass.cornerRadius = 0
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        apply(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to container: NSView) {
        guard let glass = container.subviews.first(where: { $0 is NSGlassEffectView }) as? NSGlassEffectView else {
            return
        }
        let clamped = BoltGlassMetrics.clamped(glassIntensity)
        glass.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        glass.style = .regular
        glass.tintColor = tintColor.withAlphaComponent(
            BoltGlassMetrics.windowGlassTintAlpha(intensity: clamped)
        )
    }
}

/// Shared Layer-1 frosted-glass + unified custom background backing used across MainWindow, Compress, Settings, and About windows.
struct BoltWindowFrostedBacking: View {
    let glassEnabled: Bool
    let glassIntensity: Double
    let backgroundNSColor: NSColor
    var isColoredPreset: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    init(
        glassEnabled: Bool,
        glassIntensity: Double = 0.75,
        backgroundNSColor: NSColor = NSColor.windowBackgroundColor,
        isColoredPreset: Bool = false
    ) {
        self.glassEnabled = glassEnabled
        self.glassIntensity = glassIntensity
        self.backgroundNSColor = backgroundNSColor
        self.isColoredPreset = isColoredPreset
    }

    var body: some View {
        let effectiveGlass = glassEnabled && !reduceTransparency
        let clamped = BoltGlassMetrics.clamped(glassIntensity)
        let isDark = colorScheme == .dark
        let veilAlpha = BoltGlassMetrics.windowVeilAlpha(
            intensity: clamped,
            isDark: isDark,
            isColoredPreset: isColoredPreset
        )

        if effectiveGlass {
            ZStack {
                BoltBehindWindowBlurView(glassIntensity: clamped, tintColor: backgroundNSColor)
                Color(nsColor: backgroundNSColor)
                    .opacity(veilAlpha)
            }
            .ignoresSafeArea()
        } else {
            Color(nsColor: backgroundNSColor)
                .ignoresSafeArea()
        }
    }
}

/// Shared window backing automatically synced with WorkspaceViewModel color, appearance, and glass strength.
struct BoltUnifiedWindowBacking: View {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BoltWindowFrostedBacking(
            glassEnabled: vm.effectiveWindowTranslucency && !reduceTransparency,
            glassIntensity: vm.glassIntensity,
            backgroundNSColor: vm.resolvedBackgroundNSColor(isDark: colorScheme == .dark),
            isColoredPreset: vm.appBackgroundColor != .pureWhite
        )
    }
}

/// Bridges translucency and clear NSWindow backing to auxiliary standalone windows (Compress / Settings / About).
struct BoltAuxiliaryWindowStyleBridge: NSViewRepresentable {
    let isTranslucent: Bool
    let backgroundOpacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let allowTranslucency = isTranslucent && !reduceTransparency
        DispatchQueue.main.async {
            apply(to: view.window, allowTranslucency: allowTranslucency)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let allowTranslucency = isTranslucent && !reduceTransparency
        DispatchQueue.main.async {
            apply(to: nsView.window, allowTranslucency: allowTranslucency)
        }
    }

    private func apply(to window: NSWindow?, allowTranslucency: Bool) {
        guard let window else { return }
        if !window.styleMask.contains(.closable) {
            window.styleMask.insert(.closable)
        }
        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }
        if let closeBtn = window.standardWindowButton(.closeButton) {
            if closeBtn.isHidden { closeBtn.isHidden = false }
            if !closeBtn.isEnabled { closeBtn.isEnabled = true }
        }

        applyBoltWindowTranslucency(allowTranslucency, to: window)
    }
}
