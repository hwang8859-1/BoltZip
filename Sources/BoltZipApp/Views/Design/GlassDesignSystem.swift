import AppKit
import Foundation
import SwiftUI

/// Runtime platform capabilities and architecture descriptors (macOS 26+ Apple Silicon).
enum BoltPlatformCapabilities {
    static let supportsLiquidGlass: Bool = true

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

enum BoltSurfaceTone: Sendable {
    case regular
    /// Only for components floating over rich media (photo/video). Never over text or mixed with `.regular`.
    case clear
}

/// Visual depth tier separating glass chrome (`.window`, `.elevated`) from non-glass content cards (`.card`).
enum BoltGlassLevel: Sendable {
    case window
    case card
    case elevated
}

/// Centralized translucency & opacity curves driven by a single `glassIntensity` slider (`0.0 ... 1.0`).
/// Enforces at most one blur/glass layer per surface.
enum BoltGlassMetrics: Sendable {
    static func clamped(_ intensity: Double) -> Double {
        min(max(intensity, 0), 1)
    }

    // MARK: L1 — Window glass (single NSGlassEffectView + color veil)

    static func windowGlassTintAlpha(intensity: Double) -> CGFloat {
        let t = clamped(intensity)
        return CGFloat(0.24 - t * 0.08)
    }

    static func windowVeilAlpha(intensity: Double, isDark: Bool, isColoredPreset: Bool) -> Double {
        let t = clamped(intensity)
        if isColoredPreset {
            let minAlpha = isDark ? 0.36 : 0.40
            return 0.90 - t * (0.90 - minAlpha)
        }
        let minAlpha = isDark ? 0.44 : 0.48
        return 0.88 - t * (0.88 - minAlpha)
    }

    // MARK: L2 — Sheet single material + veil

    static func sheetVeilAlpha(intensity: Double, isDark: Bool, isColoredPreset: Bool) -> Double {
        let t = clamped(intensity)
        let minAlpha = isColoredPreset ? (isDark ? 0.42 : 0.44) : (isDark ? 0.42 : 0.46)
        return 0.88 - t * (0.88 - minAlpha)
    }

    // MARK: L3 — Content cards (fill + hairline only, never glass)

    static func cardFillAlpha(intensity: Double, isDark: Bool) -> Double {
        let t = clamped(intensity)
        let base = isDark ? 0.16 : 0.15
        return base - t * 0.04
    }

    // MARK: L4' — Pinned bars / sticky covers (frosted material + calibrated readable veil)

    static func coverScrimAlpha(intensity: Double, isDark: Bool) -> Double {
        let t = clamped(intensity)
        let base = isDark ? 0.64 : 0.66
        let minAlpha = isDark ? 0.36 : 0.38
        return base - t * (base - minAlpha)
    }

    /// Lightweight within-card veil paired with `.safeAreaBar` + `.scrollEdgeEffectStyle(.soft, for: .top)`
    /// so scrolled rows remain softly discernible ("半遮挡 / 玻璃进入效果") without sharp text collision.
    static func scrollHeaderVeilAlpha(intensity: Double, isDark: Bool) -> Double {
        let t = clamped(intensity)
        let base = isDark ? 0.38 : 0.40
        let minAlpha = isDark ? 0.14 : 0.16
        return base - t * (base - minAlpha)
    }

    /// Calibrated glass veil for the Welcome screen's titlebar scroll pocket (`0..topOffset`)
    /// paired with `.scrollEdgeEffectStyle(.hard, for: .top)` so scrolled cards blur cleanly behind
    /// the traffic lights, window title, and toolbar capsule without bleeding sharp characters through.
    static func titlebarScrollVeilAlpha(intensity: Double, isDark: Bool) -> Double {
        let t = clamped(intensity)
        let base = isDark ? 0.36 : 0.38
        let minAlpha = isDark ? 0.14 : 0.16
        return base - t * (base - minAlpha)
    }

    static func borderOpacity(level: BoltGlassLevel, isDark: Bool, increasedContrast: Bool) -> Double {
        if increasedContrast {
            return level == .elevated ? 0.28 : 0.22
        }
        switch level {
        case .window:
            return 0
        case .card:
            return isDark ? 0.14 : 0.10
        case .elevated:
            return isDark ? 0.18 : 0.13
        }
    }
}

private struct BoltGlassIntensityKey: EnvironmentKey {
    static let defaultValue: Double = 0.75
}

extension EnvironmentValues {
    var boltGlassIntensity: Double {
        get { self[BoltGlassIntensityKey.self] }
        set { self[BoltGlassIntensityKey.self] = newValue }
    }
}

enum BoltRadius {
    static func nested(in outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(6, outer - padding)
    }

    static let hero: CGFloat = 16
    static let bar: CGFloat = nested(in: hero, padding: 4)
    static let card: CGFloat = 14
    static let row: CGFloat = nested(in: card, padding: 6)
    static let badge: CGFloat = nested(in: bar, padding: 2)
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

/// Wraps `GlassEffectContainer` natively on macOS 26+.
struct BoltGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

/// Reusable frosted glass section card for forms, settings, and wizards.
struct BoltGlassSectionCard<Content: View>: View {
    let title: String?
    var icon: String? = nil
    var iconColor: Color = .cyan
    let glassEnabled: Bool
    var level: BoltGlassLevel = .card
    var tint: Color? = nil
    var contentSpacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        icon: String? = nil,
        iconColor: Color = .cyan,
        glassEnabled: Bool,
        level: BoltGlassLevel = .card,
        tint: Color? = nil,
        contentSpacing: CGFloat = 8,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.glassEnabled = glassEnabled
        self.level = level
        self.tint = tint
        self.contentSpacing = contentSpacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                HStack(spacing: 5) {
                    if let icon {
                        Image(systemName: icon)
                            .font(BoltType.captionMedium)
                            .foregroundStyle(iconColor)
                    }
                    Text(title)
                        .font(BoltType.cardEyebrow)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: contentSpacing) {
                content()
            }
            .font(BoltType.subbody)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: level,
                tone: .regular,
                tint: tint,
                in: RoundedRectangle(cornerRadius: BoltRadius.card, style: .continuous)
            )
        }
    }
}

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
    /// Applies native Liquid Glass surface styling on macOS 26+.
    func boltGlassSurface<S: InsettableShape>(
        _ tone: BoltSurfaceTone = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        self.glassEffect(makeBoltGlass(tone, tint: tint, interactive: interactive), in: shape)
    }

    /// Applies tiered Liquid Glass (`.window`, `.elevated`) or non-glass fill surfaces (`.card`),
    /// automatically adapting to `boltGlassIntensity` and macOS Reduce Transparency / Increase Contrast.
    func boltLayeredSurface<S: InsettableShape>(
        glassEnabled: Bool,
        level: BoltGlassLevel = .card,
        tone: BoltSurfaceTone = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        self.modifier(
            BoltLayeredSurfaceModifier(
                glassEnabled: glassEnabled,
                level: level,
                tone: tone,
                tint: tint,
                interactive: interactive,
                shape: shape
            )
        )
    }

    /// Applies the unified translucent sheet backdrop + presentation glass + preferred theme across modal sheets.
    func boltGlassSheetStyle(
        enabled: Bool,
        glassIntensity: Double = 0.75,
        backgroundNSColor: NSColor? = nil,
        isColoredPreset: Bool = false,
        colorScheme: ColorScheme?
    ) -> some View {
        self.modifier(
            BoltGlassSheetStyleModifier(
                enabled: enabled,
                glassIntensity: glassIntensity,
                backgroundNSColor: backgroundNSColor,
                isColoredPreset: isColoredPreset,
                preferredScheme: colorScheme
            )
        )
    }

    /// Unified sheet backdrop bound directly to WorkspaceViewModel background color & glass strength preferences.
    func boltUnifiedSheetStyle(vm: WorkspaceViewModel) -> some View {
        self.modifier(BoltUnifiedSheetModifier(vm: vm))
    }

    /// Within-window frosted glass overlay cap for pinned headers/footers/bars over app content & background.
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

    /// Applies unified transparent `.clear` container background when glass is active so `BoltUnifiedWindowBacking`
    /// renders identically across SwiftUI Scenes and AppKit-hosted windows without double material stacking.
    func boltUnifiedWindowContainerBackground(glassEnabled: Bool) -> some View {
        self.modifier(BoltWindowContainerBackgroundModifier(glassEnabled: glassEnabled))
    }

    func boltGlassButton() -> some View {
        self.buttonStyle(.glass)
    }

    func boltGlassProminentButton() -> some View {
        self.buttonStyle(.glassProminent)
    }

    func boltSoftTopScrollEdgeEffect() -> some View {
        self.scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Pairs `.scrollEdgeEffectStyle(.soft, for: .top)` with `.safeAreaBar(edge: .top)` so macOS 26
    /// progressively blurs scrolling rows as they glide beneath sticky headers ("半遮挡 / 玻璃进入效果").
    func boltTopScrollHeaderBar<Header: View>(
        glassEnabled: Bool,
        dividerEdge: Edge? = .bottom,
        @ViewBuilder header: @escaping () -> Header
    ) -> some View {
        self.modifier(
            BoltTopScrollHeaderBarModifier(
                glassEnabled: glassEnabled,
                dividerEdge: dividerEdge,
                header: header
            )
        )
    }

    /// Pairs `.scrollEdgeEffectStyle(.hard, for: .top)` with a uniform glass `.safeAreaBar` across `0..topOffset`
    /// so Welcome page cards are frosted and blurred smoothly behind the window titlebar and toolbar capsules.
    func boltTitlebarScrollEdgeBar(
        height: CGFloat,
        glassEnabled: Bool
    ) -> some View {
        self.modifier(
            BoltTitlebarScrollEdgeBarModifier(
                height: height,
                glassEnabled: glassEnabled
            )
        )
    }

    func boltHardTopScrollEdgeEffect() -> some View {
        self.scrollEdgeEffectStyle(.hard, for: .top)
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func boltHiddenSharedBackground() -> some ToolbarContent {
        self.sharedBackgroundVisibility(.hidden)
    }
}

private struct BoltLayeredSurfaceModifier<S: InsettableShape>: ViewModifier {
    let glassEnabled: Bool
    let level: BoltGlassLevel
    let tone: BoltSurfaceTone
    let tint: Color?
    let interactive: Bool
    let shape: S

    @Environment(\.boltGlassIntensity) private var glassIntensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let increasedContrast = colorSchemeContrast == .increased
        let effectiveGlass = glassEnabled && !reduceTransparency
        let borderWidth: CGFloat = increasedContrast ? 1.0 : 0.5

        switch tone {
        case .clear:
            if effectiveGlass {
                content.boltGlassSurface(.clear, tint: tint, interactive: interactive, in: shape)
            } else {
                content.background(tint ?? Color.clear, in: shape)
            }
        case .regular:
            regularSurface(
                content: content,
                isDark: isDark,
                increasedContrast: increasedContrast,
                effectiveGlass: effectiveGlass,
                borderWidth: borderWidth
            )
        }
    }

    @ViewBuilder
    private func regularSurface(
        content: Content,
        isDark: Bool,
        increasedContrast: Bool,
        effectiveGlass: Bool,
        borderWidth: CGFloat
    ) -> some View {
        if !effectiveGlass {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(
                    shape.strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.24 : 0.10),
                        lineWidth: borderWidth
                    )
                )
        } else {
            switch level {
            case .window, .elevated:
                content
                    .boltGlassSurface(.regular, tint: tint, interactive: interactive, in: shape)
                    .overlay(
                        shape.strokeBorder(
                            Color.primary.opacity(
                                BoltGlassMetrics.borderOpacity(
                                    level: level, isDark: isDark, increasedContrast: increasedContrast
                                )
                            ),
                            lineWidth: borderWidth
                        )
                    )
            case .card:
                content
                    .background {
                        ZStack {
                            shape.fill(
                                Color(nsColor: .controlBackgroundColor)
                                    .opacity(BoltGlassMetrics.cardFillAlpha(intensity: glassIntensity, isDark: isDark))
                            )
                            if let tint {
                                shape.fill(tint)
                            }
                        }
                    }
                    .overlay(
                        shape.strokeBorder(
                            Color.primary.opacity(
                                BoltGlassMetrics.borderOpacity(
                                    level: .card, isDark: isDark, increasedContrast: increasedContrast
                                )
                            ),
                            lineWidth: borderWidth
                        )
                    )
            }
        }
    }
}

private struct BoltWindowContainerBackgroundModifier: ViewModifier {
    let glassEnabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let effectiveGlass = glassEnabled && !reduceTransparency
        content
            .containerBackground(
                effectiveGlass ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)),
                for: .window
            )
            .toolbarBackgroundVisibility(effectiveGlass ? .hidden : .automatic, for: .windowToolbar)
    }
}

private struct BoltUnifiedSheetModifier: ViewModifier {
    @Bindable var vm: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.boltGlassIntensity, vm.glassIntensity)
            .boltGlassSheetStyle(
                enabled: vm.effectiveWindowTranslucency,
                glassIntensity: vm.glassIntensity,
                backgroundNSColor: vm.resolvedBackgroundNSColor(isDark: colorScheme == .dark),
                isColoredPreset: vm.appBackgroundColor != .pureWhite,
                colorScheme: vm.appTheme.colorScheme
            )
    }
}

private struct BoltWithinWindowGlassCoverModifier: ViewModifier {
    let glassEnabled: Bool
    let dividerEdge: Edge?
    let cornerRadius: CGFloat
    @Environment(\.boltGlassIntensity) private var glassIntensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let effectiveGlass = glassEnabled && !reduceTransparency
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let scrimAlpha = BoltGlassMetrics.coverScrimAlpha(intensity: glassIntensity, isDark: isDark)

        content
            .background {
                if effectiveGlass {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Color(nsColor: .controlBackgroundColor).opacity(scrimAlpha)
                        VStack {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.14 : 0.34),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 6)
                            Spacer(minLength: 0)
                        }
                    }
                    .clipShape(shape)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                        .clipShape(shape)
                }
            }
            .overlay(alignment: dividerEdge == .top ? .top : .bottom) {
                if dividerEdge != nil {
                    let dividerOpacity = colorSchemeContrast == .increased
                        ? 0.28
                        : (isDark ? 0.20 : 0.12)
                    Rectangle()
                        .fill(
                            effectiveGlass
                                ? Color.primary.opacity(dividerOpacity)
                                : Color(nsColor: .separatorColor)
                        )
                        .frame(height: 0.5)
                }
            }
    }
}

private struct BoltTopScrollHeaderBarModifier<Header: View>: ViewModifier {
    let glassEnabled: Bool
    let dividerEdge: Edge?
    @ViewBuilder let header: () -> Header
    @Environment(\.boltGlassIntensity) private var glassIntensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let effectiveGlass = glassEnabled && !reduceTransparency
        let veilAlpha = BoltGlassMetrics.scrollHeaderVeilAlpha(intensity: glassIntensity, isDark: isDark)
        let dividerOpacity = colorSchemeContrast == .increased
            ? 0.26
            : (isDark ? 0.14 : 0.08)

        content
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                header()
                    .background {
                        if effectiveGlass {
                            Color(nsColor: .controlBackgroundColor)
                                .opacity(veilAlpha)
                        } else {
                            Color(nsColor: .windowBackgroundColor)
                        }
                    }
                    .overlay(alignment: dividerEdge == .top ? .top : .bottom) {
                        if dividerEdge != nil {
                            Rectangle()
                                .fill(
                                    effectiveGlass
                                        ? Color.primary.opacity(dividerOpacity)
                                        : Color(nsColor: .separatorColor)
                                )
                                .frame(height: 0.5)
                        }
                    }
            }
    }
}

private struct BoltTitlebarScrollEdgeBarModifier: ViewModifier {
    let height: CGFloat
    let glassEnabled: Bool
    @Environment(\.boltGlassIntensity) private var glassIntensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let effectiveGlass = glassEnabled && !reduceTransparency
        let veilAlpha = BoltGlassMetrics.titlebarScrollVeilAlpha(intensity: glassIntensity, isDark: isDark)
        let dividerOpacity = colorSchemeContrast == .increased
            ? 0.22
            : (isDark ? 0.12 : 0.07)

        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .safeAreaBar(edge: .top) {
                Group {
                    if effectiveGlass {
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(veilAlpha)
                    } else {
                        Color(nsColor: .windowBackgroundColor)
                    }
                }
                .frame(height: height)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(
                            effectiveGlass
                                ? Color.primary.opacity(dividerOpacity)
                                : Color(nsColor: .separatorColor)
                        )
                        .frame(height: 0.5)
                }
                .allowsHitTesting(false)
            }
    }
}

private struct BoltGlassSheetStyleModifier: ViewModifier {
    let enabled: Bool
    let glassIntensity: Double
    let backgroundNSColor: NSColor?
    let isColoredPreset: Bool
    let preferredScheme: ColorScheme?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var envColorScheme

    func body(content: Content) -> some View {
        let isDark = envColorScheme == .dark
        let effectiveGlass = enabled && !reduceTransparency
        let clamped = BoltGlassMetrics.clamped(glassIntensity)
        let baseColor = backgroundNSColor ?? NSColor.windowBackgroundColor
        let veilOpacity = BoltGlassMetrics.sheetVeilAlpha(
            intensity: clamped,
            isDark: isDark,
            isColoredPreset: isColoredPreset
        )

        content
            .preferredColorScheme(preferredScheme)
            .background {
                Color(nsColor: baseColor)
                    .opacity(effectiveGlass ? veilOpacity : 1.0)
                    .ignoresSafeArea()
            }
            .presentationBackground(
                effectiveGlass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color(nsColor: baseColor))
            )
    }
}

// MARK: - Shared Form Row Primitives

/// Standardized switch row shared by Settings and Create Archive panels.
struct BoltFormSwitchRow<Leading: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    @ViewBuilder let leading: () -> Leading

    init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.leading = leading
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BoltType.subbodyMedium)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// Standardized Liquid Glass dropdown menu row shared by Settings and Create Archive panels.
struct BoltFormMenuRow<MenuContent: View>: View {
    let title: String
    var subtitle: String? = nil
    let selectedTitle: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BoltType.subbodyMedium)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(BoltType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            BoltGlassContainer {
                Menu {
                    menuContent()
                } label: {
                    Text(selectedTitle)
                        .font(BoltType.subbody)
                        .foregroundStyle(.primary)
                }
                .menuStyle(.button)
                .boltGlassButton()
                .controlSize(.small)
                .fixedSize()
            }
        }
    }
}

/// Unified checkmark-capable option button inside `BoltFormMenuRow`.
struct BoltMenuOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Neutral low-contrast read-only badge clearly separated from interactive Liquid Glass controls.
struct BoltReadOnlyBadge: View {
    let text: String
    var dotColor: Color? = nil
    var isEmphasized: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(BoltType.monoCaption)
                .monospacedDigit()
                .foregroundStyle(isEmphasized ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }
}

/// Unified elevated Liquid Glass footer bar shared across sheets and modal forms.
struct BoltSheetFooterBar<Content: View>: View {
    let glassEnabled: Bool
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        BoltGlassContainer(spacing: 10) {
            HStack(spacing: spacing) {
                content()
            }
            .padding(.horizontal, BoltMetrics.cardFooterHPad)
            .padding(.vertical, BoltMetrics.cardFooterVPad)
            .boltLayeredSurface(
                glassEnabled: glassEnabled,
                level: .elevated,
                tone: .regular,
                in: RoundedRectangle(cornerRadius: BoltRadius.bar, style: .continuous)
            )
        }
    }
}

@MainActor
protocol BoltDragTrackingWindow: AnyObject {
    func setUserDragging(_ dragging: Bool)
}

/// AppKit mouse-tracking drag surface allowing borderless HUDs and transparent-titlebar windows
/// to be smoothly repositioned by dragging non-interactive areas (e.g., headers, progress bars, card surfaces).
struct BoltWindowDragHandle: NSViewRepresentable {
    final class DragNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else {
                super.mouseDown(with: event)
                return
            }
            let tracker = window as? BoltDragTrackingWindow
            tracker?.setUserDragging(true)
            defer { tracker?.setUserDragging(false) }

            var startMouse = NSEvent.mouseLocation
            var origin = window.frame.origin
            window.trackEvents(
                matching: [.leftMouseDragged, .leftMouseUp],
                timeout: .greatestFiniteMagnitude,
                mode: .eventTracking
            ) { ev, stop in
                guard let ev else {
                    stop.pointee = true
                    return
                }
                switch ev.type {
                case .leftMouseDragged:
                    let cur = NSEvent.mouseLocation
                    origin.x += cur.x - startMouse.x
                    origin.y += cur.y - startMouse.y
                    startMouse = cur
                    window.setFrameOrigin(origin)
                case .leftMouseUp:
                    stop.pointee = true
                default:
                    break
                }
            }
        }
    }

    func makeNSView(context: Context) -> DragNSView {
        DragNSView(frame: .zero)
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}
}
