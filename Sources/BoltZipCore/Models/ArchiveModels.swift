import Foundation

public enum ArchiveFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case zip
    case rar
    case sevenZip = "7z"
    case tar
    case tarGz = "tar.gz"
    case tarZst = "tar.zst"
    case tarXz = "tar.xz"
    case tarBz2 = "tar.bz2"
    case tarLz4 = "tar.lz4"
    case gz
    case zst
    case xz
    case bz2
    case lz4
    case iso
    case cab
    case xar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zip: return "ZIP (.zip)"
        case .rar: return "RAR (.rar)"
        case .sevenZip: return "7-Zip (.7z)"
        case .tar: return "TAR (.tar)"
        case .tarGz: return "TAR + Gzip (.tar.gz)"
        case .tarZst: return "TAR + Zstandard (.tar.zst)"
        case .tarXz: return "TAR + XZ (.tar.xz)"
        case .tarBz2: return "TAR + Bzip2 (.tar.bz2)"
        case .tarLz4: return "TAR + LZ4 (.tar.lz4)"
        case .gz: return "Gzip (.gz)"
        case .zst: return "Zstandard (.zst)"
        case .xz: return "XZ (.xz)"
        case .bz2: return "Bzip2 (.bz2)"
        case .lz4: return "LZ4 (.lz4)"
        case .iso: return BoltCoreLocalization.t("ISO 镜像 (.iso)", "ISO 光碟映像 (.iso)", "ISO Image (.iso)", "ISO イメージ (.iso)")
        case .cab: return "Windows CAB (.cab)"
        case .xar: return "macOS XAR (.xar)"
        }
    }

    public var fileExtension: String { rawValue }

    public static var creatableFormats: [ArchiveFormat] {
        [.zip, .tarZst, .tarGz, .tarXz, .tarBz2, .tarLz4, .tar, .sevenZip]
    }

    public var supportsInPlaceEditing: Bool { self == .zip }
    public var supportsEncryption: Bool { self == .zip }
    public var supportsSplitVolumes: Bool { self == .zip }

    public var supportedAlgorithms: [CompressionAlgorithm] {
        switch self {
        case .zip:
            return [.deflate, .zstd, .bzip2, .store]
        case .tarGz, .gz:
            return [.deflate]
        case .tarZst, .zst:
            return [.zstd]
        case .tarXz, .xz:
            return [.xz]
        case .tarBz2, .bz2:
            return [.bzip2]
        case .tarLz4, .lz4:
            return [.lz4]
        case .tar:
            return [.store]
        case .sevenZip:
            return [.xz, .bzip2, .deflate, .store]
        default:
            return [.store]
        }
    }

    public var defaultAlgorithm: CompressionAlgorithm {
        switch self {
        case .zip, .tarGz, .gz: return .deflate
        case .tarZst, .zst: return .zstd
        case .tarXz, .xz, .sevenZip: return .xz
        case .tarBz2, .bz2: return .bzip2
        case .tarLz4, .lz4: return .lz4
        default: return .store
        }
    }

    public static func detect(from url: URL) -> ArchiveFormat? {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tarGz }
        if lower.hasSuffix(".tar.zst") || lower.hasSuffix(".tzst") { return .tarZst }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return .tarXz }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") || lower.hasSuffix(".tbz") { return .tarBz2 }
        if lower.hasSuffix(".tar.lz4") || lower.hasSuffix(".tlz4") { return .tarLz4 }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip", "zipx", "cbz", "ipa", "apk", "jar", "epub", "whl": return .zip
        case "rar", "cbr": return .rar
        case "7z", "cb7": return .sevenZip
        case "tar": return .tar
        case "gz": return .gz
        case "zst", "zstd": return .zst
        case "xz", "lzma": return .xz
        case "bz2": return .bz2
        case "lz4": return .lz4
        case "iso": return .iso
        case "cab": return .cab
        case "xar", "pkg": return .xar
        default:
            // Detect split zip volume like archive.z01, archive.z02
            if ext.count >= 2, ext.hasPrefix("z"), Int(ext.dropFirst()) != nil {
                return .zip
            }
            // Detect legacy split rar volume like archive.r00, archive.r01
            if ext.count == 3, ext.hasPrefix("r"), Int(ext.dropFirst()) != nil {
                return .rar
            }
            return nil
        }
    }
}

public enum CompressionAlgorithm: String, CaseIterable, Identifiable, Codable, Sendable {
    case store
    case deflate
    case zstd
    case xz
    case bzip2
    case lz4

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .store: return BoltCoreLocalization.t("仅存储 (Store)", "僅儲存 (Store)", "Store (No Compression)", "無圧縮 (Store)")
        case .deflate: return "DEFLATE (zlib)"
        case .zstd: return "Zstandard (zstd)"
        case .xz: return "LZMA2 (xz)"
        case .bzip2: return "Bzip2 (libbz2)"
        case .lz4: return "LZ4 (lz4frame)"
        }
    }

    public var shortName: String {
        switch self {
        case .store: return "Store"
        case .deflate: return "DEFLATE"
        case .zstd: return "Zstd"
        case .xz: return "LZMA2"
        case .bzip2: return "Bzip2"
        case .lz4: return "LZ4"
        }
    }

    public var openSourceLicenseNote: String {
        switch self {
        case .store: return BoltCoreLocalization.t("无压缩直存", "無壓縮直存", "Uncompressed raw storage", "無圧縮ダイレクト保存")
        case .deflate: return BoltCoreLocalization.t("zlib License · 全平台最通用", "zlib License · 全平台最通用", "zlib License · Universal compatibility", "zlib License · 汎用性重視")
        case .zstd: return BoltCoreLocalization.t("BSD License · Meta 开源高比高速", "BSD License · Meta 開源高壓縮高速度", "BSD License · High ratio & fast", "BSD License · 高圧縮・超高速")
        case .xz: return BoltCoreLocalization.t("0BSD / Public Domain · 极限压缩比", "0BSD / Public Domain · 極限壓縮比", "0BSD / Public Domain · Maximum ratio", "0BSD / Public Domain · 最高圧縮率")
        case .bzip2: return BoltCoreLocalization.t("bzip2 License · 经典块排序压缩", "bzip2 License · 經典區塊排序壓縮", "bzip2 License · Classic block sorting", "bzip2 License · クラシック高圧縮")
        case .lz4: return BoltCoreLocalization.t("BSD 2-Clause · 实时超高速", "BSD 2-Clause · 即時超高速", "BSD 2-Clause · Real-time ultra fast", "BSD 2-Clause · リアルタイム超高速")
        }
    }

    public var levelRange: ClosedRange<Int> {
        switch self {
        case .store: return 0...0
        case .deflate: return 1...9
        case .zstd: return 1...19
        case .xz: return 0...9
        case .bzip2: return 1...9
        case .lz4: return 0...12
        }
    }

    public var defaultLevel: Int {
        switch self {
        case .store: return 0
        case .deflate: return 6
        case .zstd: return 5
        case .xz: return 6
        case .bzip2: return 6
        case .lz4: return 3
        }
    }

    public var zipMethodCode: UInt16 {
        switch self {
        case .store: return 0
        case .deflate: return 8
        case .bzip2: return 12
        case .zstd: return 93
        case .xz: return 95
        case .lz4: return 93
        }
    }
}

public enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case store
    case fastest
    case balanced
    case maximum
    case ultra

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .store: return BoltCoreLocalization.t("仅存储", "僅儲存", "Store", "無圧縮")
        case .fastest: return BoltCoreLocalization.t("极速压缩", "極速壓縮", "Fastest", "最速")
        case .balanced: return BoltCoreLocalization.t("标准均衡", "標準均衡", "Balanced", "標準")
        case .maximum: return BoltCoreLocalization.t("高压缩率", "高壓縮率", "Maximum", "高圧縮")
        case .ultra: return BoltCoreLocalization.t("极限压缩", "極限壓縮", "Ultra", "最高圧縮")
        }
    }

    public func level(for algorithm: CompressionAlgorithm) -> Int {
        switch (self, algorithm) {
        case (.store, _): return 0
        case (_, .store): return 0
        case (.fastest, .deflate): return 1
        case (.balanced, .deflate): return 6
        case (.maximum, .deflate): return 8
        case (.ultra, .deflate): return 9
        case (.fastest, .zstd): return 1
        case (.balanced, .zstd): return 5
        case (.maximum, .zstd): return 12
        case (.ultra, .zstd): return 19
        case (.fastest, .xz): return 1
        case (.balanced, .xz): return 5
        case (.maximum, .xz): return 7
        case (.ultra, .xz): return 9
        case (.fastest, .bzip2): return 1
        case (.balanced, .bzip2): return 6
        case (.maximum, .bzip2): return 8
        case (.ultra, .bzip2): return 9
        case (.fastest, .lz4): return 0
        case (.balanced, .lz4): return 3
        case (.maximum, .lz4): return 9
        case (.ultra, .lz4): return 12
        }
    }
}

public enum EncryptionMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case aes256
    case zipCrypto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return BoltCoreLocalization.t("不加密", "不加密", "None", "暗号化なし")
        case .aes256: return BoltCoreLocalization.t("AES-256 (WinZip AE-2 标准)", "AES-256 (WinZip AE-2 標準)", "AES-256 (WinZip AE-2)", "AES-256 (WinZip AE-2 準拠)")
        case .zipCrypto: return BoltCoreLocalization.t("ZipCrypto (传统兼容)", "ZipCrypto (傳統相容)", "ZipCrypto (Legacy Compatible)", "ZipCrypto (従来互換)")
        }
    }
}

public enum FilenameEncodingOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case utf8
    case gb18030
    case big5
    case shiftJIS
    case eucKR
    case cp437

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return BoltCoreLocalization.t("智能自动识别 (推荐)", "智慧自動辨識 (推薦)", "Auto-Detect (Recommended)", "自動判別 (推奨)")
        case .utf8: return "UTF-8 (Unicode)"
        case .gb18030: return BoltCoreLocalization.t("简体中文 (GB18030 / GBK)", "簡體中文 (GB18030 / GBK)", "Simplified Chinese (GB18030 / GBK)", "簡体字中国語 (GB18030 / GBK)")
        case .big5: return BoltCoreLocalization.t("繁体中文 (Big5)", "繁體中文 (Big5)", "Traditional Chinese (Big5)", "繁体字中国語 (Big5)")
        case .shiftJIS: return BoltCoreLocalization.t("日文 (Shift-JIS)", "日文 (Shift-JIS)", "Japanese (Shift-JIS)", "日本語 (Shift-JIS)")
        case .eucKR: return BoltCoreLocalization.t("韩文 (EUC-KR)", "韓文 (EUC-KR)", "Korean (EUC-KR)", "韓国語 (EUC-KR)")
        case .cp437: return BoltCoreLocalization.t("DOS / 英文 (CP437)", "DOS / 英文 (CP437)", "DOS / Western (CP437)", "DOS / 欧文 (CP437)")
        }
    }
}

public enum MultiCorePreference: Equatable, Hashable, Sendable {
    case auto
    case fixed(Int)

    public var rawStorageValue: Int {
        switch self {
        case .auto: return 0
        case .fixed(let count): return max(1, count)
        }
    }

    public init(rawStorageValue: Int) {
        if rawStorageValue <= 0 {
            self = .auto
        } else {
            self = .fixed(rawStorageValue)
        }
    }

    public var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }
}

public enum ExtractMode: Equatable, Sendable {
    case smart
    case here
    case subfolder
    case selected(Set<String>)
}

public enum OverwritePolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case overwrite
    case skip
    case rename

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .overwrite: return BoltCoreLocalization.t("覆盖已有文件", "覆蓋既有檔案", "Overwrite Existing", "既存ファイルを上書き")
        case .skip: return BoltCoreLocalization.t("跳过已有文件", "略過既有檔案", "Skip Existing", "既存ファイルをスキップ")
        case .rename: return BoltCoreLocalization.t("自动重命名保留两者", "自動重新命名保留兩者", "Keep Both (Auto Rename)", "自動リネームして両方残す")
        }
    }
}

public struct ExtractConflictSummary: Sendable, Equatable {
    public let destinationRoot: URL
    public let conflictingNames: [String]

    public var hasConflicts: Bool { !conflictingNames.isEmpty }

    public init(destinationRoot: URL, conflictingNames: [String]) {
        self.destinationRoot = destinationRoot
        self.conflictingNames = conflictingNames
    }
}

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let parentPath: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let uncompressedSize: UInt64
    public let compressedSize: UInt64
    public let compressionMethodName: String
    public let crc32: UInt32
    public let modifiedDate: Date
    public let permissions: UInt16
    public let isEncrypted: Bool
    public let encryptionLabel: String
    public let comment: String
    public let rawPathBytes: Data
    public let hasUTF8Flag: Bool

    public init(
        path: String,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        uncompressedSize: UInt64,
        compressedSize: UInt64,
        compressionMethodName: String,
        crc32: UInt32,
        modifiedDate: Date,
        permissions: UInt16 = 0o644,
        isEncrypted: Bool = false,
        encryptionLabel: String = "",
        comment: String = "",
        rawPathBytes: Data = Data(),
        hasUTF8Flag: Bool = true
    ) {
        let normalized = ArchiveEntry.normalizePath(path, isDirectory: isDirectory)
        self.id = normalized
        self.path = normalized
        let trimmed = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        if let idx = trimmed.lastIndex(of: "/") {
            self.parentPath = String(trimmed[..<idx])
            self.name = String(trimmed[trimmed.index(after: idx)...])
        } else {
            self.parentPath = ""
            self.name = trimmed
        }
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.compressionMethodName = compressionMethodName
        self.crc32 = crc32
        self.modifiedDate = modifiedDate
        self.permissions = permissions
        self.isEncrypted = isEncrypted
        self.encryptionLabel = encryptionLabel
        self.comment = comment
        self.rawPathBytes = rawPathBytes
        self.hasUTF8Flag = hasUTF8Flag
    }

    public var compressionRatioPercent: Double {
        guard !isDirectory, uncompressedSize > 0 else { return 0 }
        let ratio = (1.0 - (Double(compressedSize) / Double(uncompressedSize))) * 100.0
        return max(-999.0, min(100.0, ratio))
    }

    public static func normalizePath(_ raw: String, isDirectory: Bool) -> String {
        if !raw.isEmpty,
           !raw.contains("\\"),
           !raw.hasPrefix("/"),
           !raw.hasPrefix("./"),
           !raw.contains("//") {
            let hasTrailingSlash = raw.hasSuffix("/")
            if hasTrailingSlash == isDirectory {
                return raw
            }
        }
        var cleaned = raw.replacingOccurrences(of: "\\", with: "/")
        while cleaned.hasPrefix("/") { cleaned.removeFirst() }
        while cleaned.hasPrefix("./") { cleaned.removeFirst(2) }
        while cleaned.contains("//") { cleaned = cleaned.replacingOccurrences(of: "//", with: "/") }
        while cleaned.hasSuffix("/") { cleaned.removeLast() }
        if isDirectory && !cleaned.isEmpty {
            cleaned += "/"
        }
        return cleaned
    }
}

public struct CreateArchiveOptions: Sendable {
    public var format: ArchiveFormat
    public var algorithm: CompressionAlgorithm
    public var level: Int
    public var encryption: EncryptionMethod
    public var password: String?
    public var splitVolumeSizeBytes: UInt64?
    public var excludeMacJunk: Bool
    public var encoding: FilenameEncodingOption
    public var archiveComment: String
    /// `nil` = follow global `BoltConcurrency.preference`; `0` = auto; `>= 1` = explicit core cap.
    public var workerCount: Int?
    public var preserveSymlinks: Bool

    public init(
        format: ArchiveFormat = .zip,
        algorithm: CompressionAlgorithm = .deflate,
        level: Int? = nil,
        encryption: EncryptionMethod = .none,
        password: String? = nil,
        splitVolumeSizeBytes: UInt64? = nil,
        excludeMacJunk: Bool = true,
        encoding: FilenameEncodingOption = .utf8,
        archiveComment: String = "",
        workerCount: Int? = nil,
        preserveSymlinks: Bool = true
    ) {
        self.format = format
        self.algorithm = algorithm
        self.level = level ?? algorithm.defaultLevel
        self.encryption = encryption
        self.password = password
        self.splitVolumeSizeBytes = splitVolumeSizeBytes
        self.excludeMacJunk = excludeMacJunk
        self.encoding = encoding
        self.archiveComment = archiveComment
        self.workerCount = workerCount
        self.preserveSymlinks = preserveSymlinks
    }
}

public struct ExtractOptions: Sendable {
    public var destinationURL: URL
    public var mode: ExtractMode
    public var overwritePolicy: OverwritePolicy
    public var password: String?
    public var encoding: FilenameEncodingOption
    public var stripMacJunk: Bool
    /// `nil` = follow global `BoltConcurrency.preference`; `0` = auto; `>= 1` = explicit core cap.
    public var workerCount: Int?
    public var restoreSymlinks: Bool

    public init(
        destinationURL: URL,
        mode: ExtractMode = .smart,
        overwritePolicy: OverwritePolicy = .overwrite,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        stripMacJunk: Bool = true,
        workerCount: Int? = nil,
        restoreSymlinks: Bool = true
    ) {
        self.destinationURL = destinationURL
        self.mode = mode
        self.overwritePolicy = overwritePolicy
        self.password = password
        self.encoding = encoding
        self.stripMacJunk = stripMacJunk
        self.workerCount = workerCount
        self.restoreSymlinks = restoreSymlinks
    }
}

public struct OperationProgress: Sendable {
    public let fractionCompleted: Double
    public let currentItem: String
    public let processedBytes: UInt64
    public let totalBytes: UInt64

    public init(fractionCompleted: Double, currentItem: String, processedBytes: UInt64 = 0, totalBytes: UInt64 = 0) {
        self.fractionCompleted = min(1.0, max(0.0, fractionCompleted))
        self.currentItem = currentItem
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
    }
}

public struct IntegrityEntryResult: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case passed
        case failed
        case missingPassword
    }

    public let id: String
    public let path: String
    public let status: Status
    public let detail: String

    public init(path: String, status: Status, detail: String) {
        self.id = path
        self.path = path
        self.status = status
        self.detail = detail
    }
}

public struct IntegrityReport: Sendable {
    public let archiveName: String
    public let totalEntries: Int
    public let passedCount: Int
    public let failedCount: Int
    public let skippedEncryptedCount: Int
    public let elapsedSeconds: Double
    public let results: [IntegrityEntryResult]

    public init(
        archiveName: String,
        totalEntries: Int,
        passedCount: Int,
        failedCount: Int,
        skippedEncryptedCount: Int,
        elapsedSeconds: Double,
        results: [IntegrityEntryResult]
    ) {
        self.archiveName = archiveName
        self.totalEntries = totalEntries
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.skippedEncryptedCount = skippedEncryptedCount
        self.elapsedSeconds = elapsedSeconds
        self.results = results
    }

    public var isHealthy: Bool { failedCount == 0 && skippedEncryptedCount == 0 }
}

public struct BenchmarkEntryResult: Identifiable, Sendable {
    public let id: String
    public let algorithm: CompressionAlgorithm
    public let level: Int
    public let originalBytes: Int
    public let compressedBytes: Int
    public let compressMBps: Double
    public let decompressMBps: Double
    public let compressMs: Double
    public let decompressMs: Double

    public var ratioPercent: Double {
        guard originalBytes > 0 else { return 0 }
        return (1.0 - Double(compressedBytes) / Double(originalBytes)) * 100.0
    }
}

public enum MacJunkFilter {
    private static let exactNames: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        "__MACOSX",
        "Thumbs.db",
        "desktop.ini"
    ]

    public static func isJunk(path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        for comp in components {
            if exactNames.contains(comp) { return true }
            if comp.hasPrefix("._") && comp.count > 2 { return true }
        }
        return false
    }
}
