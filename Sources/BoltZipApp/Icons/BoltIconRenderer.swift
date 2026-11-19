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
    private static var sweepTask: Task<Void, Never>?

    static func apply(style: AppIconStyle, animationEnabled: Bool, in app: NSApplication) {
        sweepTask?.cancel()
        sweepTask = nil
        let white: Bool
        switch style {
        case .light: white = true
        case .dark: white = false
        case .system:
            let systemStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            white = systemStyle != "Dark"
        }

        let restingIcon = appIconImage(whiteBackground: white)
        app.applicationIconImage = restingIcon
        app.dockTile.display()

        if let bundleID = Bundle.main.bundleIdentifier {
            DistributedNotificationCenter.default().post(
                name: Notification.Name("dev.boltzip.macos.dockIconStyleDidChange"),
                object: bundleID,
                userInfo: [WorkspaceViewModel.Keys.appIconStyle: style.rawValue]
            )
        }

        guard animationEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        sweepTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            let renderFrames = Task.detached(priority: .utility) {
                var rendered: [Data] = []
                for step in 0..<18 {
                    guard !Task.isCancelled else { return [Data]() }
                    let progress = 0.06 + 0.90 * CGFloat(step) / 17
                    if let png = BoltIconArtwork.renderAppIconPNG(
                        pixelSize: 256, whiteBackground: white, goldSweepProgress: progress
                    ) {
                        rendered.append(png)
                    }
                }
                return rendered
            }
            let pngs = await withTaskCancellationHandler {
                await renderFrames.value
            } onCancel: {
                renderFrames.cancel()
            }
            guard !Task.isCancelled else { return }
            let frames = pngs.compactMap { png -> NSImage? in
                guard let image = NSImage(data: png) else { return nil }
                image.size = restingIcon.size
                return image
            }
            guard !frames.isEmpty else { return }

            while !Task.isCancelled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                for image in frames {
                    guard !Task.isCancelled else { return }
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { break }
                    app.applicationIconImage = image
                    app.dockTile.display()
                    try? await Task.sleep(for: .milliseconds(55))
                }
                guard !Task.isCancelled else { return }
                app.applicationIconImage = restingIcon
                app.dockTile.display()
                try? await Task.sleep(for: .seconds(8))
            }
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
