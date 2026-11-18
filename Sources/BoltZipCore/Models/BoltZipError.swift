import Foundation

public enum BoltZipError: LocalizedError, Sendable {
    case invalidArchive(String)
    case unsupportedFormat(String)
    case unsupportedCompressionMethod(UInt16)
    case passwordRequired(String)
    case wrongPassword(String)
    case corruptedEntry(entry: String, detail: String)
    case entryNotFound(String)
    case entryAlreadyExists(String)
    case pathTraversalDetected(String)
    case missingSplitVolume(String)
    case ioError(String)
    case compressionFailed(String)
    case externalToolFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail):
            return BoltCoreLocalization.t(
                "无效或损坏的压缩包：\(detail)",
                "無效或已損毀的封存檔：\(detail)",
                "Invalid or corrupted archive: \(detail)",
                "無効または破損した書庫です: \(detail)"
            )
        case .unsupportedFormat(let fmt):
            return BoltCoreLocalization.t(
                "暂不支持该压缩格式：\(fmt)",
                "暫不支援此壓縮格式：\(fmt)",
                "Unsupported archive format: \(fmt)",
                "未対応の書庫形式です: \(fmt)"
            )
        case .unsupportedCompressionMethod(let id):
            return BoltCoreLocalization.t(
                "不支持的 ZIP 压缩算法编号：\(id)",
                "不支援的 ZIP 壓縮演算法編號：\(id)",
                "Unsupported ZIP compression method ID: \(id)",
                "未対応の ZIP 圧縮方式 ID です: \(id)"
            )
        case .passwordRequired(let entry):
            return BoltCoreLocalization.t(
                "文件「\(entry)」已加密，请输入解压密码",
                "檔案「\(entry)」已加密，請輸入解壓密碼",
                "“\(entry)” is encrypted. Please enter a password.",
                "「\(entry)」は暗号化されています。パスワードを入力してください。"
            )
        case .wrongPassword(let entry):
            return BoltCoreLocalization.t(
                "密码错误，无法解密「\(entry)」",
                "密碼錯誤，無法解密「\(entry)」",
                "Incorrect password for “\(entry)”.",
                "パスワードが正しくないため「\(entry)」を復号できません。"
            )
        case .corruptedEntry(let entry, let detail):
            return BoltCoreLocalization.t(
                "文件「\(entry)」校验失败：\(detail)",
                "檔案「\(entry)」驗證失敗：\(detail)",
                "Verification failed for “\(entry)”: \(detail)",
                "「\(entry)」の整合性検証に失敗しました: \(detail)"
            )
        case .entryNotFound(let path):
            return BoltCoreLocalization.t(
                "归档内未找到条目：\(path)",
                "封存檔內找不到項目：\(path)",
                "Entry not found in archive: \(path)",
                "書庫内に項目が見つかりません: \(path)"
            )
        case .entryAlreadyExists(let path):
            return BoltCoreLocalization.t(
                "归档内已存在同名条目：\(path)",
                "封存檔內已存在同名項目：\(path)",
                "Entry already exists in archive: \(path)",
                "書庫内に同名の項目が既に存在します: \(path)"
            )
        case .pathTraversalDetected(let path):
            return BoltCoreLocalization.t(
                "检测到不安全的路径（路径穿越风险）：\(path)",
                "偵測到不安全的路徑（路徑穿越風險）：\(path)",
                "Unsafe path detected (path traversal blocked): \(path)",
                "安全でないパスが検出されました（パストラバーサルをブロック）: \(path)"
            )
        case .missingSplitVolume(let name):
            return BoltCoreLocalization.t(
                "缺少分卷文件：\(name)",
                "缺少分卷檔案：\(name)",
                "Missing split archive volume: \(name)",
                "分割ボリュームファイルが見つかりません: \(name)"
            )
        case .ioError(let detail):
            return BoltCoreLocalization.t(
                "文件读写错误：\(detail)",
                "檔案讀寫錯誤：\(detail)",
                "File I/O error: \(detail)",
                "ファイル入出力エラー: \(detail)"
            )
        case .compressionFailed(let detail):
            return BoltCoreLocalization.t(
                "压缩/解压缩引擎错误：\(detail)",
                "壓縮/解壓縮引擎錯誤：\(detail)",
                "Compression engine error: \(detail)",
                "圧縮/展開エンジンエラー: \(detail)"
            )
        case .externalToolFailed(let detail):
            return BoltCoreLocalization.t(
                "归档处理错误：\(detail)",
                "封存檔處理錯誤：\(detail)",
                "Archive processing error: \(detail)",
                "書庫処理エラー: \(detail)"
            )
        case .cancelled:
            return BoltCoreLocalization.t(
                "操作已取消",
                "操作已取消",
                "Operation cancelled",
                "操作がキャンセルされました"
            )
        }
    }
}
