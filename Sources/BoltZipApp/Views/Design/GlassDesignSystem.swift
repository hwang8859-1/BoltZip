import AppKit
import Foundation
import SwiftUI

/// Runtime platform capabilities and architecture descriptors for OS backward compatibility.
enum BoltPlatformCapabilities {
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

enum BoltRadius {
    static let hero: CGFloat = 16
    static let card: CGFloat = 14
    static let bar: CGFloat = 12
    static let badge: CGFloat = 10
    static let row: CGFloat = 8
}

enum BoltType {
    static let displayTitle = Font.system(size: 20, weight: .bold)
    static func heroTitle(compact: Bool) -> Font {
        .system(size: compact ? 15 : 18, weight: .semibold)
    }
    static let windowTitle = Font.system(size: 14, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let subbody = Font.system(size: 12, weight: .regular)
    static let subbodyMedium = Font.system(size: 12, weight: .medium)
    static let cardEyebrow = Font.system(size: 11.5, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let badge = Font.system(size: 10, weight: .semibold)
    static let metricLarge = Font.system(size: 16, weight: .semibold)
    static let statusGlyph = Font.system(size: 19, weight: .regular)
    static let badgeSymbol = Font.system(size: 15, weight: .semibold)
    static let controlIcon = Font.system(size: 14.5, weight: .regular)
    static let microIcon = Font.system(size: 9.5, weight: .semibold)
    static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
}

enum BoltMetrics {
    static let headerHeight: CGFloat = 34
    static let cardHeaderHPad: CGFloat = 14
    static let cardHeaderVPad: CGFloat = 10
    static let cardFooterHPad: CGFloat = 14
    static let cardFooterVPad: CGFloat = 10
    static let pickerWidth: CGFloat = 205
    static let createPickerWidth: CGFloat = 230
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
                            .font(BoltType.captionMedium)
                            .foregroundStyle(.cyan)
                    }
                    Text(title)
                        .font(BoltType.cardEyebrow)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .font(BoltType.subbody)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                tone: .regular,
                tint: tint,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )
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
        if #available(macOS 13.3, *) {
            if enabled {
                self.presentationBackground(.ultraThinMaterial)
            } else {
                self.presentationBackground(Color(nsColor: .windowBackgroundColor))
            }
        } else {
            self
        }
    }

    /// Applies the unified translucent sheet backdrop + presentation glass + preferred theme across modal sheets.
    func boltGlassSheetStyle(
        enabled: Bool,
        glassIntensity: Double = 0.75,
        backgroundNSColor: NSColor? = nil,
        colorScheme: ColorScheme?
    ) -> some View {
        self.modifier(
            BoltGlassSheetStyleModifier(
                enabled: enabled,
                glassIntensity: glassIntensity,
                backgroundNSColor: backgroundNSColor,
                preferredScheme: colorScheme
            )
        )
    }

    /// Unified sheet backdrop bound directly to WorkspaceViewModel background color & glass strength preferences.
    func boltUnifiedSheetStyle(vm: WorkspaceViewModel) -> some View {
        self.modifier(BoltUnifiedSheetModifier(vm: vm))
    }

    /// Within-window frosted glass overlay cap for pinned headers/footers/bars over app content & background.
    @ViewBuilder
    func boltWithinWindowGlassCover(
        glassEnabled: Bool,
        dividerEdge: Edge? = .bottom,
        cornerRadius: CGFloat = 0
    ) -> some View {
        self.modifier(
            BoltWithinWindowGlassCoverModifier(
                glassEnabled: glassEnabled,
                dividerEdge: dividerEdge,
                cornerRadius: cornerRadius
            )
        )
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
    func boltScrollTopMargin(_ top: CGFloat, includeContent: Bool = true) -> some View {
        if #available(macOS 14.0, *) {
            if includeContent {
                self
                    .contentMargins(.top, top, for: .scrollContent)
                    .contentMargins(.top, top, for: .scrollIndicators)
            } else {
                self.contentMargins(.top, top, for: .scrollIndicators)
            }
        } else if includeContent {
            self.safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: top)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func boltFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    @ViewBuilder
    func boltWindowToolbarBackgroundVisibility(_ visibility: Visibility) -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(visibility, for: .windowToolbar)
        } else if #available(macOS 13.0, *) {
            self.toolbarBackground(visibility, for: .windowToolbar)
        } else {
            self
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

private struct BoltUnifiedSheetModifier: ViewModifier {
    @ObservedObject var vm: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .boltGlassSheetStyle(
                enabled: vm.effectiveWindowTranslucency,
                glassIntensity: vm.glassIntensity,
                backgroundNSColor: vm.resolvedBackgroundNSColor(isDark: colorScheme == .dark),
                colorScheme: vm.appTheme.colorScheme
            )
    }
}

private struct BoltWithinWindowGlassCoverModifier: ViewModifier {
    let glassEnabled: Bool
    let dividerEdge: Edge?
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if glassEnabled {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.white.opacity(isDark ? 0.05 : 0.14)
                    }
                    .clipShape(shape)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                        .clipShape(shape)
                }
            }
            .overlay(alignment: dividerEdge == .top ? .top : .bottom) {
                if dividerEdge != nil {
                    Rectangle()
                        .fill(
                            glassEnabled
                                ? Color.primary.opacity(isDark ? 0.14 : 0.08)
                                : Color(nsColor: .separatorColor)
                        )
                        .frame(height: 0.5)
                }
            }
    }
}

private struct BoltGlassSheetStyleModifier: ViewModifier {
    let enabled: Bool
    let glassIntensity: Double
    let backgroundNSColor: NSColor?
    let preferredScheme: ColorScheme?
    @Environment(\.colorScheme) private var envColorScheme

    func body(content: Content) -> some View {
        let isDark = envColorScheme == .dark
        let clamped = min(max(glassIntensity, 0), 1)
        let baseColor = backgroundNSColor ?? NSColor.windowBackgroundColor
        let veilOpacity = max(0.14, (1.0 - clamped) * 0.72 + 0.08)
        content
            .preferredColorScheme(preferredScheme)
            .background {
                if enabled {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Color(nsColor: baseColor)
                            .opacity(isDark ? max(0.24, veilOpacity) : veilOpacity)
                    }
                    .ignoresSafeArea()
                } else {
                    Color(nsColor: baseColor)
                        .ignoresSafeArea()
                }
            }
            .boltSheetPresentationGlass(enabled)
    }
}
