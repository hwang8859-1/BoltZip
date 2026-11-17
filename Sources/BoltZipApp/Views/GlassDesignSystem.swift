import SwiftUI

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
                .glassEffect(.regular.tint(.cyan.opacity(0.18)), in: Circle())

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
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.04, green: 0.07, blue: 0.14).opacity(0.75), Color(red: 0.08, green: 0.10, blue: 0.22).opacity(0.55), Color.clear]
                    : [Color.cyan.opacity(0.08), Color.indigo.opacity(0.09), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(isDark ? 0.18 : 0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 95)
                .offset(x: -240, y: -180)

            Circle()
                .fill(Color.indigo.opacity(isDark ? 0.20 : 0.14))
                .frame(width: 460, height: 460)
                .blur(radius: 105)
                .offset(x: 260, y: 120)

            Circle()
                .fill(Color.yellow.opacity(isDark ? 0.08 : 0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 85)
                .offset(x: 40, y: 240)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
