import Foundation

public enum BoltArchiveEngine {
    public static func inspect(
        archiveURL: URL,
        encoding: FilenameEncodingOption = .auto,
        password: String? = nil
    ) throws -> ArchiveListing {
        let format = try ArchiveFormat.requireForReading(from: archiveURL)

        let entries: [ArchiveEntry]
        var comment = ""
        var isSplitVolume = false
        var hasZIPOuterData = false

        switch format {
        case .zip:
            let res = try ZipReader(url: archiveURL).inspectParsedArchive(encoding: encoding)
            entries = res.entries
            comment = res.comment
            isSplitVolume = res.isSplitVolume
            hasZIPOuterData = res.parsed.hasOuterData
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            entries = try TarCodec.listEntries(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            entries = try ExtendedArchiveDriver.listEntries(at: archiveURL, format: format, encoding: encoding, password: password)
            if format == .rar {
                isSplitVolume = ExtendedArchiveDriver.resolveVolumePaths(for: archiveURL, format: .rar).count > 1
            }
        }

        return try makeListing(archiveURL: archiveURL, format: format, entries: entries,
                               comment: comment, isSplitVolume: isSplitVolume, hasZIPOuterData: hasZIPOuterData)
    }

    public static func readEntryData(
        archiveURL: URL,
        entryPath: String,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto
    ) throws -> Data {
        let format = try ArchiveFormat.requireForReading(from: archiveURL)
        switch format {
        case .zip:
            return try ZipReader(url: archiveURL).readEntryData(path: entryPath, password: password, encoding: encoding)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            return try TarCodec.readEntryData(at: archiveURL, format: format, path: entryPath)
        case .rar, .sevenZip, .iso, .cab, .xar:
            return try ExtendedArchiveDriver.readEntryData(
                at: archiveURL,
                format: format,
                path: entryPath,
                password: password,
                encoding: encoding
            )
        }
    }

    @discardableResult
    public static func createArchive(
        from inputURLs: [URL],
        to outputURL: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> [URL] {
        try controller?.checkpoint()
        try ArchiveOutputTransaction.validate(outputURL)
        if !options.format.supportsEncryption && (options.encryption != .none || !(options.password ?? "").isEmpty) {
            throw ArchiveOperationError.encryptionRequiresZIP
        }
        if !options.format.supportsSplitVolumes && (options.splitVolumeSizeBytes ?? 0) > 0 {
            throw ArchiveOperationError.splitVolumesRequireZIP
        }
        switch options.format {
        case .zip:
            return try ZipWriter.create(from: inputURLs, to: outputURL, options: options, controller: controller, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            try TarCodec.create(from: inputURLs, to: outputURL, options: options, controller: controller, progress: progress)
            return [outputURL]
        case .sevenZip:
            try ExtendedArchiveDriver.create7z(
                from: inputURLs,
                to: outputURL,
                algorithm: options.algorithm,
                level: options.level,
                excludeMacJunk: options.excludeMacJunk,
                preserveSymlinks: options.preserveSymlinks,
                controller: controller,
                progress: progress
            )
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent))
            return [outputURL]
        default:
            throw BoltZipError.unsupportedFormat(options.format.displayName)
        }
    }

    public static func editZip(
        at archiveURL: URL,
        operations: [ZipEditOperation],
        options: CreateArchiveOptions = CreateArchiveOptions(),
        encoding: FilenameEncodingOption = .auto,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        guard try ArchiveFormat.detectForReading(from: archiveURL) == .zip else {
            throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t("仅 ZIP 格式支持包内原地增删改", "僅 ZIP 格式支援封存檔內原地編輯", "In-place editing is only supported for ZIP archives", "書庫内での直接編集は ZIP 形式のみ対応しています"))
        }
        try ZipWriter.editArchive(at: archiveURL, operations: operations, options: options, encoding: encoding, progress: progress)
    }

    public static func filterArchiveURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard (try? ArchiveFormat.detectForReading(from: url)) != nil else { return false }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return !isDir
        }
    }

    static func makeListing(
        archiveURL: URL,
        format: ArchiveFormat,
        entries: [ArchiveEntry],
        comment: String = "",
        isSplitVolume: Bool = false,
        hasZIPOuterData: Bool = false
    ) throws -> ArchiveListing {
        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveFileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let totalUncomp = try entries.reduce(UInt64(0)) {
            try ArchiveByteCount.checkedSum($0, $1.isDirectory ? 0 : $1.uncompressedSize)
        }
        let totalComp = try entries.reduce(UInt64(0)) {
            try ArchiveByteCount.checkedSum($0, $1.isDirectory ? 0 : $1.compressedSize)
        }
        let hasEnc = entries.contains { $0.isEncrypted }
        return ArchiveListing(
            archiveURL: archiveURL,
            format: format,
            entries: entries,
            comment: comment,
            totalUncompressedBytes: totalUncomp,
            totalCompressedBytes: totalComp > 0 ? totalComp : archiveFileSize,
            archiveFileSize: archiveFileSize,
            hasEncryptedEntries: hasEnc,
            isSplitVolume: isSplitVolume,
            hasZIPOuterData: hasZIPOuterData
        )
    }
}
