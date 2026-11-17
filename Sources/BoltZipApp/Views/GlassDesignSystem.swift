import SwiftUI

struct BoltAmbientBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.cyan.opacity(0.08),
                    Color.indigo.opacity(0.09),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -240, y: -180)

            Circle()
                .fill(Color.indigo.opacity(0.14))
                .frame(width: 460, height: 460)
                .blur(radius: 100)
                .offset(x: 260, y: 120)

            Circle()
                .fill(Color.yellow.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 40, y: 240)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
