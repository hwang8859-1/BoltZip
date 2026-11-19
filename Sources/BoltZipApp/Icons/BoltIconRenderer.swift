import AppKit
import BoltZipCore
import SwiftUI

/// Cached AppKit image bridge over `BoltIconArtwork` for BoltZip's Dock / About / Settings icons
/// and per-format Finder document icon previews.
@MainActor
enum BoltAppIconRenderer {
    private static var cachedDarkIcon: NSImage?
    private static var cachedWhiteIcon: NSImage?
    private static var cachedDocumentIcons: [String: NSImage] = [:]

    static func apply(style: AppIconStyle) {
        guard let app = NSApp as NSApplication? else { return }
        switch style {
        case .system:
            // Clearing the runtime override lets the Dock render the adaptive Assets.car AppIcon live.
            app.applicationIconImage = nil
        case .light:
            app.applicationIconImage = appIconImage(whiteBackground: true, size: 512)
        case .dark:
            app.applicationIconImage = appIconImage(whiteBackground: false, size: 512)
        }
        app.dockTile.display()
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
        let image = BoltIconArtwork.renderAppIconNSImage(size: size, whiteBackground: whiteBackground)
        if size == 512 {
            if whiteBackground {
                cachedWhiteIcon = image
            } else {
                cachedDarkIcon = image
            }
        }
        return image
    }

    static func documentIconImage(kind: BoltDocumentIconKind, size: CGFloat = 32, isDark: Bool = false) -> NSImage {
        let key = "\(kind.rawValue)-\(Int(size.rounded()))-\(isDark ? "dark" : "light")"
        if let cached = cachedDocumentIcons[key] {
            return cached
        }
        let image = BoltIconArtwork.renderDocumentIconNSImage(kind: kind, size: size, isDark: isDark)
        cachedDocumentIcons[key] = image
        return image
    }
}

/// Crisp SwiftUI wrapper displaying BoltZip's rendered AppIcon at a target display size.
struct BoltAppIconView: View {
    let style: AppIconStyle
    var appTheme: AppTheme = .system
    var renderSize: CGFloat = 64
    var displaySize: CGFloat = 20

    @Environment(\.colorScheme) private var systemColorScheme

    private var whiteBackground: Bool {
        switch style {
        case .system:
            switch appTheme {
            case .light: return true
            case .dark: return false
            case .system: return systemColorScheme != .dark
            }
        case .light:
            return true
        case .dark:
            return false
        }
    }

    var body: some View {
        Image(nsImage: BoltAppIconRenderer.appIconImage(whiteBackground: whiteBackground, size: renderSize))
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize, height: displaySize)
    }
}

/// Crisp SwiftUI wrapper displaying a per-format BoltZip Document Icon synced with the active theme.
struct BoltDocumentIconView: View {
    let kind: BoltDocumentIconKind
    let appTheme: AppTheme
    var renderSize: CGFloat = 32
    var displaySize: CGFloat = 26

    @Environment(\.colorScheme) private var systemColorScheme

    private var isDark: Bool {
        appTheme == .dark || (appTheme == .system && systemColorScheme == .dark)
    }

    var body: some View {
        Image(nsImage: BoltAppIconRenderer.documentIconImage(kind: kind, size: renderSize, isDark: isDark))
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize, height: displaySize)
    }
}
