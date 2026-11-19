import SwiftUI

/// Unified 36x36 frosted icon tile shared by sheet headers and progress HUDs.
struct BoltHeaderIconBadge: View {
    let symbol: String
    var tint: Color = .cyan
    var isPulsing: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BoltRadius.badge, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: BoltRadius.badge, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 0.75)
                )

            Image(systemName: symbol)
                .font(BoltType.badgeSymbol)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: isPulsing)
        }
        .frame(width: 36, height: 36)
    }
}

/// Shared subtle close/dismiss/remove icon button with hover feedback and generous 20x20 hit target.
struct BoltCloseIconButton: View {
    let helpText: String
    var iconSize: CGFloat = 10.5
    var boxSize: CGFloat = 20
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: boxSize, height: boxSize)
                .background(
                    Circle().fill(Color.primary.opacity(isHovered ? 0.10 : 0.0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

/// Shared hairline section divider calibrated for both Liquid Glass and solid fallback surfaces.
struct BoltSectionDivider: View {
    let glassEnabled: Bool

    var body: some View {
        Divider().opacity(glassEnabled ? 0.28 : 0.6)
    }
}
