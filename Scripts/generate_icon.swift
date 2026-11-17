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

    // Outer drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.38).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.05, green: 0.10, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.11, green: 0.15, blue: 0.37, alpha: 1.0).cgColor,
        NSColor(red: 0.03, green: 0.05, blue: 0.13, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Soft radial cyan/indigo ambient glow behind the emblem
    let auraColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.98, alpha: 0.28).cgColor,
        NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.12).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let aura = CGGradient(colorsSpace: cs, colors: auraColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawRadialGradient(
            aura,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
            endRadius: s * 0.44,
            options: []
        )
    }

    // Subtle glass top specular sheen
    let hlColors = [
        NSColor.white.withAlphaComponent(0.22).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let hlGrad = CGGradient(colorsSpace: cs, colors: hlColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hlGrad, start: CGPoint(x: s * 0.5, y: rect.maxY), end: CGPoint(x: s * 0.5, y: rect.midY), options: [])
    }

    // Tilted Lightning + "Z" Emblem:
    // Forward-leant dynamic Z where the diagonal stroke splits like an electric bolt
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

    // Rotate Z-Bolt slightly (-8 deg clockwise) around center so it feels like a tilted lightning strike AND a sharp Z
    var xform = CGAffineTransform(translationX: s * 0.5, y: s * 0.5)
        .rotated(by: -0.11)
        .translatedBy(x: -s * 0.5, y: -s * 0.5)
    let tiltedBolt = zBolt.copy(using: &xform) ?? zBolt

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.075, color: NSColor(red: 0.22, green: 0.78, blue: 1.0, alpha: 0.75).cgColor)
    ctx.addPath(tiltedBolt)
    ctx.clip()
    let boltColors = [
        NSColor(red: 0.22, green: 0.84, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(red: 0.54, green: 0.72, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(red: 1.0, green: 0.84, blue: 0.18, alpha: 1.0).cgColor
    ] as CFArray
    if let bGrad = CGGradient(colorsSpace: cs, colors: boltColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(bGrad, start: CGPoint(x: s * 0.26, y: s * 0.78), end: CGPoint(x: s * 0.74, y: s * 0.21), options: [])
    }
    ctx.restoreGState()

    // Crisp specular edge around Z-Bolt
    ctx.addPath(tiltedBolt)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.38).cgColor)
    ctx.setLineWidth(max(0.8, s * 0.008))
    ctx.strokePath()

    // Outer squircle glass rim
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
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
