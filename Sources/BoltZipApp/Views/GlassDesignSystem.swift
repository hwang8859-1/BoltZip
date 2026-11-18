import AppKit
import Foundation
import SwiftUI

/// Runtime platform capabilities and architecture descriptors for OS backward compatibility.
enum BoltPlatformCapabilities {
    /// Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.glass` buttons) require macOS 26.0+.
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    static var architectureLabel: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static var osShortVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
    }

    static func runtimeVersionSummary(appVersion: String) -> String {
        "v\(appVersion) · macOS \(osShortVersion) · \(architectureLabel)"
    }
}

enum BoltSurfaceTone {
    case regular
    case clear
}

/// Wraps `GlassEffectContainer` on macOS 26+ and renders children directly when glass is disabled.
struct BoltGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

@available(macOS 26.0, *)
private func makeBoltGlass(_ tone: BoltSurfaceTone, tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = (tone == .regular ? .regular : .clear)
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

extension View {
    /// Applies Liquid Glass surface styling on macOS 26+ and falls back to solid native surfaces on older macOS.
    @ViewBuilder
    func boltGlassSurface<S: InsettableShape>(
        _ tone: BoltSurfaceTone = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeBoltGlass(tone, tint: tint, interactive: interactive), in: shape)
        } else {
            switch tone {
            case .clear:
                self.background(tint ?? Color.clear, in: shape)
            case .regular:
                self
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.95), in: shape)
                    .background(tint ?? Color.clear, in: shape)
                    .overlay(
                        shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
            }
        }
    }

    /// Applies Liquid Glass when enabled and supported (macOS 26+), otherwise clean solid native chrome.
    @ViewBuilder
    func boltLayeredSurface<S: InsettableShape>(
        glassEnabled: Bool,
        tone: BoltSurfaceTone = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        if glassEnabled {
            self.boltGlassSurface(tone, tint: tint, interactive: interactive, in: shape)
        } else {
            switch tone {
            case .clear:
                self.background(tint ?? Color.clear, in: shape)
            case .regular:
                self
                    .background(Color(nsColor: .controlBackgroundColor), in: shape)
                    .overlay(
                        shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                    )
            }
        }
    }

    @ViewBuilder
    func boltSheetPresentationGlass(_ enabled: Bool) -> some View {
        if enabled {
            self.presentationBackground(.ultraThinMaterial)
        } else {
            self.presentationBackground(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// Applies the unified translucent sheet backdrop + presentation glass + preferred theme across modal sheets.
    func boltGlassSheetStyle(enabled: Bool, colorScheme: ColorScheme?) -> some View {
        self.modifier(BoltGlassSheetStyleModifier(enabled: enabled, preferredScheme: colorScheme))
    }

    @ViewBuilder
    func boltGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func boltGlassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func boltSoftTopScrollEdgeEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func boltWindowToolbarBackgroundVisibility(_ visibility: Visibility) -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(visibility, for: .windowToolbar)
        } else {
            self.toolbarBackground(visibility, for: .windowToolbar)
        }
    }

    @ViewBuilder
    func boltWindowContainerBackground(_ style: AnyShapeStyle) -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(style, for: .window)
        } else {
            self
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func boltHiddenSharedBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct BoltZMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        // SwiftUI coordinates have y=0 at top, y=1 at bottom (flipped vertically vs CoreGraphics)
        let rawPoints: [(CGFloat, CGFloat)] = [
            (0.28, 0.14),
            (0.84, 0.14),
            (0.51, 0.45),
            (0.68, 0.45),
            (0.39, 0.70),
            (0.76, 0.70),
            (0.70, 0.85),
            (0.14, 0.85),
            (0.47, 0.54),
            (0.30, 0.54),
            (0.59, 0.29),
            (0.22, 0.29)
        ]

        var p = Path()
        for (idx, pt) in rawPoints.enumerated() {
            let point = CGPoint(x: ox + pt.0 * s, y: oy + pt.1 * s)
            if idx == 0 {
                p.move(to: point)
            } else {
                p.addLine(to: point)
            }
        }
        p.closeSubpath()

        // Slight clockwise tilt (~6.5 deg) matching AppIcon.icns
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: 0.11)
            .translatedBy(x: -center.x, y: -center.y)
        return p.applying(transform)
    }
}

struct BoltLogoBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: size, height: size)
                .boltGlassSurface(.regular, tint: .cyan.opacity(0.18), in: Circle())

            BoltZMark()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.84, blue: 1.0),
                            Color(red: 0.52, green: 0.70, blue: 1.0),
                            Color(red: 1.0, green: 0.84, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.62, height: size * 0.62)
                .shadow(color: Color.cyan.opacity(0.45), radius: size * 0.08)
        }
    }
}

struct BoltAmbientBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

/// Reusable Layer-2 frosted glass section card for forms, settings, and wizards.
struct BoltGlassSectionCard<Content: View>: View {
    let title: String?
    var icon: String? = nil
    let glassEnabled: Bool
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        icon: String? = nil,
        glassEnabled: Bool,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.glassEnabled = glassEnabled
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                HStack(spacing: 5) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                tint: tint,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

private struct BoltGlassSheetStyleModifier: ViewModifier {
    let enabled: Bool
    let preferredScheme: ColorScheme?
    @Environment(\.colorScheme) private var envColorScheme

    func body(content: Content) -> some View {
        let isDark = envColorScheme == .dark
        content
            .preferredColorScheme(preferredScheme)
            .background {
                if enabled {
                    ZStack {
                        BoltAmbientBackdrop()
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(isDark ? 0.24 : 0.14)
                    }
                    .ignoresSafeArea()
                } else {
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea()
                }
            }
            .boltSheetPresentationGlass(enabled)
    }
}

/// Bridges translucency and clear NSWindow backing to auxiliary standalone windows (Settings / About).
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
        window.titleVisibility = .visible
        if let closeBtn = window.standardWindowButton(.closeButton) {
            closeBtn.isHidden = false
            closeBtn.isEnabled = true
            if let titlebarContainer = closeBtn.superview?.superview {
                titlebarContainer.isHidden = false
                titlebarContainer.alphaValue = 1.0
                if let themeFrame = titlebarContainer.superview, themeFrame.subviews.last !== titlebarContainer {
                    themeFrame.addSubview(titlebarContainer, positioned: .above, relativeTo: nil)
                }
            }
        }

        if isTranslucent {
            if window.isOpaque { window.isOpaque = false }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            let alpha = max(0.02, min(0.95, backgroundOpacity * 0.45))
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha)
        } else {
            if !window.isOpaque { window.isOpaque = true }
            if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = false }
            if window.titlebarSeparatorStyle != .automatic { window.titlebarSeparatorStyle = .automatic }
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}
