import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_dmg_bg.swift <output_tiff_path> [version_label]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let versionLabel = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "macOS"
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let logicalW: CGFloat = 660
let logicalH: CGFloat = 410

func renderBackground(scale: Int) -> Data? {
    let pxW = Int(logicalW) * scale
    let pxH = Int(logicalH) * scale

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxW,
        pixelsHigh: pxH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: logicalW, height: logicalH)

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()

    // Helper converting top-left Finder coordinates to bottom-left CoreGraphics coordinates.
    func y(_ topY: CGFloat) -> CGFloat { logicalH - topY }
    func rectFromTop(_ x: CGFloat, _ topY: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: logicalH - topY - h, width: w, height: h)
    }

    // 1. Soft studio cool sky-slate base gradient (high readability in Light & Dark Finder)
    let bgColors = [
        NSColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1.0).cgColor,
        NSColor(red: 0.91, green: 0.94, blue: 0.99, alpha: 1.0).cgColor,
        NSColor(red: 0.87, green: 0.91, blue: 0.98, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: 0, y: logicalH),
            end: CGPoint(x: logicalW, y: 0),
            options: []
        )
    }

    // 2. Ambient top-center cyan/indigo glow
    let auraColors = [
        NSColor(red: 0.14, green: 0.62, blue: 0.98, alpha: 0.14).cgColor,
        NSColor(red: 0.36, green: 0.42, blue: 0.96, alpha: 0.06).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let aura = CGGradient(colorsSpace: cs, colors: auraColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawRadialGradient(
            aura,
            startCenter: CGPoint(x: logicalW * 0.5, y: y(160)),
            startRadius: 0,
            endCenter: CGPoint(x: logicalW * 0.5, y: y(160)),
            endRadius: 340,
            options: []
        )
    }

    // 3. Soft translucent halo cards behind BoltZip.app (x=180) and Applications (x=480)
    //    Includes generous bottom padding so Finder's icon label sits inside a high-contrast light plate.
    for cx in [CGFloat(180), CGFloat(480)] {
        let cardRect = rectFromTop(cx - 92, 102, 184, 188)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 24, cornerHeight: 24, transform: nil)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 16,
            color: NSColor(red: 0.08, green: 0.16, blue: 0.34, alpha: 0.08).cgColor
        )
        ctx.addPath(cardPath)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.76).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.setStrokeColor(NSColor(red: 0.68, green: 0.78, blue: 0.92, alpha: 0.55).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 4. Center vector install arrow connecting BoltZip.app -> Applications (aligned with icon center y_top=178)
    let arrowCenterY = y(178)
    let pillRect = rectFromTop(294, 152, 72, 52)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -3),
        blur: 12,
        color: NSColor(red: 0.14, green: 0.45, blue: 0.95, alpha: 0.22).cgColor
    )
    ctx.addPath(pillPath)
    ctx.clip()
    let pillGradColors = [
        NSColor(red: 0.12, green: 0.66, blue: 0.96, alpha: 1.0).cgColor,
        NSColor(red: 0.24, green: 0.44, blue: 0.94, alpha: 1.0).cgColor
    ] as CFArray
    if let pillGrad = CGGradient(colorsSpace: cs, colors: pillGradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            pillGrad,
            start: CGPoint(x: pillRect.minX, y: pillRect.maxY),
            end: CGPoint(x: pillRect.maxX, y: pillRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp white right-pointing arrow inside the pill
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(3.2)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 315, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: 344, y: arrowCenterY))
    ctx.move(to: CGPoint(x: 334, y: arrowCenterY + 10))
    ctx.addLine(to: CGPoint(x: 345, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: 334, y: arrowCenterY - 10))
    ctx.strokePath()
    ctx.restoreGState()

    // Subtle dashed connector guides flanking the center arrow pill
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.28, green: 0.46, blue: 0.78, alpha: 0.28).cgColor)
    ctx.setLineWidth(1.6)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [4, 5])
    ctx.move(to: CGPoint(x: 274, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: 290, y: arrowCenterY))
    ctx.move(to: CGPoint(x: 370, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: 386, y: arrowCenterY))
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Top brand header + clear bilingual instruction
    let headerPara = NSMutableParagraphStyle()
    headerPara.alignment = .center

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .bold),
        .foregroundColor: NSColor(red: 0.08, green: 0.13, blue: 0.26, alpha: 1.0),
        .paragraphStyle: headerPara
    ]
    let titleStr = NSAttributedString(string: "BoltZip  \(versionLabel)", attributes: titleAttrs)
    titleStr.draw(in: rectFromTop(0, 26, logicalW, 28))

    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        .foregroundColor: NSColor(red: 0.26, green: 0.34, blue: 0.48, alpha: 0.92),
        .paragraphStyle: headerPara
    ]
    let subStr = NSAttributedString(
        string: "将 BoltZip 拖入右侧「Applications / 应用程序」即可安装 · Drag to Applications",
        attributes: subAttrs
    )
    subStr.draw(in: rectFromTop(20, 56, logicalW - 40, 22))

    // 6. Subtle bottom tip pill
    let footerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(red: 0.32, green: 0.40, blue: 0.54, alpha: 0.85),
        .paragraphStyle: headerPara
    ]
    let footerStr = NSAttributedString(
        string: "安装后首次打开，可在右上角设置中一键启用访达一级「Bolt ›」右键菜单",
        attributes: footerAttrs
    )
    footerStr.draw(in: rectFromTop(24, 322, logicalW - 48, 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard let png1x = renderBackground(scale: 1),
      let png2x = renderBackground(scale: 2) else {
    fputs("Failed to render DMG background images\n", stderr)
    exit(1)
}

let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("boltzip-dmgbg-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmpDir) }

let url1x = tmpDir.appendingPathComponent("bg.png")
let url2x = tmpDir.appendingPathComponent("bg@2x.png")
try png1x.write(to: url1x)
try png2x.write(to: url2x)

if outputURL.pathExtension.lowercased() == "png" {
    try png2x.write(to: outputURL)
} else {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
    proc.arguments = ["-cathidpicheck", url1x.path, url2x.path, "-out", outputURL.path]
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        fputs("tiffutil failed with status \(proc.terminationStatus)\n", stderr)
        exit(1)
    }
}
