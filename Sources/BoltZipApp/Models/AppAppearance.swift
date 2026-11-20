import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func title(_ l: L10n) -> String {
        switch self {
        case .system: return l.themeSystem
        case .light: return l.themeLight
        case .dark: return l.themeDark
        }
    }
}

enum AppIconStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    func title(_ l: L10n) -> String {
        switch self {
        case .system: return l.themeSystem
        case .light: return l.themeLight
        case .dark: return l.themeDark
        }
    }
}

enum AppBackgroundColor: String, CaseIterable, Identifiable, Sendable {
    case pureWhite
    case iceBlue
    case lavender
    case mint
    case warmCream
    case custom

    var id: String { rawValue }

    static var presets: [AppBackgroundColor] {
        [.pureWhite, .iceBlue, .lavender, .mint, .warmCream]
    }

    func title(_ l: L10n) -> String {
        switch self {
        case .pureWhite: return l.bgColorPureWhite
        case .iceBlue: return l.bgColorIceBlue
        case .lavender: return l.bgColorLavender
        case .mint: return l.bgColorMint
        case .warmCream: return l.bgColorWarmCream
        case .custom: return l.bgColorCustom
        }
    }

    func swatchColor(customRed: Double = 0.94, customGreen: Double = 0.96, customBlue: Double = 0.99) -> Color {
        switch self {
        case .pureWhite: return Color(red: 0.96, green: 0.97, blue: 0.98)
        case .iceBlue: return Color(red: 0.78, green: 0.90, blue: 0.99)
        case .lavender: return Color(red: 0.88, green: 0.84, blue: 0.99)
        case .mint: return Color(red: 0.80, green: 0.95, blue: 0.88)
        case .warmCream: return Color(red: 0.98, green: 0.92, blue: 0.82)
        case .custom: return Color(red: customRed, green: customGreen, blue: customBlue)
        }
    }

    func resolvedNSColor(
        isDark: Bool,
        customRed: Double,
        customGreen: Double,
        customBlue: Double
    ) -> NSColor {
        switch self {
        case .pureWhite:
            return isDark
                ? NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)
                : NSColor(calibratedRed: 0.955, green: 0.962, blue: 0.975, alpha: 1.0)
        case .iceBlue:
            return isDark
                ? NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.25, alpha: 1.0)
                : NSColor(calibratedRed: 0.86, green: 0.935, blue: 0.99, alpha: 1.0)
        case .lavender:
            return isDark
                ? NSColor(calibratedRed: 0.14, green: 0.11, blue: 0.24, alpha: 1.0)
                : NSColor(calibratedRed: 0.915, green: 0.895, blue: 0.99, alpha: 1.0)
        case .mint:
            return isDark
                ? NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.14, alpha: 1.0)
                : NSColor(calibratedRed: 0.875, green: 0.965, blue: 0.92, alpha: 1.0)
        case .warmCream:
            return isDark
                ? NSColor(calibratedRed: 0.19, green: 0.15, blue: 0.11, alpha: 1.0)
                : NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.875, alpha: 1.0)
        case .custom:
            let base = NSColor(calibratedRed: customRed, green: customGreen, blue: customBlue, alpha: 1.0)
            if isDark {
                return base.blended(withFraction: 0.62, of: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)) ?? base
            }
            return base
        }
    }
}
