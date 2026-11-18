import Foundation
import os

public enum BoltCoreLanguage: String, CaseIterable, Sendable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"

    public static var current: BoltCoreLanguage {
        if let forced = BoltCoreLocalization.overrideLanguage {
            return forced
        }
        if let raw = UserDefaults.standard.string(forKey: "BoltZip.AppLanguage") {
            switch raw {
            case "zh-Hans": return .zhHans
            case "zh-Hant": return .zhHant
            case "en": return .en
            case "ja": return .ja
            default: break
            }
        }
        return resolve(preferredLanguages: Locale.preferredLanguages)
    }

    public static func resolve(preferredLanguages: [String]) -> BoltCoreLanguage {
        let preferred = preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ja") { return .ja }
        if preferred.hasPrefix("zh-hant")
            || preferred.hasPrefix("zh-tw")
            || preferred.hasPrefix("zh-hk")
            || preferred.hasPrefix("zh-mo") {
            return .zhHant
        }
        if preferred.hasPrefix("zh") { return .zhHans }
        return .en
    }
}

public enum BoltCoreLocalization: Sendable {
    private static let overrideLock = OSAllocatedUnfairLock<BoltCoreLanguage?>(initialState: nil)

    public static var overrideLanguage: BoltCoreLanguage? {
        get { overrideLock.withLock { $0 } }
        set { overrideLock.withLock { $0 = newValue } }
    }

    public static func t(_ sc: String, _ tc: String, _ en: String, _ ja: String) -> String {
        switch BoltCoreLanguage.current {
        case .zhHans: return sc
        case .zhHant: return tc
        case .en: return en
        case .ja: return ja
        }
    }
}
