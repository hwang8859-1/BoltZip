#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import Foundation

/// Shared CoreGraphics renderer entry point for BoltZip's Application Icon (`AppIcon.icns`)
/// and 17 per-format Archive Document Icons (`Doc*.icns` + UI/CLI previews).
public enum BoltIconArtwork {
    internal static let colorSpace = CGColorSpaceCreateDeviceRGB()

    // MARK: - Public Image & PNG Renderers

    public static func renderAppIconNSImage(size: CGFloat, whiteBackground: Bool, goldSweepProgress: CGFloat? = nil) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAppIcon(in: ctx, size: size, whiteBackground: whiteBackground, goldSweepProgress: goldSweepProgress)
            return true
        }
    }

    public static func renderAppIconPNG(pixelSize: Int, whiteBackground: Bool, goldSweepProgress: CGFloat? = nil) -> Data? {
        renderPNG(pixelSize: pixelSize) { ctx, s in
            drawAppIcon(in: ctx, size: s, whiteBackground: whiteBackground, goldSweepProgress: goldSweepProgress)
        }
    }

    public static func renderAppIconForegroundPNG(pixelSize: Int, whiteBackground: Bool) -> Data? {
        renderPNG(pixelSize: pixelSize) { ctx, s in
            drawAppIconForeground(in: ctx, size: s, whiteBackground: whiteBackground)
        }
    }

    public static func renderDocumentIconNSImage(
        kind: BoltDocumentIconKind,
        size: CGFloat,
        isDark: Bool = false
    ) -> NSImage {
        let scale = BoltIconScale(pixelSize: Int(size.rounded()))
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawDocumentIcon(in: ctx, size: size, kind: kind, isDark: isDark, opticalScale: scale)
            return true
        }
    }

    public static func renderDocumentIconPNG(
        kind: BoltDocumentIconKind,
        pixelSize: Int,
        isDark: Bool = false
    ) -> Data? {
        let scale = BoltIconScale(pixelSize: pixelSize)
        return renderPNG(pixelSize: pixelSize) { ctx, s in
            drawDocumentIcon(in: ctx, size: s, kind: kind, isDark: isDark, opticalScale: scale)
        }
    }

    private static func renderPNG(pixelSize: Int, draw: (CGContext, CGFloat) -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
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
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        draw(ctx, CGFloat(pixelSize))
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
