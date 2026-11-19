#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import Foundation

extension BoltIconArtwork {
    // MARK: - App Icon (Liquid / Deep Glass Plate + Signature Z-Bolt + Split Zipper Seal)

    public static func drawAppIcon(in ctx: CGContext, size s: CGFloat, whiteBackground: Bool) {
        let inset = s * 0.0975
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let corner = rect.width * 0.225
        let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let isMicro = s < 24
        let isDark = !whiteBackground

        // 1. Calibrated Drop Shadow (#0B1A33)
        ctx.saveGState()
        let shadowBlur: CGFloat = s >= 64 ? s * 0.046 : (isMicro ? s * 0.020 : s * 0.028)
        let shadowAlpha: CGFloat = isDark ? 0.50 : (isMicro ? 0.14 : 0.17)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.016),
            blur: shadowBlur,
            color: NSColor(srgbRed: 0.043, green: 0.102, blue: 0.200, alpha: shadowAlpha).cgColor
        )
        ctx.addPath(squircle)
        ctx.setFillColor(
            (isDark
                ? NSColor(srgbRed: 0.122, green: 0.216, blue: 0.376, alpha: 1.0)
                : (isMicro
                    ? NSColor(srgbRed: 0.867, green: 0.922, blue: 0.988, alpha: 1.0)
                    : NSColor(srgbRed: 0.969, green: 0.980, blue: 1.000, alpha: 1.0))
            ).cgColor
        )
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Clipped Glass Plate Layers (No inner badge frame)
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        let bgColors: [CGColor]
        if isDark {
            bgColors = [
                NSColor(srgbRed: 0.192, green: 0.333, blue: 0.541, alpha: 1.0).cgColor, // #31558A
                NSColor(srgbRed: 0.122, green: 0.216, blue: 0.376, alpha: 1.0).cgColor, // #1F3760
                NSColor(srgbRed: 0.063, green: 0.122, blue: 0.239, alpha: 1.0).cgColor  // #101F3D
            ]
        } else if isMicro {
            // Boost light contrast at 16px so the tile perimeter stays distinct on light surfaces
            bgColors = [
                NSColor(srgbRed: 0.929, green: 0.961, blue: 1.000, alpha: 1.0).cgColor, // #EDF5FF
                NSColor(srgbRed: 0.867, green: 0.922, blue: 0.988, alpha: 1.0).cgColor, // #DDEBFC
                NSColor(srgbRed: 0.792, green: 0.867, blue: 0.969, alpha: 1.0).cgColor  // #CADDF7
            ]
        } else {
            bgColors = [
                NSColor.white.cgColor,                                                  // #FFFFFF
                NSColor(srgbRed: 0.969, green: 0.980, blue: 1.000, alpha: 1.0).cgColor, // #F7FAFF
                NSColor(srgbRed: 0.914, green: 0.945, blue: 0.988, alpha: 1.0).cgColor  // #E9F1FC
            ]
        }
        if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 0.55, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Top-left cyan glass aura (suppressed at micro size)
        if !isMicro {
            drawCyanAura(in: ctx, rect: rect, isDark: isDark)
        }

        // Top glass dome specular highlight (dark mode y=1.0 -> y=0.52; subtle bevel wash on light >=48)
        if isDark && !isMicro {
            let topAlpha: CGFloat = s >= 128 ? 0.26 : (s >= 48 ? 0.22 : 0.14)
            let hlColors = [
                NSColor.white.withAlphaComponent(topAlpha).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let hlGrad = CGGradient(colorsSpace: colorSpace, colors: hlColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    hlGrad,
                    start: CGPoint(x: rect.midX, y: rect.maxY),
                    end: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.52),
                    options: []
                )
            }
        } else if !isDark && s >= 48 {
            let sheenAlpha: CGFloat = s >= 128 ? 0.22 : 0.16
            let hlColors = [
                NSColor.white.withAlphaComponent(sheenAlpha).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let hlGrad = CGGradient(colorsSpace: colorSpace, colors: hlColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    hlGrad,
                    start: CGPoint(x: rect.minX, y: rect.maxY),
                    end: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY),
                    options: []
                )
            }
        }

        // Bottom inner depth gradient
        let innerBottomColor = isDark
            ? NSColor.black.withAlphaComponent(0.28).cgColor
            : NSColor(srgbRed: 0.180, green: 0.329, blue: 0.549, alpha: 0.10).cgColor
        if let innerGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [NSColor.clear.cgColor, innerBottomColor] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                innerGrad,
                start: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.48),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )
        }

        // 3 & 4. Zipper Seal + Signature Z-Bolt
        drawForegroundEmblems(in: ctx, size: s, whiteBackground: whiteBackground)

        ctx.restoreGState()

        // 5. Specular Glass Refraction Rim & Crisp Outer Hairline
        drawRefractionRim(in: ctx, rect: rect, corner: corner, s: s, dark: isDark, clipPath: squircle)
    }

    /// Renders only the transparent foreground emblems (zipper seal + Z-Bolt)
    /// without any clipped background aura plate, so macOS 26 `actool` (`AppIcon.icon`)
    /// applies native Liquid Glass specular highlights cleanly around the artwork itself.
    public static func drawAppIconForeground(in ctx: CGContext, size s: CGFloat, whiteBackground: Bool) {
        drawForegroundEmblems(in: ctx, size: s, whiteBackground: whiteBackground)
    }

    private static func drawCyanAura(in ctx: CGContext, rect: CGRect, isDark: Bool) {
        let auraCenter = CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.76)
        let auraColor = isDark
            ? NSColor(srgbRed: 0.376, green: 0.804, blue: 1.000, alpha: 0.30).cgColor
            : NSColor(srgbRed: 0.431, green: 0.804, blue: 1.000, alpha: 0.26).cgColor
        if let aura = CGGradient(
            colorsSpace: colorSpace,
            colors: [auraColor, NSColor.clear.cgColor] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawRadialGradient(
                aura,
                startCenter: auraCenter,
                startRadius: 0,
                endCenter: auraCenter,
                endRadius: rect.width * 0.66,
                options: []
            )
        }
    }

    private static func drawForegroundEmblems(in ctx: CGContext, size s: CGFloat, whiteBackground: Bool) {
        let isDark = !whiteBackground
        if s >= 128 {
            let toothTint = isDark
                ? NSColor(srgbRed: 0.588, green: 0.843, blue: 1.000, alpha: 0.50)
                : NSColor(srgbRed: 0.133, green: 0.431, blue: 0.745, alpha: 0.50)
            drawZipperSeal(in: ctx, s: s, tint: toothTint)
        }

        let boltBounds = CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
        drawZBoltEmblem(
            in: ctx,
            bounds: boltBounds,
            whiteBackdrop: whiteBackground,
            strokeWeight: boltOpticalStrokeWidth(for: s)
        )
    }

    // MARK: - App Icon Vector Primitives

    private static func boltOpticalStrokeWidth(for s: CGFloat) -> CGFloat {
        let pct: CGFloat
        switch s {
        case ..<24:  pct = 2.30
        case ..<48:  pct = 1.35
        case ..<128: pct = 0.80
        default:     pct = 0.55
        }
        return s * (pct / 100.0)
    }

    private static func drawRefractionRim(
        in ctx: CGContext,
        rect: CGRect,
        corner: CGFloat,
        s: CGFloat,
        dark: Bool,
        clipPath: CGPath
    ) {
        let isMicro = s < 24
        let rimWidth: CGFloat
        if isMicro {
            rimWidth = max(0.80, s * 0.036)
        } else if s < 48 {
            rimWidth = max(0.95, s * 0.024)
        } else if s < 128 {
            rimWidth = max(1.0, s * 0.0135)
        } else {
            rimWidth = max(1.1, s * 0.011)
        }

        let rimInset = rimWidth * 0.45
        let rimRect = rect.insetBy(dx: rimInset, dy: rimInset)
        let rimCorner = max(1.0, corner - rimInset)
        let rimPath = CGPath(roundedRect: rimRect, cornerWidth: rimCorner, cornerHeight: rimCorner, transform: nil)

        // Outer hairline anchoring the glass silhouette before top specular catchlight
        let hairWidth = isMicro ? max(0.75, s * 0.012) : max(0.45, s * 0.004)
        let hairColor = dark
            ? NSColor.black.withAlphaComponent(0.26)
            : NSColor(srgbRed: 0.118, green: 0.220, blue: 0.384, alpha: isMicro ? 0.22 : 0.14)
        ctx.addPath(clipPath)
        ctx.setStrokeColor(hairColor.cgColor)
        ctx.setLineWidth(hairWidth)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(clipPath)
        ctx.clip()

        ctx.addPath(rimPath)
        ctx.setLineWidth(rimWidth)
        ctx.replacePathWithStrokedPath()
        ctx.clip()

        let rimTop = NSColor.white.withAlphaComponent(dark ? 0.80 : 0.94).cgColor
        let rimMid = NSColor.white.withAlphaComponent(0.06).cgColor
        let rimBot = NSColor.white.withAlphaComponent(dark ? 0.30 : 0.35).cgColor
        if let rimGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [rimTop, rimMid, rimMid, rimBot] as CFArray,
            locations: [0.0, 0.42, 0.72, 1.0]
        ) {
            ctx.drawLinearGradient(
                rimGrad,
                start: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY),
                end: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()
    }

    private static func drawZipperSeal(in ctx: CGContext, s: CGFloat, tint: NSColor) {
        let toothCount = 4
        let centerX = s * 0.5
        let toothW = s * 0.030
        let toothH = max(1.0, s * 0.009)
        let halfGap = s * 0.0035
        let step = s * 0.023
        let span = CGFloat(toothCount - 1) * step

        // Symmetrical top and bottom clusters inside the 9.75% glass tile without colliding with bolt
        let topAnchor = s * 0.864
        let botAnchor = s * 0.136

        ctx.saveGState()
        let threadW = max(0.75, s * 0.0035)
        ctx.setStrokeColor(tint.withAlphaComponent(tint.alphaComponent * 0.52).cgColor)
        ctx.setLineWidth(threadW)

        ctx.move(to: CGPoint(x: centerX, y: topAnchor + s * 0.009))
        ctx.addLine(to: CGPoint(x: centerX, y: topAnchor - span - s * 0.009))
        ctx.move(to: CGPoint(x: centerX, y: botAnchor - s * 0.009))
        ctx.addLine(to: CGPoint(x: centerX, y: botAnchor + span + s * 0.009))
        ctx.strokePath()

        ctx.setFillColor(tint.cgColor)
        for i in 0..<toothCount {
            let yTop = topAnchor - CGFloat(i) * step
            let yBot = botAnchor + CGFloat(i) * step
            let isLeft = (i % 2 == 0)
            let x = isLeft ? (centerX - halfGap - toothW) : (centerX + halfGap)

            let topRect = CGRect(x: x, y: yTop - toothH * 0.5, width: toothW, height: toothH)
            let botRect = CGRect(x: x, y: yBot - toothH * 0.5, width: toothW, height: toothH)
            ctx.addPath(CGPath(roundedRect: topRect, cornerWidth: toothH * 0.5, cornerHeight: toothH * 0.5, transform: nil))
            ctx.addPath(CGPath(roundedRect: botRect, cornerWidth: toothH * 0.5, cornerHeight: toothH * 0.5, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private static func drawZBoltEmblem(
        in ctx: CGContext,
        bounds: CGRect,
        whiteBackdrop: Bool,
        strokeWeight: CGFloat
    ) {
        let s = min(bounds.width, bounds.height)
        let ox = bounds.midX - s * 0.5
        let oy = bounds.midY - s * 0.5

        let zBolt = CGMutablePath()
        let pts: [(CGFloat, CGFloat)] = [
            (0.32, 0.79),
            (0.80, 0.79),
            (0.51, 0.53),
            (0.67, 0.53),
            (0.41, 0.32),
            (0.74, 0.32),
            (0.68, 0.20),
            (0.20, 0.20),
            (0.49, 0.46),
            (0.33, 0.46),
            (0.59, 0.67),
            (0.26, 0.67)
        ]
        for (i, pt) in pts.enumerated() {
            let p = CGPoint(x: ox + s * pt.0, y: oy + s * pt.1)
            if i == 0 {
                zBolt.move(to: p)
            } else {
                zBolt.addLine(to: p)
            }
        }
        zBolt.closeSubpath()

        var xform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .rotated(by: -0.105)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        let tiltedBolt = zBolt.copy(using: &xform) ?? zBolt

        // 6-stop cyan -> amber transition bypassing muted gray RGB interpolation zone
        let boltStops: [CGColor] = whiteBackdrop
            ? [
                NSColor(srgbRed: 0.000, green: 0.796, blue: 0.961, alpha: 1.0).cgColor, // #00CBF5
                NSColor(srgbRed: 0.231, green: 0.635, blue: 1.000, alpha: 1.0).cgColor, // #3BA2FF
                NSColor(srgbRed: 0.353, green: 0.486, blue: 1.000, alpha: 1.0).cgColor, // #5A7CFF
                NSColor(srgbRed: 0.784, green: 0.667, blue: 0.314, alpha: 1.0).cgColor, // #C8AA50
                NSColor(srgbRed: 0.941, green: 0.761, blue: 0.227, alpha: 1.0).cgColor, // #F0C23A
                NSColor(srgbRed: 1.000, green: 0.824, blue: 0.180, alpha: 1.0).cgColor  // #FFD22E
            ]
            : [
                NSColor(srgbRed: 0.498, green: 0.941, blue: 1.000, alpha: 1.0).cgColor, // #7FF0FF
                NSColor(srgbRed: 0.486, green: 0.784, blue: 1.000, alpha: 1.0).cgColor, // #7CC8FF
                NSColor(srgbRed: 0.471, green: 0.698, blue: 1.000, alpha: 1.0).cgColor, // #78B2FF
                NSColor(srgbRed: 0.878, green: 0.769, blue: 0.392, alpha: 1.0).cgColor, // #E0C464
                NSColor(srgbRed: 0.969, green: 0.816, blue: 0.239, alpha: 1.0).cgColor, // #F7D03D
                NSColor(srgbRed: 1.000, green: 0.839, blue: 0.161, alpha: 1.0).cgColor  // #FFD629
            ]
        guard let bGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: boltStops as CFArray,
            locations: [0.00, 0.34, 0.60, 0.80, 0.91, 1.00]
        ) else { return }

        let gradStart = CGPoint(x: ox + s * 0.28, y: oy + s * 0.76)
        let gradEnd = CGPoint(x: ox + s * 0.72, y: oy + s * 0.24)
        let isMicro = bounds.width < 24 * 0.88

        ctx.saveGState()
        if !isMicro {
            let shadowColor = whiteBackdrop
                ? NSColor(srgbRed: 0.078, green: 0.235, blue: 0.471, alpha: 0.16).cgColor
                : NSColor(srgbRed: 0.118, green: 0.471, blue: 0.784, alpha: 0.18).cgColor
            ctx.setShadow(
                offset: CGSize(width: 0, height: -s * 0.010),
                blur: s * (whiteBackdrop ? 0.030 : 0.050),
                color: shadowColor
            )
        }

        // Transparency layer lets fill + same-gradient round-joined optical stroke share one smooth silhouette & shadow
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        if strokeWeight > 0 {
            let strokedBolt = tiltedBolt.copy(
                strokingWithWidth: strokeWeight,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 4.0
            )
            ctx.saveGState()
            ctx.addPath(strokedBolt)
            ctx.clip()
            ctx.drawLinearGradient(
                bGrad,
                start: gradStart,
                end: gradEnd,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(tiltedBolt)
        ctx.clip()
        ctx.drawLinearGradient(
            bGrad,
            start: gradStart,
            end: gradEnd,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
#endif
