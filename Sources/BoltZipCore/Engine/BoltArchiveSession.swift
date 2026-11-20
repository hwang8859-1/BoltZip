import Darwin
import Foundation
import os

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
        format.supportsInPlaceEditing && !isSplitVolume && archiveURL.pathExtension.lowercased() == "zip"
    }

    public var overallCompressionRatioPercent: Double {
        guard totalUncompressedBytes > 0 else { return 0 }
        let ratio = (1.0 - Double(totalCompressedBytes) / Double(totalUncompressedBytes)) * 100.0
        return max(-999.0, min(100.0, ratio))
    }
}

public enum BoltArchiveEngine {
    public static func inspect(
        archiveURL: URL,
        encoding: FilenameEncodingOption = .auto,
        password: String? = nil
    ) throws -> ArchiveListing {
        guard let format = try ArchiveFormat.detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }

        let entries: [ArchiveEntry]
        var comment = ""
        var isSplitVolume = false

        switch format {
        case .zip:
            let res = try ZipReader(url: archiveURL).inspectArchive(encoding: encoding)
            entries = res.entries
            comment = res.comment
            isSplitVolume = res.isSplitVolume
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            entries = try TarCodec.listEntries(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            entries = try ExtendedArchiveDriver.listEntries(at: archiveURL, format: format, encoding: encoding, password: password)
            if format == .rar {
                isSplitVolume = ExtendedArchiveDriver.resolveVolumePaths(for: archiveURL, format: .rar).count > 1
            }
        }

        return try makeListing(archiveURL: archiveURL, format: format, entries: entries,
                               comment: comment, isSplitVolume: isSplitVolume)
    }

    public static func readEntryData(
        archiveURL: URL,
        entryPath: String,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto
    ) throws -> Data {
        guard let format = try ArchiveFormat.detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
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

    /// Streams a single regular entry directly onto disk without loading its full payload into memory.
    public static func extractSingleEntryToFile(
        archiveURL: URL,
        entryPath: String,
        destinationFileURL: URL,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        controller: ArchiveTaskController? = nil
    ) throws {
        try controller?.checkpoint()
        guard let format = try ArchiveFormat.detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
        let fm = FileManager.default
        let destParent = destinationFileURL.deletingLastPathComponent()
        try fm.createDirectory(at: destParent, withIntermediateDirectories: true)

        switch format {
        case .zip:
            let reader = ZipReader(url: archiveURL)
            let parsed = try reader.parseArchive()
            let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
            try accessor.configureVolumes(totalDisks: parsed.totalDisks)
            defer { accessor.closeAll() }

            let targetNorm = ArchiveEntry.normalizePath(entryPath, isDirectory: entryPath.hasSuffix("/"))
            guard let record = parsed.records.first(where: { ZipReader.makeEntry(from: $0, encoding: encoding).path == targetNorm }) else {
                throw BoltZipError.entryNotFound(entryPath)
            }
            let entry = ZipReader.makeEntry(from: record, encoding: encoding)
            try reader.decodePayloadToFile(
                record: record,
                entryPath: entry.path,
                accessor: accessor,
                destinationURL: destinationFileURL,
                destinationRoot: destParent,
                entry: entry,
                overwritePolicy: .overwrite,
                password: password,
                controller: controller
            )

        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            try TarCodec.extractSingleEntryToFile(
                at: archiveURL,
                format: format,
                path: entryPath,
                to: destinationFileURL,
                controller: controller
            )

        case .rar, .sevenZip, .iso, .cab, .xar:
            let stageDir = try makeExtractionStage(near: destinationFileURL, under: destParent)
            defer { try? fm.removeItem(at: stageDir) }
            try ExtendedArchiveDriver.extract(
                at: archiveURL,
                format: format,
                to: stageDir,
                selectedPaths: [entryPath],
                overwritePolicy: .overwrite,
                password: password,
                encoding: encoding,
                stripMacJunk: false,
                restoreSymlinks: false,
                controller: controller
            )
            let targetNorm = ArchiveEntry.normalizePath(entryPath, isDirectory: entryPath.hasSuffix("/"))
            let stagedFile = try safeDestinationURL(for: targetNorm, under: stageDir)
            guard fm.fileExists(atPath: stagedFile.path) else {
                throw BoltZipError.entryNotFound(entryPath)
            }
            try commitExtractedItem(stagedFile, to: destinationFileURL, under: destParent, policy: .overwrite, controller: controller)
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

    public static func detectExtractConflicts(
        archiveURL: URL,
        options: ExtractOptions
    ) throws -> ExtractConflictSummary {
        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        let targetRoot = resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL {
            if fm.fileExists(atPath: targetRoot.path) {
                return ExtractConflictSummary(
                    destinationRoot: options.destinationURL,
                    conflictingNames: [targetRoot.lastPathComponent]
                )
            }
            return ExtractConflictSummary(destinationRoot: options.destinationURL, conflictingNames: [])
        }

        let entriesToExtract = filterEntriesForExtract(listing.entries, options: options)
        var seen: Set<String> = []
        var conflicts: [String] = []

        switch options.mode {
        case .selected(let chosen):
            var targetRootsToCheck: [String] = []
            for raw in chosen {
                let clean = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
                targetRootsToCheck.append(clean)
            }
            if targetRootsToCheck.isEmpty {
                for entry in entriesToExtract {
                    let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                    guard let top = clean.split(separator: "/").first.map(String.init),
                          seen.insert(top).inserted else { continue }
                    targetRootsToCheck.append(top)
                }
            }
            for rel in targetRootsToCheck {
                if let url = try? safeDestinationURL(for: rel, under: targetRoot),
                   fm.fileExists(atPath: url.path) {
                    conflicts.append(url.lastPathComponent)
                }
            }
        case .smart, .here, .subfolder:
            for entry in entriesToExtract {
                let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                guard let top = clean.split(separator: "/").first.map(String.init),
                      seen.insert(top).inserted else { continue }
                if let url = try? safeDestinationURL(for: top, under: targetRoot),
                   fm.fileExists(atPath: url.path) {
                    conflicts.append(top)
                }
            }
        }

        return ExtractConflictSummary(destinationRoot: targetRoot, conflictingNames: conflicts)
    }

    static func pathMatchesSelection(_ entryPath: String, selectedPaths: Set<String>) -> Bool {
        let cleanEntry = entryPath.hasSuffix("/") ? String(entryPath.dropLast()) : entryPath
        return selectedPaths.contains { sel in
            let cleanSel = sel.hasSuffix("/") ? String(sel.dropLast()) : sel
            return cleanEntry == cleanSel || cleanEntry.hasPrefix(cleanSel + "/")
        }
    }

    private static func filterEntriesForExtract(_ entries: [ArchiveEntry], options: ExtractOptions) -> [ArchiveEntry] {
        entries.filter { entry in
            if options.stripMacJunk && MacJunkFilter.isJunk(path: entry.path) {
                return false
            }
            switch options.mode {
            case .smart, .here, .subfolder:
                return true
            case .selected(let chosen):
                return pathMatchesSelection(entry.path, selectedPaths: chosen)
            }
        }
    }

    static func checkedArchiveSize(_ total: UInt64, adding bytes: UInt64) throws -> UInt64 {
        let (sum, overflow) = total.addingReportingOverflow(bytes)
        guard !overflow, sum <= UInt64(Int64.max) else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t(
                "归档大小超出支持范围", "封存檔大小超出支援範圍", "Archive size exceeds the supported range", "書庫サイズが対応範囲を超えています"
            ))
        }
        return sum
    }

    private static func makeListing(
        archiveURL: URL,
        format: ArchiveFormat,
        entries: [ArchiveEntry],
        comment: String = "",
        isSplitVolume: Bool = false
    ) throws -> ArchiveListing {
        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveFileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let totalUncomp = try entries.reduce(UInt64(0)) {
            try checkedArchiveSize($0, adding: $1.isDirectory ? 0 : $1.uncompressedSize)
        }
        let totalComp = try entries.reduce(UInt64(0)) {
            try checkedArchiveSize($0, adding: $1.isDirectory ? 0 : $1.compressedSize)
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
            isSplitVolume: isSplitVolume
        )
    }

    private static func prepareExtractPlan(
        listing: ArchiveListing,
        options: ExtractOptions
    ) throws -> (targetRoot: URL, entriesToExtract: [ArchiveEntry], topLevelDirRenameMap: [String: String], totalBytes: UInt64) {
        var targetRoot = resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL,
           fm.fileExists(atPath: targetRoot.path) {
            targetRoot = uniqueNonCollidingURL(for: targetRoot, isDirectoryHint: true)
        }
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        let entriesToExtract = filterEntriesForExtract(listing.entries, options: options)

        var topLevelDirRenameMap: [String: String] = [:]
        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL == options.destinationURL.standardizedFileURL {
            var checkedTops: Set<String> = []
            for entry in entriesToExtract {
                let parts = entry.path.split(separator: "/").map(String.init)
                guard let top = parts.first else { continue }
                let isFolderTop = parts.count > 1 || entry.isDirectory
                guard isFolderTop, checkedTops.insert(top).inserted else { continue }
                let existing = targetRoot.appendingPathComponent(top)
                var isDirObjC: ObjCBool = false
                if fm.fileExists(atPath: existing.path, isDirectory: &isDirObjC) {
                    let renamed = uniqueNonCollidingURL(for: existing, isDirectoryHint: true)
                    topLevelDirRenameMap[top] = renamed.lastPathComponent
                }
            }
        }

        let totalBytes = try entriesToExtract.reduce(UInt64(0)) {
            try checkedArchiveSize($0, adding: $1.isDirectory ? 0 : $1.uncompressedSize)
        }
        return (targetRoot, entriesToExtract, topLevelDirRenameMap, totalBytes)
    }

    @discardableResult
    public static func extract(
        archiveURL: URL,
        options: ExtractOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> URL {
        try controller?.checkpoint()
        guard let format = try ArchiveFormat.detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
        let fm = FileManager.default

        if format == .zip {
            let reader = ZipReader(url: archiveURL)
            let parsedInfo = try reader.inspectParsedArchive(encoding: options.encoding)
            let listing = try makeListing(
                archiveURL: archiveURL,
                format: .zip,
                entries: parsedInfo.entries,
                comment: parsedInfo.comment,
                isSplitVolume: parsedInfo.isSplitVolume
            )
            try controller?.checkpoint()
            let (targetRoot, entriesToExtract, topLevelDirRenameMap, totalBytes) = try prepareExtractPlan(listing: listing, options: options)

            let parsed = parsedInfo.parsed
            let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
            try accessor.configureVolumes(totalDisks: parsed.totalDisks)
            defer { accessor.closeAll() }

            let selectedPaths = Set(entriesToExtract.map(\.path))

            var parentDirs: Set<URL> = []
            var fileJobs: [(entry: ArchiveEntry, record: ZipRecord, destURL: URL)] = []
            fileJobs.reserveCapacity(entriesToExtract.count)

            for rec in parsed.records {
                let entry = ZipReader.makeEntry(from: rec, encoding: options.encoding)
                guard selectedPaths.contains(entry.path) else { continue }
                try controller?.checkpoint()
                let outputPath = remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
                let destURL = try safeDestinationURL(for: outputPath, under: targetRoot)
                if entry.isDirectory {
                    try assertNoSymlinkTraversal(at: destURL, under: targetRoot)
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                    continue
                }
                if entry.isSymbolicLink {
                    if options.restoreSymlinks {
                        let targetData = try reader.decodePayload(
                            record: rec,
                            entryPath: entry.path,
                            accessor: accessor,
                            password: options.password,
                            controller: controller
                        )
                        let linkTarget = String(data: targetData, encoding: .utf8) ?? ""
                        try createSafeSymlink(
                            at: destURL,
                            target: linkTarget,
                            under: targetRoot,
                            overwritePolicy: options.overwritePolicy
                        )
                    }
                    continue
                }
                parentDirs.insert(destURL.deletingLastPathComponent())
                fileJobs.append((entry: entry, record: rec, destURL: destURL))
            }

            for dir in parentDirs {
                try assertNoSymlinkTraversal(at: dir.appendingPathComponent("probe"), under: targetRoot)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            if fileJobs.count <= 1 {
                if let job = fileJobs.first {
                    try controller?.checkpoint()
                    progress?(OperationProgress(
                        fractionCompleted: 0,
                        currentItem: job.entry.path,
                        processedBytes: 0,
                        totalBytes: totalBytes
                    ))
                    try reader.decodePayloadToFile(
                        record: job.record,
                        entryPath: job.entry.path,
                        accessor: accessor,
                        destinationURL: job.destURL,
                        destinationRoot: targetRoot,
                        entry: job.entry,
                        overwritePolicy: options.overwritePolicy,
                        password: options.password,
                        controller: controller
                    ) { itemRead, _ in
                        let cur = min(totalBytes, itemRead)
                        let curFrac = totalBytes > 0 ? Double(cur) / Double(totalBytes) : 0
                        progress?(OperationProgress(
                            fractionCompleted: curFrac,
                            currentItem: job.entry.path,
                            processedBytes: cur,
                            totalBytes: totalBytes
                        ))
                    }
                }
            } else {
                let renameMapLock = NSLock()
                let progressLock = OSAllocatedUnfairLock(initialState: UInt64(0))
                let policy = options.overwritePolicy
                let pw = options.password
                let rootDest = targetRoot
                let destinationsAreUnique = Set(fileJobs.map { $0.destURL.path.precomposedStringWithCanonicalMapping.lowercased() }).count == fileJobs.count
                let workers = destinationsAreUnique ? BoltConcurrency.resolvedWorkerCount(override: options.workerCount) : 1

                try ParallelExecutor.forEachBounded(fileJobs, maxWorkers: workers, controller: controller) { _, job in
                    if policy == .rename {
                        renameMapLock.lock()
                        defer { renameMapLock.unlock() }
                        try reader.decodePayloadToFile(
                            record: job.record,
                            entryPath: job.entry.path,
                            accessor: accessor,
                            destinationURL: job.destURL,
                            destinationRoot: rootDest,
                            entry: job.entry,
                            overwritePolicy: policy,
                            password: pw,
                            controller: controller
                        )
                    } else {
                        try reader.decodePayloadToFile(
                            record: job.record,
                            entryPath: job.entry.path,
                            accessor: accessor,
                            destinationURL: job.destURL,
                            destinationRoot: rootDest,
                            entry: job.entry,
                            overwritePolicy: policy,
                            password: pw,
                            controller: controller
                        )
                    }
                    let doneNow = progressLock.withLock { total -> UInt64 in
                        total = min(totalBytes, total + job.entry.uncompressedSize)
                        return total
                    }
                    let frac = totalBytes > 0 ? Double(doneNow) / Double(totalBytes) : 1.0
                    progress?(OperationProgress(
                        fractionCompleted: frac,
                        currentItem: job.entry.path,
                        processedBytes: doneNow,
                        totalBytes: totalBytes
                    ))
                }
            }

            progress?(OperationProgress(
                fractionCompleted: 1.0,
                currentItem: archiveURL.lastPathComponent,
                processedBytes: totalBytes,
                totalBytes: totalBytes
            ))
            return targetRoot
        }

        if format == .tar || format == .tarGz || format == .tarZst || format == .tarXz || format == .tarBz2 || format == .tarLz4 {
            var resolvedRoot = options.destinationURL
            let selectedSet: Set<String>? = {
                if case .selected(let s) = options.mode { return s }
                return nil
            }()
            try TarCodec.withUncompressedTarFile(at: archiveURL, format: format, controller: controller, progress: { readBytes, totalCompressed in
                let frac = totalCompressed > 0 ? 0.35 * (Double(readBytes) / Double(totalCompressed)) : 0.1
                progress?(OperationProgress(fractionCompleted: frac, currentItem: archiveURL.lastPathComponent, processedBytes: readBytes, totalBytes: totalCompressed))
            }) { tarURL in
                let entries = try TarCodec.streamScanTar(at: tarURL, methodLabel: format.defaultAlgorithm.shortName, computeCRC: false)
                let listing = try makeListing(archiveURL: archiveURL, format: format, entries: entries)
                try controller?.checkpoint()
                let (targetRoot, _, topLevelDirRenameMap, totalBytes) = try prepareExtractPlan(listing: listing, options: options)
                resolvedRoot = targetRoot

                try TarCodec.streamExtractTarFile(
                    at: tarURL,
                    to: targetRoot,
                    selectedPaths: selectedSet,
                    stripMacJunk: options.stripMacJunk,
                    overwritePolicy: options.overwritePolicy,
                    restoreSymlinks: options.restoreSymlinks,
                    topLevelDirRenameMap: topLevelDirRenameMap,
                    baseFrac: format == .tar ? 0.0 : 0.35,
                    totalExpectedBytes: totalBytes,
                    controller: controller,
                    progress: progress
                )
                progress?(OperationProgress(
                    fractionCompleted: 1.0,
                    currentItem: archiveURL.lastPathComponent,
                    processedBytes: totalBytes,
                    totalBytes: totalBytes
                ))
            }
            return resolvedRoot
        }

        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        try controller?.checkpoint()
        let (targetRoot, _, topLevelDirRenameMap, totalBytes) = try prepareExtractPlan(listing: listing, options: options)

        if listing.format == .rar || listing.format == .sevenZip || listing.format == .iso || listing.format == .cab || listing.format == .xar {
            let selectedSet: Set<String>?
            if case .selected(let s) = options.mode {
                selectedSet = s
            } else {
                selectedSet = nil
            }
            let estBytes = listing.totalUncompressedBytes > 0 ? listing.totalUncompressedBytes : listing.archiveFileSize
            progress?(OperationProgress(fractionCompleted: 0.05, currentItem: archiveURL.lastPathComponent, processedBytes: 0, totalBytes: estBytes))
            try ExtendedArchiveDriver.extract(
                at: archiveURL,
                format: listing.format,
                to: targetRoot,
                selectedPaths: selectedSet,
                overwritePolicy: options.overwritePolicy,
                password: options.password,
                encoding: options.encoding,
                stripMacJunk: options.stripMacJunk,
                restoreSymlinks: options.restoreSymlinks,
                expectedTotalBytes: estBytes,
                topLevelDirRenameMap: topLevelDirRenameMap,
                controller: controller,
                progress: progress
            )
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent, processedBytes: estBytes, totalBytes: estBytes))
            return targetRoot
        }

        let selectedSet: Set<String>?
        if case .selected(let s) = options.mode {
            selectedSet = s
        } else {
            selectedSet = nil
        }
        try TarCodec.extract(
            at: archiveURL,
            format: listing.format,
            to: targetRoot,
            selectedPaths: selectedSet,
            stripMacJunk: options.stripMacJunk,
            overwritePolicy: options.overwritePolicy,
            restoreSymlinks: options.restoreSymlinks,
            topLevelDirRenameMap: topLevelDirRenameMap,
            totalExpectedBytes: totalBytes,
            controller: controller,
            progress: progress
        )

        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: archiveURL.lastPathComponent,
            processedBytes: totalBytes,
            totalBytes: totalBytes
        ))
        return targetRoot
    }

    public static func testIntegrity(
        archiveURL: URL,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        workerCount: Int? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> IntegrityReport {
        guard let format = try ArchiveFormat.detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
        switch format {
        case .zip:
            return try ZipReader(url: archiveURL).testIntegrity(password: password, encoding: encoding, workerCount: workerCount, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            return try TarCodec.testIntegrity(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            return try ExtendedArchiveDriver.testIntegrity(at: archiveURL, format: format, password: password)
        }
    }

    public static func filterArchiveURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard (try? ArchiveFormat.detectForReading(from: url)) != nil else { return false }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return !isDir
        }
    }

    public static func testIntegrityBatch(
        archiveURLs: [URL],
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        workerCount: Int? = nil,
        batchTitle: String? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) -> IntegrityReport {
        let start = CFAbsoluteTimeGetCurrent()
        let totalArchives = max(1, archiveURLs.count)
        var allResults: [IntegrityEntryResult] = []
        var totalPassed = 0
        var totalFailed = 0
        var totalSkipped = 0

        for (index, url) in archiveURLs.enumerated() {
            let baseFrac = Double(index) / Double(totalArchives)
            let spanFrac = 1.0 / Double(totalArchives)
            progress?(OperationProgress(
                fractionCompleted: baseFrac,
                currentItem: url.lastPathComponent,
                processedBytes: UInt64(index),
                totalBytes: UInt64(totalArchives)
            ))

            do {
                let single = try testIntegrity(archiveURL: url, password: password, encoding: encoding, workerCount: workerCount) { sub in
                    progress?(OperationProgress(
                        fractionCompleted: min(1.0, baseFrac + sub.fractionCompleted * spanFrac),
                        currentItem: "\(url.lastPathComponent): \(sub.currentItem)",
                        processedBytes: UInt64(index),
                        totalBytes: UInt64(totalArchives)
                    ))
                }
                totalPassed += single.passedCount
                totalFailed += single.failedCount
                totalSkipped += single.skippedEncryptedCount
                for item in single.results {
                    let scopedPath = archiveURLs.count > 1
                        ? "\(url.lastPathComponent) / \(item.path)"
                        : item.path
                    allResults.append(IntegrityEntryResult(path: scopedPath, status: item.status, detail: item.detail))
                }
            } catch BoltZipError.passwordRequired {
                totalSkipped += 1
                allResults.append(IntegrityEntryResult(
                    path: url.lastPathComponent,
                    status: .missingPassword,
                    detail: BoltCoreLocalization.t("归档已加密，需要密码", "封存檔已加密，需要密碼", "Archive is encrypted; password required", "書庫が暗号化されています（パスワードが必要）")
                ))
            } catch {
                totalFailed += 1
                allResults.append(IntegrityEntryResult(
                    path: url.lastPathComponent,
                    status: .failed,
                    detail: error.localizedDescription
                ))
            }
        }

        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: BoltCoreLocalization.t("校验完成", "驗證完成", "Verification complete", "検証完了"),
            processedBytes: UInt64(totalArchives),
            totalBytes: UInt64(totalArchives)
        ))

        let title = batchTitle ?? (archiveURLs.count == 1
            ? archiveURLs[0].lastPathComponent
            : BoltCoreLocalization.t(
                "\(archiveURLs.count) 个压缩包",
                "\(archiveURLs.count) 個封存檔",
                "\(archiveURLs.count) Archives",
                "\(archiveURLs.count) 件の書庫"
            ))
        return IntegrityReport(
            archiveName: title,
            totalEntries: allResults.count,
            passedCount: totalPassed,
            failedCount: totalFailed,
            skippedEncryptedCount: totalSkipped,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
            results: allResults
        )
    }

    /// Bandizip/Windows-Zip style smart destination folder detection
    public static func resolveExtractDestination(listing: ArchiveListing, options: ExtractOptions) -> URL {
        switch options.mode {
        case .here, .selected:
            return options.destinationURL
        case .subfolder:
            return options.destinationURL.appendingPathComponent(archiveBaseStem(listing.archiveURL), isDirectory: true)
        case .smart:
            let cleanEntries = listing.entries.filter { !MacJunkFilter.isJunk(path: $0.path) }
            let roots = Set(cleanEntries.compactMap { entry -> String? in
                let parts = entry.path.split(separator: "/")
                return parts.first.map(String.init)
            })
            if roots.count <= 1 {
                return options.destinationURL
            }
            return options.destinationURL.appendingPathComponent(archiveBaseStem(listing.archiveURL), isDirectory: true)
        }
    }

    public static func archiveBaseStem(_ url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.zst", ".tar.xz", ".tar.bz2", ".tar.lz4"] where lower.hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    static func safeDestinationURL(for entryPath: String, under rootURL: URL) throws -> URL {
        let components = entryPath.split(separator: "/").map(String.init)
        if components.contains("..") || entryPath.hasPrefix("/") {
            throw BoltZipError.pathTraversalDetected(entryPath)
        }
        let resolvedRoot = rootURL.standardizedFileURL
        let candidate = resolvedRoot.appendingPathComponent(entryPath).standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : (resolvedRoot.path + "/")
        guard candidate.path == resolvedRoot.path || candidate.path.hasPrefix(rootPrefix) else {
            throw BoltZipError.pathTraversalDetected(entryPath)
        }
        return candidate
    }

    static func assertNoSymlinkTraversal(at url: URL, under rootURL: URL) throws {
        let fm = FileManager.default
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : (resolvedRoot.path + "/")

        var probe = url.deletingLastPathComponent()
        while (try? fm.attributesOfItem(atPath: probe.path)) == nil && probe.path != "/" && probe.path != resolvedRoot.path {
            probe = probe.deletingLastPathComponent()
        }
        let resolvedAncestor = probe.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedAncestor.path == resolvedRoot.path || resolvedAncestor.path.hasPrefix(rootPrefix) else {
            throw BoltZipError.pathTraversalDetected(url.lastPathComponent)
        }
    }

    static func prepareExtractTargetURL(
        initialURL: URL,
        under rootURL: URL,
        policy: OverwritePolicy
    ) throws -> URL? {
        try assertNoSymlinkTraversal(at: initialURL, under: rootURL)
        let fm = FileManager.default
        try fm.createDirectory(at: initialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var targetURL = initialURL
        if let attrs = try? fm.attributesOfItem(atPath: targetURL.path) {
            let isExistingDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
            switch policy {
            case .skip:
                return nil
            case .overwrite:
                if isExistingDirectory {
                    // Never recursively delete an existing directory to overwrite it with a file
                    targetURL = uniqueNonCollidingURL(for: initialURL)
                }
            case .rename:
                targetURL = uniqueNonCollidingURL(for: initialURL)
            }
        }
        return targetURL
    }

    /// Publishes a regular file extracted by a caller, using the same collision and atomic replacement rules.
    @discardableResult
    public static func publishExtractedFile(from source: URL, to destination: URL,
                                            under root: URL, policy: OverwritePolicy) throws -> URL? {
        guard let target = try prepareExtractTargetURL(initialURL: destination, under: root, policy: policy) else { return nil }
        let stage = try makeExtractionStage(near: target, under: root)
        defer { try? FileManager.default.removeItem(at: stage) }
        let staged = stage.appendingPathComponent("payload")
        try FileManager.default.moveItem(at: source, to: staged)
        try commitExtractedItem(staged, to: target, under: root, policy: policy)
        return target
    }

    static func makeExtractionStage(near target: URL, under root: URL) throws -> URL {
        try assertNoSymlinkTraversal(at: target, under: root)
        let folder = target.deletingLastPathComponent()
            .appendingPathComponent(".boltzip-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return folder
    }

    static func commitExtractedItem(
        _ staged: URL,
        to target: URL,
        under root: URL,
        policy: OverwritePolicy,
        controller: ArchiveTaskController? = nil
    ) throws {
        try controller?.checkpoint()
        try assertNoSymlinkTraversal(at: target, under: root)
        let result = staged.withUnsafeFileSystemRepresentation { source in
            target.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return EINVAL }
                if policy == .overwrite {
                    return Darwin.rename(source, destination) == 0 ? 0 : errno
                }
                return renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
        if result != 0 {
            if policy == .skip && result == EEXIST { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    static func createSafeSymlink(
        at initialURL: URL,
        target: String,
        under rootURL: URL,
        overwritePolicy: OverwritePolicy
    ) throws {
        let cleanTarget = target.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !cleanTarget.isEmpty, !cleanTarget.hasPrefix("/") else {
            throw BoltZipError.pathTraversalDetected("\(initialURL.lastPathComponent) -> \(target)")
        }
        try assertNoSymlinkTraversal(at: initialURL, under: rootURL)

        let fm = FileManager.default
        let parentDir = initialURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : (resolvedRoot.path + "/")
        let resolvedParent = parentDir.resolvingSymlinksInPath().standardizedFileURL
        let resolvedTarget = URL(fileURLWithPath: cleanTarget, relativeTo: resolvedParent).standardizedFileURL
        guard resolvedTarget.path == resolvedRoot.path || resolvedTarget.path.hasPrefix(rootPrefix) else {
            throw BoltZipError.pathTraversalDetected("\(initialURL.lastPathComponent) -> \(cleanTarget)")
        }

        guard let finalURL = try prepareExtractTargetURL(initialURL: initialURL, under: rootURL, policy: overwritePolicy) else { return }
        let stage = try makeExtractionStage(near: finalURL, under: rootURL)
        defer { try? fm.removeItem(at: stage) }
        let stagedLink = stage.appendingPathComponent("link")
        try fm.createSymbolicLink(atPath: stagedLink.path, withDestinationPath: cleanTarget)
        try commitExtractedItem(stagedLink, to: finalURL, under: rootURL, policy: overwritePolicy)
    }

    static func writeExtractedFile(
        _ data: Data,
        to initialURL: URL,
        under root: URL,
        entry: ArchiveEntry,
        policy: OverwritePolicy,
        controller: ArchiveTaskController?
    ) throws {
        guard let target = try prepareExtractTargetURL(initialURL: initialURL, under: root, policy: policy) else { return }
        let fm = FileManager.default
        let stage = try makeExtractionStage(near: target, under: root)
        defer { try? fm.removeItem(at: stage) }
        let stagedFile = stage.appendingPathComponent("payload")
        try data.write(to: stagedFile)
        try? fm.setAttributes([
            .modificationDate: entry.modifiedDate,
            .posixPermissions: NSNumber(value: entry.permissions)
        ], ofItemAtPath: stagedFile.path)
        try commitExtractedItem(stagedFile, to: target, under: root, policy: policy, controller: controller)
    }

    static func remapTopLevelFolder(in entryPath: String, renameMap: [String: String]) -> String {
        guard !renameMap.isEmpty else { return entryPath }
        let parts = entryPath.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first, let replacement = renameMap[String(first)] else {
            return entryPath
        }
        let suffixStart = entryPath.index(entryPath.startIndex, offsetBy: first.count)
        return replacement + entryPath[suffixStart...]
    }

    static func uniqueNonCollidingURL(for url: URL, isDirectoryHint: Bool = false) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let ext = isDirectoryHint ? "" : url.pathExtension
        let stem = isDirectoryHint ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }
}
