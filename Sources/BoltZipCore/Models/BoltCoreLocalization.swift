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

    static var archiveOutputIsInput: String {
        t("压缩包不能同时作为输入文件", "壓縮檔不能同時作為輸入檔案",
          "The archive output cannot also be an input file.", "出力先の圧縮ファイルを入力ファイルとして指定することはできません。")
    }

    static var applicationNotFoundForAssociation: String {
        t("找不到 BoltZip.app，请先安装应用", "找不到 BoltZip.app，請先安裝應用程式",
          "BoltZip.app was not found. Install the app first.", "BoltZip.app が見つかりません。先にアプリをインストールしてください。")
    }

    static var encryptionRequiresZIP: String {
        t("该格式不支持加密，请使用 ZIP 或关闭加密", "此格式不支援加密，請使用 ZIP 或關閉加密",
          "This format does not support encryption. Use ZIP or disable encryption.", "この形式は暗号化に対応していません。ZIP を使用するか暗号化を解除してください。")
    }

    static var splitVolumesRequireZIP: String {
        t("该格式不支持分卷，请使用 ZIP", "此格式不支援分卷，請使用 ZIP",
          "This format does not support split volumes. Use ZIP.", "この形式は分割に対応していません。ZIP を使用してください。")
    }

    static func cannotReplaceDirectoryWithArchive(_ name: String) -> String {
        t("目标是文件夹，无法替换为压缩文件：\(name)", "目標是資料夾，無法替換為壓縮檔：\(name)",
          "Cannot replace a directory with an archive: \(name)", "フォルダを圧縮ファイルで置き換えることはできません: \(name)")
    }

    static func inputChangedWhileArchiving(_ path: String) -> String {
        t("压缩过程中输入文件发生变化：\(path)", "壓縮過程中輸入檔案發生變化：\(path)",
          "Input changed while archiving: \(path)", "圧縮中に入力ファイルが変更されました: \(path)")
    }
}
