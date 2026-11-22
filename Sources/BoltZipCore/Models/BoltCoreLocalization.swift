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

    static func extractionWouldReplaceSource(_ name: String) -> String {
        t("解压会覆盖源压缩包或分卷：\(name)。请选择其他目录或保留两份。",
          "解壓縮會覆蓋來源封存檔或分卷：\(name)。請選擇其他資料夾或保留兩份。",
          "Extraction would replace a source archive or volume: \(name). Choose another folder or keep both.",
          "展開すると元の書庫または分割ボリューム「\(name)」が上書きされます。別のフォルダを選ぶか、両方を残してください。")
    }

    static var applicationNotFoundForAssociation: String {
        t("找不到 BoltZip.app，请先安装应用", "找不到 BoltZip.app，請先安裝應用程式",
          "BoltZip.app was not found. Install the app first.", "BoltZip.app が見つかりません。先にアプリをインストールしてください。")
    }

    static var encryptionRequiresZIP: String {
        t("该格式不支持加密，请使用 ZIP 或 7z", "此格式不支援加密，請使用 ZIP 或 7z",
          "This format does not support encryption. Use ZIP or 7z.", "この形式は暗号化に対応していません。ZIP または 7z を使用してください。")
    }

    static var filenameEncryptionRequires7z: String {
        t("请使用 7z 格式加密文件名。", "請使用 7z 格式加密檔名。",
          "Use the 7z format to encrypt file names.", "ファイル名を暗号化するには 7z 形式を使用してください。")
    }

    static var sevenZipEncryptionRequiresAES256: String {
        t("7z 加密需要使用 AES-256。", "7z 加密需要使用 AES-256。",
          "7z encryption requires AES-256.", "7z の暗号化には AES-256 が必要です。")
    }

    static var invalidSevenZipPassword: String {
        t("请输入压缩包密码。密码不能包含换行符或空字符。", "請輸入封存檔密碼。密碼不能包含換行字元或空字元。",
          "Enter an archive password without line breaks or null characters.", "改行やヌル文字を含まない書庫のパスワードを入力してください。")
    }

    static var sevenZipEngineUnavailable: String {
        t("归档处理组件不可用，请重新安装 BoltZip", "封存檔處理元件無法使用，請重新安裝 BoltZip",
          "The archive processing component is unavailable. Reinstall BoltZip.", "書庫処理用のコンポーネントを使用できません。BoltZip を再インストールしてください。")
    }

    static var splitVolumesRequireZIP: String {
        t("该格式不支持分卷，请使用 ZIP 或 7z", "此格式不支援分卷，請使用 ZIP 或 7z",
          "This format does not support split volumes. Use ZIP or 7z.", "この形式は分割に対応していません。ZIP または 7z を使用してください。")
    }

    static func singleStreamRequiresSingleRegularFile(_ formatName: String) -> String {
        t("\(formatName) 仅支持压缩单个常规文件；多个项目或文件夹请改用 TAR 归档。",
          "\(formatName) 僅支援壓縮單一常規檔案；多個項目或資料夾請改用 TAR 封存檔。",
          "\(formatName) compresses a single regular file only. Use a TAR archive for multiple items or folders.",
          "\(formatName) は単一の通常ファイルのみ圧縮できます。複数項目やフォルダには TAR 書庫を使用してください。")
    }

    static var noRecoverableZipEntries: String {
        t("未在该损坏的 ZIP 中扫描到可校验恢复的有效条目。",
          "未在此損毀的 ZIP 中掃描到可校驗復原的有效項目。",
          "No verifiable entries were found to recover from this damaged ZIP archive.",
          "この破損した ZIP から検証および復元可能な有効項目は見つかりませんでした。")
    }

    static var sevenZipSplitArchiveReadOnly: String {
        t("7z 分卷归档仅支持只读浏览与解压，不支持原地增删改。",
          "7z 分卷封存檔僅支援唯讀瀏覽與解壓縮，不支援原地增刪改。",
          "Split 7z archives are read-only and cannot be edited in place.",
          "分割された 7z 書庫は読み取り専用のため、書庫内の直接編集には対応していません。")
    }

    static func cannotReplaceDirectoryWithArchive(_ name: String) -> String {
        t("目标是文件夹，无法替换为压缩文件：\(name)", "目標是資料夾，無法替換為壓縮檔：\(name)",
          "Cannot replace a directory with an archive: \(name)", "フォルダを圧縮ファイルで置き換えることはできません: \(name)")
    }

    static func inputChangedWhileArchiving(_ path: String) -> String {
        t("压缩过程中输入文件发生变化：\(path)", "壓縮過程中輸入檔案發生變化：\(path)",
          "Input changed while archiving: \(path)", "圧縮中に入力ファイルが変更されました: \(path)")
    }

    static func archiveEditCompatibilityMessage(_ error: ArchiveEditCompatibilityError) -> String {
        switch error {
        case .unsupportedCompression(let path, let method):
            return t("无法按条目“\(path)”原有的压缩方式 \(method) 写入。", "無法依項目「\(path)」原有的壓縮方式 \(method) 寫入。",
                     "Cannot write entry “\(path)” with its original method \(method).", "項目「\(path)」を元の圧縮方式 \(method) で書き込めません。")
        case .unsupportedEncryption(let path):
            return t("无法保留条目“\(path)”原有的加密模式。", "無法保留項目「\(path)」原有的加密模式。",
                     "Cannot preserve the encryption mode of “\(path)”.", "項目「\(path)」の元の暗号化方式を保持できません。")
        case .ambiguousEntry(let path):
            return t("原包包含多个同名条目“\(path)”，无法安全确定替换目标。", "原套件包含多個同名項目「\(path)」，無法安全確認替換目標。",
                     "Multiple entries are named “\(path)”; the replacement target is ambiguous.", "同名の項目「\(path)」が複数あるため、安全に置換対象を特定できません。")
        }
    }
}
