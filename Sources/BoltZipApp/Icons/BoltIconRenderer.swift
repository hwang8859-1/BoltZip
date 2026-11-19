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

    private static var dockAnimation: Task<Void, Never>?

    static func apply(style: AppIconStyle, animated: Bool, in app: NSApplication) {
        dockAnimation?.cancel()
        dockAnimation = nil

        let original: NSImage?
        switch style {
        case .system:
            app.applicationIconImage = nil
            original = app.applicationIconImage
        case .light, .dark:
            original = appIconImage(whiteBackground: style == .light, size: 512)
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            DistributedNotificationCenter.default().post(
                name: Notification.Name("dev.boltzip.macos.dockIconStyleDidChange"),
                object: bundleID,
                userInfo: [WorkspaceViewModel.Keys.appIconStyle: style.rawValue]
            )
        }

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let original else {
            setDockIcon(style == .system ? nil : original, in: app)
            return
        }

        let final = style == .system ? nil : original
        let frameCount = 19
        let startScale: CGFloat = 0.82
        let firstFrame = scaledDockIcon(original, scale: startScale)
        setDockIcon(firstFrame, in: app)
        dockAnimation = Task { @MainActor in
            // Let the initial tile appear before starting the rise.
            try? await Task.sleep(for: .milliseconds(120))
            for frame in 1...frameCount {
                guard !Task.isCancelled else { return }
                let remaining = 1 - CGFloat(frame) / CGFloat(frameCount)
                let scale = 1 - (1 - startScale) * remaining * remaining
                setDockIcon(scaledDockIcon(original, scale: scale), in: app)
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            setDockIcon(final, in: app)
        }
    }

    private static func setDockIcon(_ image: NSImage?, in app: NSApplication) {
        app.applicationIconImage = image
        app.dockTile.display()
    }

    private static func scaledDockIcon(_ icon: NSImage, scale: CGFloat) -> NSImage {
        NSImage(size: icon.size, flipped: false) { canvas in
            let insetX = canvas.width * (1 - scale) / 2
            let insetY = canvas.height * (1 - scale) / 2
            icon.draw(in: canvas.insetBy(dx: insetX, dy: insetY), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
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
