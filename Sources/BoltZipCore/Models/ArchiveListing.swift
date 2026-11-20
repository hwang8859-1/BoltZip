import Foundation

public struct ArchiveListing: Sendable {
    public let archiveURL: URL
    public let format: ArchiveFormat
    public let entries: [ArchiveEntry]
    public let comment: String
    public let totalUncompressedBytes: UInt64
    public let totalCompressedBytes: UInt64
    public let archiveFileSize: UInt64
    public let hasEncryptedEntries: Bool
    public let isSplitVolume: Bool

    public var canEditInPlace: Bool {
        format.supportsInPlaceEditing && !isSplitVolume
    }

    public var overallCompressionRatioPercent: Double {
        guard totalUncompressedBytes > 0 else { return 0 }
        let ratio = (1.0 - Double(totalCompressedBytes) / Double(totalUncompressedBytes)) * 100.0
        return max(-999.0, min(100.0, ratio))
    }
}
