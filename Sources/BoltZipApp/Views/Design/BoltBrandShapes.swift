import SwiftUI

struct BoltZMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

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

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: 0.11)
            .translatedBy(x: -center.x, y: -center.y)
        return p.applying(transform)
    }
}

struct BoltLogoBadge: View {
    let size: CGFloat
    var whiteBackground: Bool = false

    var body: some View {
        ZStack {
            if whiteBackground {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 0.94, green: 0.96, blue: 0.99)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.10), radius: size * 0.08, y: size * 0.03)
            } else {
                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: size, height: size)
                    .boltGlassSurface(.regular, tint: .cyan.opacity(0.18), in: Circle())
            }

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
                .shadow(color: Color.cyan.opacity(whiteBackground ? 0.28 : 0.45), radius: size * 0.08)
        }
    }
}

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

            if #available(macOS 14.0, *) {
                Image(systemName: symbol)
                    .font(BoltType.badgeSymbol)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: isPulsing)
            } else {
                Image(systemName: symbol)
                    .font(BoltType.badgeSymbol)
                    .foregroundStyle(tint)
            }
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
