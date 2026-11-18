import AppKit
import SwiftUI

/// Uniform ambient subtle sheen replacing uneven multi-corner color blobs so all cards keep identical color.
struct BoltAmbientBackdrop: View {
    var tintColor: Color = .clear

    var body: some View {
        tintColor
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

/// Layered native Liquid Glass (NSGlassEffectView on macOS 26+) + NSVisualEffectView behind-window blur backing.
struct BoltBehindWindowBlurView: NSViewRepresentable {
    var glassIntensity: Double = 0.75
    var tintColor: NSColor = NSColor.windowBackgroundColor

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let visual = NSVisualEffectView()
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.material = .hudWindow
        visual.autoresizingMask = [.width, .height]
        container.addSubview(visual)

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
        let clamped = min(max(glassIntensity, 0), 1)
        if let visual = container.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.material = .hudWindow
            visual.alphaValue = CGFloat(max(0.24, 0.88 - clamped * 0.56))
        }
        if let glass = container.subviews.first(where: { $0 is NSGlassEffectView }) as? NSGlassEffectView {
            glass.style = clamped >= 0.70 ? .clear : .regular
            let tintAlpha = max(0.03, (1.0 - clamped) * 0.55)
            glass.tintColor = tintColor.withAlphaComponent(tintAlpha)
        }
    }
}

/// Shared frosted-glass + unified custom background backing used across MainWindow, Compress, Settings, and About windows.
struct BoltWindowFrostedBacking: View {
    let glassEnabled: Bool
    let glassIntensity: Double
    let backgroundNSColor: NSColor
    var isColoredPreset: Bool = false
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
        let clamped = min(max(glassIntensity, 0), 1)
        let isDark = colorScheme == .dark
        let veilAlpha: Double = {
            if isColoredPreset {
                return max(isDark ? 0.16 : 0.18, (1.0 - clamped) * 0.78 + 0.10)
            }
            return max(0.04, (1.0 - clamped) * 0.82)
        }()
        if glassEnabled {
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BoltWindowFrostedBacking(
            glassEnabled: vm.effectiveWindowTranslucency,
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

        if isTranslucent {
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
}
