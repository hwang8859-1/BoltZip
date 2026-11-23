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
        case .rar:
            let rar = try ExtendedArchiveDriver.openRAR(at: archiveURL, encoding: encoding, password: password)
            entries = rar.entries
            isSplitVolume = rar.isSplitVolume
        case .sevenZip:
            let sevenZip = try ExtendedArchiveDriver.openSevenZip(at: archiveURL, encoding: encoding, password: password)
            entries = sevenZip.entries
            isSplitVolume = sevenZip.isSplitVolume
        case .iso, .cab, .xar:
            entries = try ExtendedArchiveDriver.listEntries(at: archiveURL, format: format, encoding: encoding, password: password)
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
        let requestsEncryption = options.encryptFileNames || options.encryption != .none || !(options.password ?? "").isEmpty
        if options.encryptFileNames && !options.format.supportsFilenameEncryption {
            throw ArchiveOperationError.filenameEncryptionRequires7z
        }
        if requestsEncryption && !options.format.supportsEncryption {
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
        case .gz, .xz:
            try TarCodec.createSingleStream(from: inputURLs, to: outputURL, options: options, controller: controller, progress: progress)
            return [outputURL]
        case .sevenZip:
            if requestsEncryption {
                guard options.encryption == .aes256 else { throw ArchiveOperationError.sevenZipEncryptionRequiresAES256 }
            }
            let requestsSplit = (options.splitVolumeSizeBytes ?? 0) >= 65536
            let parallelCodec = options.algorithm == .xz || options.algorithm == .bzip2
            if requestsEncryption || requestsSplit || (parallelCodec && BoltConcurrency.resolvedWorkerCount(override: options.workerCount) > 1) {
                return try SevenZipArchiveWriter.create(from: inputURLs, to: outputURL, options: options,
                                                        controller: controller, progress: progress)
            } else {
                try ExtendedArchiveDriver.create7z(
                    from: inputURLs,
                    to: outputURL,
                    algorithm: options.algorithm,
                    level: options.level,
                    excludeMacJunk: options.excludeMacJunk,
                    preserveSymlinks: options.preserveSymlinks,
                    excludePatterns: options.excludePatterns,
                    controller: controller,
                    progress: progress
                )
            }
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent))
            return [outputURL]
        default:
            throw BoltZipError.unsupportedFormat(options.format.displayName)
        }
    }

    public static func editArchive(
        at archiveURL: URL,
        operations: [ArchiveEditOperation],
        options: CreateArchiveOptions = CreateArchiveOptions(),
        encoding: FilenameEncodingOption = .auto,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        let format = try ArchiveFormat.requireForReading(from: archiveURL)
        switch format {
        case .zip:
            try ZipWriter.editArchive(at: archiveURL, operations: operations, options: options, encoding: encoding, progress: progress)
        case .sevenZip:
            try SevenZipEditor.editArchive(at: archiveURL, operations: operations, options: options, progress: progress)
        default:
            throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t(
                "仅 ZIP 与非分卷 7z 格式支持包内增删改",
                "僅 ZIP 與非分卷 7z 格式支援封存檔內編輯",
                "In-place editing is only supported for ZIP and single-file 7z archives",
                "書庫内の直接編集は ZIP と非分割 7z 形式のみ対応しています"
            ))
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

    public static func defaultBaseStem(for inputs: [URL], format: ArchiveFormat = .zip) -> String {
        guard let first = inputs.first else { return "Archive" }
        if inputs.count == 1 {
            let name = first.deletingPathExtension().lastPathComponent
            return name.isEmpty ? "Archive" : name
        }
        let parentName = first.deletingLastPathComponent().lastPathComponent
        return parentName.isEmpty ? "Archive" : parentName
    }

    public static func makeOutputURL(
        stem: String,
        format: ArchiveFormat,
        splitVolumeSizeBytes: UInt64? = nil,
        in directory: URL,
        deduplicating: Bool = true,
        reservedPaths: Set<String> = []
    ) -> URL {
        let fm = FileManager.default
        let isSplit = format.supportsSplitVolumes && (splitVolumeSizeBytes ?? 0) >= 65536
        func candidatePaths(index: Int) -> (output: URL, collisionURLs: [URL]) {
            let suffixedStem = index == 0 ? stem : "\(stem) (\(index))"
            let mainURL = directory.appendingPathComponent("\(suffixedStem).\(format.fileExtension)")
            if isSplit && format == .sevenZip {
                let firstVol = directory.appendingPathComponent("\(suffixedStem).7z.001")
                return (firstVol, [mainURL, firstVol])
            }
            if isSplit && format == .zip {
                let firstVol = directory.appendingPathComponent("\(suffixedStem).z01")
                return (mainURL, [mainURL, firstVol])
            }
            return (mainURL, [mainURL])
        }

        if !deduplicating {
            return candidatePaths(index: 0).output
        }

        var idx = 0
        while idx < 10_000 {
            let candidate = candidatePaths(index: idx)
            let collides = candidate.collisionURLs.contains { url in
                fm.fileExists(atPath: url.path)
                    || reservedPaths.contains(ArchiveExtractionDestination.pathKey(url))
            }
            if !collides {
                return candidate.output
            }
            idx += 1
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(6)).\(format.fileExtension)")
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
