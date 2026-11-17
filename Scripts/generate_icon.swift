import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor(red: 0.06, green: 0.09, blue: 0.19, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for gradient background
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.07, green: 0.12, blue: 0.26, alpha: 1.0).cgColor,
        NSColor(red: 0.12, green: 0.16, blue: 0.38, alpha: 1.0).cgColor,
        NSColor(red: 0.04, green: 0.07, blue: 0.15, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Subtle glass top highlight
    let highlightRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.55)
    let hlColors = [
        NSColor.white.withAlphaComponent(0.20).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let hlGrad = CGGradient(colorsSpace: cs, colors: hlColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hlGrad, start: CGPoint(x: s / 2, y: highlightRect.maxY), end: CGPoint(x: s / 2, y: highlightRect.minY), options: [])
    }

    // Zipper seam lines vertically down center
    let seamX = s * 0.5
    ctx.setStrokeColor(NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.38).cgColor)
    ctx.setLineWidth(max(1.0, s * 0.015))
    for step in stride(from: s * 0.14, through: s * 0.86, by: s * 0.065) {
        let toothW = s * 0.055
        let isLeft = Int((step / (s * 0.065)).rounded()) % 2 == 0
        let x1 = isLeft ? seamX - toothW : seamX
        let x2 = isLeft ? seamX : seamX + toothW
        ctx.move(to: CGPoint(x: x1, y: step))
        ctx.addLine(to: CGPoint(x: x2, y: step))
    }
    ctx.strokePath()

    // Lightning bolt centerpiece
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: s * 0.56, y: s * 0.82))
    bolt.addLine(to: CGPoint(x: s * 0.30, y: s * 0.47))
    bolt.addLine(to: CGPoint(x: s * 0.48, y: s * 0.47))
    bolt.addLine(to: CGPoint(x: s * 0.42, y: s * 0.18))
    bolt.addLine(to: CGPoint(x: s * 0.70, y: s * 0.54))
    bolt.addLine(to: CGPoint(x: s * 0.52, y: s * 0.54))
    bolt.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.65).cgColor)
    ctx.addPath(bolt)
    ctx.clip()
    let boltColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor,
        NSColor(red: 0.98, green: 0.82, blue: 0.18, alpha: 1.0).cgColor
    ] as CFArray
    if let bGrad = CGGradient(colorsSpace: cs, colors: boltColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bGrad, start: CGPoint(x: s * 0.35, y: s * 0.82), end: CGPoint(x: s * 0.65, y: s * 0.18), options: [])
    }
    ctx.restoreGState()

    // Outer specular rim
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    if let png = renderIcon(size: px) {
        try png.write(to: iconsetURL.appendingPathComponent(filename))
    }
}
