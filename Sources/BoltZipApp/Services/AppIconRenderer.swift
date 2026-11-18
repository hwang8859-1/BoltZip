import AppKit

/// Procedural NSImage renderer for BoltZip's Dock / About / Settings app icon,
/// supporting both the classic deep-indigo background and the crisp white background
/// while keeping the cyan-periwinkle-gold tilted Z-bolt emblem intact.
@MainActor
enum BoltAppIconRenderer {
    private static var cachedDarkIcon: NSImage?
    private static var cachedWhiteIcon: NSImage?

    static func apply(whiteBackground: Bool) {
        guard let app = NSApp as NSApplication? else { return }
        app.applicationIconImage = appIconImage(whiteBackground: whiteBackground, size: 512)
    }

    static func appIconImage(whiteBackground: Bool, size: CGFloat = 512) -> NSImage {
        if size == 512 {
            if whiteBackground, let cachedWhiteIcon {
                return cachedWhiteIcon
            }
            if !whiteBackground, let cachedDarkIcon {
                return cachedDarkIcon
            }
        }
        let image = renderIcon(size: size, whiteBackground: whiteBackground)
        if size == 512 {
            if whiteBackground {
                cachedWhiteIcon = image
            } else {
                cachedDarkIcon = image
            }
        }
        return image
    }

    static func renderIcon(size: CGFloat, whiteBackground: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawIcon(in: ctx, size: size, whiteBackground: whiteBackground)
            return true
        }
        return img
    }

    private static func drawIcon(in ctx: CGContext, size s: CGFloat, whiteBackground: Bool) {
        let inset = s * 0.08
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let corner = rect.width * 0.225
        let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let cs = CGColorSpaceCreateDeviceRGB()

        // Outer drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.025),
            blur: s * 0.05,
            color: NSColor.black.withAlphaComponent(whiteBackground ? 0.22 : 0.38).cgColor
        )
        ctx.addPath(squircle)
        ctx.setFillColor(
            (whiteBackground
                ? NSColor.white
                : NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1.0)
            ).cgColor
        )
        ctx.fillPath()
        ctx.restoreGState()

        // Clip to squircle
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        let bgColors: [CGColor] = whiteBackground
            ? [
                NSColor.white.cgColor,
                NSColor(calibratedRed: 0.97, green: 0.985, blue: 1.0, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.935, green: 0.96, blue: 0.99, alpha: 1.0).cgColor
            ]
            : [
                NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.24, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.37, alpha: 1.0).cgColor,
                NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.13, alpha: 1.0).cgColor
            ]
        if let grad = CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: [0.0, 0.52, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
        }

        // Soft radial cyan/indigo ambient glow behind the emblem
        let auraColors: [CGColor] = whiteBackground
            ? [
                NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.98, alpha: 0.14).cgColor,
                NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.94, alpha: 0.05).cgColor,
                NSColor.clear.cgColor
            ]
            : [
                NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.98, alpha: 0.28).cgColor,
                NSColor(calibratedRed: 0.39, green: 0.40, blue: 0.95, alpha: 0.12).cgColor,
                NSColor.clear.cgColor
            ]
        if let aura = CGGradient(colorsSpace: cs, colors: auraColors as CFArray, locations: [0.0, 0.5, 1.0]) {
            ctx.drawRadialGradient(
                aura,
                startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
                startRadius: 0,
                endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
                endRadius: s * 0.44,
                options: []
            )
        }

        if !whiteBackground {
            let hlColors = [
                NSColor.white.withAlphaComponent(0.22).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let hlGrad = CGGradient(colorsSpace: cs, colors: hlColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    hlGrad,
                    start: CGPoint(x: s * 0.5, y: rect.maxY),
                    end: CGPoint(x: s * 0.5, y: rect.midY),
                    options: []
                )
            }
        }

        // Exact tilted Z-bolt emblem shared with GenerateIcon + FinderSync + BoltZMark
        let zBolt = CGMutablePath()
        zBolt.move(to: CGPoint(x: s * 0.33, y: s * 0.78))
        zBolt.addLine(to: CGPoint(x: s * 0.78, y: s * 0.78))
        zBolt.addLine(to: CGPoint(x: s * 0.51, y: s * 0.53))
        zBolt.addLine(to: CGPoint(x: s * 0.65, y: s * 0.53))
        zBolt.addLine(to: CGPoint(x: s * 0.42, y: s * 0.33))
        zBolt.addLine(to: CGPoint(x: s * 0.72, y: s * 0.33))
        zBolt.addLine(to: CGPoint(x: s * 0.67, y: s * 0.21))
        zBolt.addLine(to: CGPoint(x: s * 0.21, y: s * 0.21))
        zBolt.addLine(to: CGPoint(x: s * 0.48, y: s * 0.46))
        zBolt.addLine(to: CGPoint(x: s * 0.34, y: s * 0.46))
        zBolt.addLine(to: CGPoint(x: s * 0.57, y: s * 0.66))
        zBolt.addLine(to: CGPoint(x: s * 0.28, y: s * 0.66))
        zBolt.closeSubpath()

        var xform = CGAffineTransform(translationX: s * 0.5, y: s * 0.5)
            .rotated(by: -0.11)
            .translatedBy(x: -s * 0.5, y: -s * 0.5)
        let tiltedBolt = zBolt.copy(using: &xform) ?? zBolt

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.015),
            blur: s * (whiteBackground ? 0.045 : 0.075),
            color: (whiteBackground
                ? NSColor(calibratedRed: 0.06, green: 0.36, blue: 0.68, alpha: 0.28)
                : NSColor(calibratedRed: 0.22, green: 0.78, blue: 1.0, alpha: 0.75)
            ).cgColor
        )
        ctx.addPath(tiltedBolt)
        ctx.clip()

        let boltColors = [
            NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.98, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.46, green: 0.64, blue: 0.98, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.12, alpha: 1.0).cgColor
        ] as CFArray
        if let bGrad = CGGradient(colorsSpace: cs, colors: boltColors, locations: [0.0, 0.45, 1.0]) {
            ctx.drawLinearGradient(
                bGrad,
                start: CGPoint(x: s * 0.26, y: s * 0.78),
                end: CGPoint(x: s * 0.74, y: s * 0.21),
                options: []
            )
        }
        ctx.restoreGState()

        // Specular / definition stroke around Z-Bolt
        ctx.addPath(tiltedBolt)
        ctx.setStrokeColor(
            (whiteBackground
                ? NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.72, alpha: 0.22)
                : NSColor.white.withAlphaComponent(0.38)
            ).cgColor
        )
        ctx.setLineWidth(max(0.8, s * 0.008))
        ctx.strokePath()

        // Outer squircle border rim
        ctx.addPath(squircle)
        ctx.setStrokeColor(
            (whiteBackground
                ? NSColor(white: 0.76, alpha: 0.85)
                : NSColor.white.withAlphaComponent(0.30)
            ).cgColor
        )
        ctx.setLineWidth(max(1.0, s * 0.012))
        ctx.strokePath()

        ctx.restoreGState()
    }
}
