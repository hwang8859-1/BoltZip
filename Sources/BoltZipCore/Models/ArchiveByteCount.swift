enum ArchiveByteCount {
    static func checkedSum(_ total: UInt64, _ bytes: UInt64) throws -> UInt64 {
        let (sum, overflow) = total.addingReportingOverflow(bytes)
        guard !overflow, sum <= UInt64(Int64.max) else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t(
                "归档大小超出支持范围", "封存檔大小超出支援範圍", "Archive size exceeds the supported range", "書庫サイズが対応範囲を超えています"
            ))
        }
        return sum
    }
}
