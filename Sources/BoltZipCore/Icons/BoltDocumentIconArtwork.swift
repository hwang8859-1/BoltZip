#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import Foundation

extension BoltIconArtwork {
    // MARK: - Document Icon v2 (Unified Paper + Seal + Dark Stamp + Identity Bar + Optical Scaling)

    public static func drawDocumentIcon(
        in ctx: CGContext,
        size s: CGFloat,
        kind: BoltDocumentIconKind,
        isDark: Bool = false,
        opticalScale: BoltIconScale? = nil
    ) {
        let level = opticalScale ?? BoltIconScale(pixelSize: Int(s.rounded()))
        let k = s / 128.0
        let fam = kind.family
        let ramp = fam.ramp
        let c1 = NSColor(srgbRed: ramp.c1.0, green: ramp.c1.1, blue: ramp.c1.2, alpha: 1.0)
        let c2 = NSColor(srgbRed: ramp.c2.0, green: ramp.c2.1, blue: ramp.c2.2, alpha: 1.0)

        let pagePath = makeV2PagePath(scale: k)
        let small = (level == .small || level == .micro)

        // 1. Paper Shadow
        ctx.saveGState()
        if isDark {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -3.0 * k),
                blur: 3.4 * k,
                color: NSColor.black.withAlphaComponent(0.55).cgColor
            )
        } else if small {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -5.0 * k),
                blur: 8.0 * k,
                color: NSColor(srgbRed: 0.043, green: 0.071, blue: 0.125, alpha: 0.30).cgColor
            )
        } else {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -2.8 * k),
                blur: 3.0 * k,
                color: NSColor(srgbRed: 0.043, green: 0.071, blue: 0.125, alpha: 0.18).cgColor
            )
        }
        ctx.addPath(pagePath)
        ctx.setFillColor((isDark ? NSColor(srgbRed: 0.078, green: 0.102, blue: 0.161, alpha: 1.0) : NSColor.white).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Clipped Interior Layers
        ctx.saveGState()
        ctx.addPath(pagePath)
        ctx.clip()

        // 2a. Paper three-stop gradient (128x128 grid: (14,8) -> (39,120))
        let paperColors: [CGColor] = isDark
            ? [
                NSColor(srgbRed: 0.141, green: 0.173, blue: 0.251, alpha: 1.0).cgColor, // #242C40
                NSColor(srgbRed: 0.102, green: 0.133, blue: 0.204, alpha: 1.0).cgColor, // #1A2234
                NSColor(srgbRed: 0.078, green: 0.102, blue: 0.161, alpha: 1.0).cgColor  // #141A29
            ]
            : [
                NSColor.white.cgColor,                                                  // #FFFFFF
                NSColor(srgbRed: 0.969, green: 0.976, blue: 0.992, alpha: 1.0).cgColor, // #F7F9FD
                NSColor(srgbRed: 0.929, green: 0.949, blue: 0.980, alpha: 1.0).cgColor  // #EDF2FA
            ]
        if let pGrad = CGGradient(colorsSpace: colorSpace, colors: paperColors as CFArray, locations: [0.0, 0.58, 1.0]) {
            ctx.drawLinearGradient(
                pGrad,
                start: pt(14, 8, k: k),
                end: pt(39, 120, k: k),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // 2b. Top specular glass wash (x=14 y=8 w=100 h=40 in SVG coords)
        let washColors = [
            NSColor.white.withAlphaComponent(isDark ? 0.10 : 0.55).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ] as CFArray
        if let wGrad = CGGradient(colorsSpace: colorSpace, colors: washColors, locations: [0.0, 1.0]) {
            ctx.saveGState()
            ctx.clip(to: svgRect(14, 8, 100, 40, k: k))
            ctx.drawLinearGradient(wGrad, start: pt(64, 8, k: k), end: pt(64, 48, k: k), options: [])
            ctx.restoreGState()
        }

        // 2c. Layer 2 — Brand Seal (BoltZip cyan zipper, omitted at 16–40px)
        if level == .full || level == .medium {
            drawV2Seal(in: ctx, cx: 64, topSVG: 16, bottomSVG: 42, withTeeth: level == .full, k: k)
        }

        // 2d. Layer 3 & 4 — Dark Stamp + Watermark/Glyph + Format Label + Identity Line
        let st: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
        switch level {
        case .small:
            st = (31, 40, 66, 68, 18)
        case .micro:
            st = (28, 36, 72, 76, 20)
        case .medium, .full:
            st = (34, 44, 60, 64, 16)
        }
        drawV2Stamp(
            in: ctx,
            st: st,
            kind: kind,
            fam: fam,
            c1: c1,
            c2: c2,
            level: level,
            isDark: isDark,
            k: k
        )

        ctx.restoreGState()

        // 3. Layer 1 Fold Detail (Full tier only)
        if level == .full {
            drawV2Fold(in: ctx, c1: c1, isDark: isDark, k: k)
        }

        // 4. Outer crisp border (optical stroke width)
        let strokeColor: NSColor = isDark
            ? NSColor.white.withAlphaComponent(small ? 0.24 : 0.15)
            : NSColor(srgbRed: 0.110, green: 0.169, blue: 0.267, alpha: small ? 0.30 : 0.13)
        let strokeGridW: CGFloat = switch level {
        case .micro: 8.0
        case .small: 4.0
        case .medium, .full: 1.1
        }
        ctx.addPath(pagePath)
        ctx.setStrokeColor(strokeColor.cgColor)
        ctx.setLineWidth(strokeGridW * k)
        ctx.strokePath()
    }

    // MARK: - v2 Document Icon Helpers (128x128 SVG Grid -> CoreGraphics Y-Up)

    private static func pt(_ x: CGFloat, _ ySVG: CGFloat, k: CGFloat) -> CGPoint {
        CGPoint(x: x * k, y: (128.0 - ySVG) * k)
    }

    private static func svgRect(_ x: CGFloat, _ ySVG: CGFloat, _ w: CGFloat, _ h: CGFloat, k: CGFloat) -> CGRect {
        CGRect(x: x * k, y: (128.0 - ySVG - h) * k, width: w * k, height: h * k)
    }

    private static func makeV2PagePath(scale k: CGFloat) -> CGPath {
        // M32 8 H92 L114 30 V102 Q114 120 96 120 H32 Q14 120 14 102 V26 Q14 8 32 8 Z
        let p = CGMutablePath()
        p.move(to: pt(32, 8, k: k))
        p.addLine(to: pt(92, 8, k: k))
        p.addLine(to: pt(114, 30, k: k))
        p.addLine(to: pt(114, 102, k: k))
        p.addQuadCurve(to: pt(96, 120, k: k), control: pt(114, 120, k: k))
        p.addLine(to: pt(32, 120, k: k))
        p.addQuadCurve(to: pt(14, 102, k: k), control: pt(14, 120, k: k))
        p.addLine(to: pt(14, 26, k: k))
        p.addQuadCurve(to: pt(32, 8, k: k), control: pt(14, 8, k: k))
        p.closeSubpath()
        return p
    }

    private static func drawV2Seal(
        in ctx: CGContext,
        cx: CGFloat,
        topSVG: CGFloat,
        bottomSVG: CGFloat,
        withTeeth: Bool,
        k: CGFloat
    ) {
        let cyan = NSColor(srgbRed: 0.310, green: 0.765, blue: 1.000, alpha: 1.0) // #4FC3FF
        ctx.saveGState()
        ctx.setStrokeColor(cyan.withAlphaComponent(withTeeth ? 0.48 : 0.32).cgColor)
        ctx.setLineWidth(1.2 * k)
        ctx.setLineCap(.round)
        ctx.move(to: pt(cx, topSVG, k: k))
        ctx.addLine(to: pt(cx, bottomSVG, k: k))
        ctx.strokePath()

        if withTeeth {
            let count = 5
            let step = (bottomSVG - topSVG - 3.6) / CGFloat(count - 1)
            ctx.setFillColor(cyan.withAlphaComponent(0.58).cgColor)
            for i in 0..<count {
                let y = topSVG + CGFloat(i) * step
                let x = (i % 2 == 0) ? (cx - 9.6) : (cx + 1.2)
                let tooth = svgRect(x, y, 8.4, 3.6, k: k)
                let cr = 1.7 * k
                ctx.addPath(CGPath(roundedRect: tooth, cornerWidth: cr, cornerHeight: cr, transform: nil))
                ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }

    private static func drawV2Stamp(
        in ctx: CGContext,
        st: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat),
        kind: BoltDocumentIconKind,
        fam: BoltIconFamily,
        c1: NSColor,
        c2: NSColor,
        level: BoltIconScale,
        isDark: Bool,
        k: CGFloat
    ) {
        let stampRect = svgRect(st.x, st.y, st.w, st.h, k: k)
        let cr = st.rx * k
        let stampPath = CGPath(roundedRect: stampRect, cornerWidth: cr, cornerHeight: cr, transform: nil)

        // Stamp background gradient (#1E2E4E -> #0C1526 in light, #0B1224 -> #050912 in dark)
        ctx.saveGState()
        ctx.addPath(stampPath)
        ctx.clip()

        let sColors: [CGColor] = isDark
            ? [
                NSColor(srgbRed: 0.043, green: 0.071, blue: 0.141, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.020, green: 0.035, blue: 0.071, alpha: 1.0).cgColor
            ]
            : [
                NSColor(srgbRed: 0.118, green: 0.180, blue: 0.306, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.047, green: 0.082, blue: 0.149, alpha: 1.0).cgColor
            ]
        if let sGrad = CGGradient(colorsSpace: colorSpace, colors: sColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                sGrad,
                start: pt(st.x + 0.15 * st.w, st.y, k: k),
                end: pt(st.x + 0.70 * st.w, st.y + st.h, k: k),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Top curved inner highlight arc
        let x0 = st.x + 0.7
        let y0 = st.y + 0.7
        let w0 = st.w - 1.4
        let arc = CGMutablePath()
        arc.move(to: pt(x0, y0 + st.rx * 1.7, k: k))
        arc.addQuadCurve(to: pt(x0 + st.rx, y0, k: k), control: pt(x0, y0, k: k))
        arc.addLine(to: pt(x0 + w0 - st.rx, y0, k: k))
        arc.addQuadCurve(to: pt(x0 + w0, y0 + st.rx * 1.7, k: k), control: pt(x0 + w0, y0, k: k))
        ctx.addPath(arc)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
        ctx.setLineWidth(1.3 * k)
        ctx.strokePath()

        let cx = st.x + st.w * 0.5
        let cy = st.y + st.h * 0.5

        if level == .full || level == .medium {
            let wmScale: CGFloat = (level == .full) ? 0.86 : 0.82
            let wmAlpha: CGFloat = (level == .full) ? 0.10 : 0.14
            drawV2Motif(in: ctx, motif: fam.motif, cx: cx, cySVG: cy - 2.0, motifScale: wmScale, color: c1, alpha: wmAlpha, glyphMode: false, k: k)
            drawV2Label(kind.badgeLabel, cx: cx, cySVG: cy + 1.5, k: k)
        } else {
            let gScale: CGFloat = (level == .micro) ? 1.10 : 1.22
            drawV2Motif(in: ctx, motif: fam.motif, cx: cx, cySVG: cy - 1.0, motifScale: gScale, color: .white, alpha: 0.95, glyphMode: true, k: k)
        }

        // Layer 4 — Identity Bar (55% of stamp width, 9px above bottom edge in 128 grid)
        let barW = st.w * 0.55
        let barH: CGFloat = (level == .micro) ? 4.4 : 3.4
        let bx = cx - barW * 0.5
        let by = st.y + st.h - 9.0 - barH * 0.5
        let barRect = svgRect(bx, by, barW, barH, k: k)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barRect.height * 0.5, cornerHeight: barRect.height * 0.5, transform: nil)
        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()
        if let fGrad = CGGradient(colorsSpace: colorSpace, colors: [c1.cgColor, c2.cgColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                fGrad,
                start: CGPoint(x: barRect.minX, y: barRect.minY),
                end: CGPoint(x: barRect.maxX, y: barRect.maxY),
                options: []
            )
        }
        ctx.restoreGState()

        ctx.restoreGState()

        // Outer stamp hairline border
        ctx.addPath(stampPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
        ctx.setLineWidth(1.0 * k)
        ctx.strokePath()
    }

    private static func drawV2Motif(
        in ctx: CGContext,
        motif: BoltDocumentIconMotif,
        cx: CGFloat,
        cySVG: CGFloat,
        motifScale ms: CGFloat,
        color: NSColor,
        alpha: CGFloat,
        glyphMode: Bool,
        k: CGFloat
    ) {
        ctx.saveGState()
        let lineW = (glyphMode ? 8.0 : 2.2) * k
        ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
        ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(lineW)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch motif {
        case .archiveBrackets:
            let r = (glyphMode ? 20.0 : 21.0) * ms
            let arm = 12.0 * ms
            let corners: [(CGFloat, CGFloat)] = [(-1, 1), (1, 1), (-1, -1), (1, -1)]
            for (sx, sy) in corners {
                let x = cx + sx * r
                let y = cySVG + sy * r
                ctx.move(to: pt(x - sx * arm, y, k: k))
                ctx.addLine(to: pt(x, y, k: k))
                ctx.addLine(to: pt(x, y - sy * arm, k: k))
                ctx.strokePath()
            }

        case .tarLayers:
            let w = (glyphMode ? 46.0 : 36.0) * ms
            let h: CGFloat = glyphMode ? 6.6 : 3.6
            let gap = (glyphMode ? 13.0 : 9.0) * ms
            for row in [-1.0, 0.0, 1.0] {
                let r = svgRect(cx - w * 0.5, cySVG + CGFloat(row) * gap - h * 0.5, w, h, k: k)
                let cr = r.height * 0.5
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil))
                ctx.fillPath()
            }

        case .streamChevrons:
            if glyphMode {
                let hh = 15.0 * ms
                let w = 8.0 * ms
                let base = 16.0 * ms
                ctx.move(to: pt(cx - base, cySVG - hh, k: k))
                ctx.addLine(to: pt(cx - base + w, cySVG, k: k))
                ctx.addLine(to: pt(cx - base, cySVG + hh, k: k))
                ctx.move(to: pt(cx + base, cySVG - hh, k: k))
                ctx.addLine(to: pt(cx + base - w, cySVG, k: k))
                ctx.addLine(to: pt(cx + base, cySVG + hh, k: k))
                ctx.strokePath()
            } else {
                let hh = 9.0 * ms
                let w = 5.5 * ms
                let gap = 5.0 * ms
                let base = 15.0 * ms
                for idx in 0..<2 {
                    let lx = cx - base - CGFloat(idx) * gap
                    ctx.move(to: pt(lx, cySVG - hh, k: k))
                    ctx.addLine(to: pt(lx + w, cySVG, k: k))
                    ctx.addLine(to: pt(lx, cySVG + hh, k: k))

                    let rx = cx + base + CGFloat(idx) * gap + w
                    ctx.move(to: pt(rx, cySVG - hh, k: k))
                    ctx.addLine(to: pt(rx - w, cySVG, k: k))
                    ctx.addLine(to: pt(rx, cySVG + hh, k: k))
                }
                ctx.strokePath()
            }

        case .diskRings:
            let r1 = (glyphMode ? 16.0 : 17.0) * ms
            let r2 = (glyphMode ? 26.0 : 23.0) * ms
            ctx.strokeEllipse(in: svgRect(cx - r1, cySVG - r1, r1 * 2, r1 * 2, k: k))
            ctx.strokeEllipse(in: svgRect(cx - r2, cySVG - r2, r2 * 2, r2 * 2, k: k))
        }
        ctx.restoreGState()
    }

    private static func drawV2Label(_ text: String, cx: CGFloat, cySVG: CGFloat, k: CGFloat) {
        let len = text.count
        let gridFontSize: CGFloat = len <= 2 ? 26.0 : (len == 3 ? 20.0 : 15.0)
        var fontSize = gridFontSize * k
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor

        let maxLabelWidth = 52.0 * k
        var font = NSFont(descriptor: roundedDescriptor, size: fontSize) ?? baseFont
        let kern = 0.4 * k

        while fontSize > 4.0 {
            let f = NSFont(descriptor: roundedDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let w = (text as NSString).size(withAttributes: [.font: f, .kern: kern]).width
            if w <= maxLabelWidth {
                font = f
                break
            }
            fontSize -= 0.5
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: kern
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let measured = str.size()
        let centerCG = pt(cx, cySVG, k: k)
        // Align by uppercase capHeight so labels sit at true geometric vertical center
        let baselineY = centerCG.y - font.capHeight * 0.5
        let origin = NSPoint(
            x: centerCG.x - measured.width * 0.5,
            y: baselineY + font.descender
        )
        str.draw(at: origin)
    }

    private static func drawV2Fold(in ctx: CGContext, c1: NSColor, isDark: Bool, k: CGFloat) {
        let fold = CGMutablePath()
        fold.move(to: pt(92, 8, k: k))
        fold.addLine(to: pt(114, 30, k: k))
        fold.addLine(to: pt(92, 30, k: k))
        fold.closeSubpath()

        ctx.addPath(fold)
        ctx.setFillColor(c1.withAlphaComponent(isDark ? 0.22 : 0.16).cgColor)
        ctx.fillPath()

        let edgeColor: NSColor = isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor(srgbRed: 0.110, green: 0.169, blue: 0.267, alpha: 0.16)
        ctx.move(to: pt(92, 8, k: k))
        ctx.addLine(to: pt(92, 30, k: k))
        ctx.addLine(to: pt(114, 30, k: k))
        ctx.setStrokeColor(edgeColor.cgColor)
        ctx.setLineWidth(1.0 * k)
        ctx.strokePath()

        let diagColor: NSColor = isDark ? NSColor.white.withAlphaComponent(0.24) : NSColor(srgbRed: 0.110, green: 0.169, blue: 0.267, alpha: 0.20)
        ctx.move(to: pt(92, 8, k: k))
        ctx.addLine(to: pt(114, 30, k: k))
        ctx.setStrokeColor(diagColor.cgColor)
        ctx.setLineWidth(1.0 * k)
        ctx.strokePath()
    }
}
#endif
