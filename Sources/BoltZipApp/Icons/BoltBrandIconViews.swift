import SwiftUI

/// Vector Z-bolt mark synchronized with BoltZip's redesigned AppIcon geometry.
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
            .rotated(by: 0.105)
            .translatedBy(x: -center.x, y: -center.y)
        return p.applying(transform)
    }
}

/// Branded hero emblem shown in the Welcome drop zone and About window.
struct BoltLogoBadge: View {
    let size: CGFloat
    var whiteBackground: Bool = false
    var glassEnabled: Bool = true

    var body: some View {
        ZStack {
            if whiteBackground {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white,
                                Color(red: 0.969, green: 0.980, blue: 1.000),
                                Color(red: 0.914, green: 0.945, blue: 0.988)
                            ],
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
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                    .boltLayeredSurface(
                        glassEnabled: glassEnabled,
                        level: .card,
                        tone: .regular,
                        tint: .cyan.opacity(0.18),
                        in: Circle()
                    )
            }

            // Split top & bottom archival zipper teeth harmonizing with BoltIconArtwork
            VStack(spacing: 0) {
                zipperSeamCluster(whiteBackground: whiteBackground)
                Spacer()
                zipperSeamCluster(whiteBackground: whiteBackground)
            }
            .frame(width: size * 0.16, height: size * 0.78)
            .allowsHitTesting(false)

            BoltZMark()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.000, green: 0.796, blue: 0.961), location: 0.00),
                            .init(color: Color(red: 0.231, green: 0.635, blue: 1.000), location: 0.34),
                            .init(color: Color(red: 0.353, green: 0.486, blue: 1.000), location: 0.60),
                            .init(color: Color(red: 0.784, green: 0.667, blue: 0.314), location: 0.80),
                            .init(color: Color(red: 0.941, green: 0.761, blue: 0.227), location: 0.91),
                            .init(color: Color(red: 1.000, green: 0.824, blue: 0.180), location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.60, height: size * 0.60)
                .shadow(color: Color.cyan.opacity(whiteBackground ? 0.22 : 0.38), radius: size * 0.07)
        }
    }

    @ViewBuilder
    private func zipperSeamCluster(whiteBackground: Bool) -> some View {
        let toothColor = whiteBackground
            ? Color(red: 0.133, green: 0.431, blue: 0.745).opacity(0.28)
            : Color(red: 0.588, green: 0.843, blue: 1.000).opacity(0.32)
        VStack(spacing: max(1, size * 0.02)) {
            ForEach(0..<3, id: \.self) { idx in
                Capsule()
                    .fill(toothColor)
                    .frame(width: max(3, size * 0.055), height: max(1.5, size * 0.018))
                    .offset(x: idx.isMultiple(of: 2) ? -size * 0.024 : size * 0.024)
            }
        }
    }
}
