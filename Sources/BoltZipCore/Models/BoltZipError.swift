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
            return "无效或损坏的压缩包：\(detail)"
        case .unsupportedFormat(let fmt):
            return "暂不支持该压缩格式：\(fmt)"
        case .unsupportedCompressionMethod(let id):
            return "不支持的 ZIP 压缩算法编号：\(id)"
        case .passwordRequired(let entry):
            return "文件「\(entry)」已加密，请输入解压密码"
        case .wrongPassword(let entry):
            return "密码错误，无法解密「\(entry)」"
        case .corruptedEntry(let entry, let detail):
            return "文件「\(entry)」校验失败：\(detail)"
        case .entryNotFound(let path):
            return "归档内未找到条目：\(path)"
        case .entryAlreadyExists(let path):
            return "归档内已存在同名条目：\(path)"
        case .pathTraversalDetected(let path):
            return "检测到不安全的路径（路径穿越风险）：\(path)"
        case .missingSplitVolume(let name):
            return "缺少分卷文件：\(name)"
        case .ioError(let detail):
            return "文件读写错误：\(detail)"
        case .compressionFailed(let detail):
            return "压缩/解压缩引擎错误：\(detail)"
        case .externalToolFailed(let detail):
            return "归档处理错误：\(detail)"
        case .cancelled:
            return "操作已取消"
        }
    }
}
