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
        guard let format = ArchiveFormat.detect(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let archiveFileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        let entries: [ArchiveEntry]
        var comment = ""

        switch format {
        case .zip:
            let res = try ZipReader(url: archiveURL).listEntries(encoding: encoding)
            entries = res.entries
            comment = res.comment
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            entries = try TarCodec.listEntries(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            entries = try ExtendedArchiveDriver.listEntries(at: archiveURL, format: format, encoding: encoding, password: password)
        }

        let totalUncomp = entries.reduce(UInt64(0)) { $0 + ($1.isDirectory ? 0 : $1.uncompressedSize) }
        let totalComp = entries.reduce(UInt64(0)) { $0 + ($1.isDirectory ? 0 : $1.compressedSize) }
        let hasEnc = entries.contains { $0.isEncrypted }

        return ArchiveListing(
            archiveURL: archiveURL,
            format: format,
            entries: entries,
            comment: comment,
            totalUncompressedBytes: totalUncomp,
            totalCompressedBytes: totalComp > 0 ? totalComp : archiveFileSize,
            archiveFileSize: archiveFileSize,
            hasEncryptedEntries: hasEnc
        )
    }

    public static func readEntryData(
        archiveURL: URL,
        entryPath: String,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto
    ) throws -> Data {
        guard let format = ArchiveFormat.detect(from: archiveURL) else {
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

    @discardableResult
    public static func createArchive(
        from inputURLs: [URL],
        to outputURL: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> [URL] {
        try controller?.checkpoint()
        switch options.format {
        case .zip:
            return try ZipWriter.create(from: inputURLs, to: outputURL, options: options, controller: controller, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            try TarCodec.create(from: inputURLs, to: outputURL, options: options, controller: controller, progress: progress)
            return [outputURL]
        case .sevenZip:
            progress?(OperationProgress(fractionCompleted: 0.05, currentItem: outputURL.lastPathComponent))
            try ExtendedArchiveDriver.create7z(
                from: inputURLs,
                to: outputURL,
                excludeMacJunk: options.excludeMacJunk,
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
        guard ArchiveFormat.detect(from: archiveURL) == .zip else {
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

    @discardableResult
    public static func extract(
        archiveURL: URL,
        options: ExtractOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> URL {
        try controller?.checkpoint()
        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        try controller?.checkpoint()
        var targetRoot = resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL,
           fm.fileExists(atPath: targetRoot.path) {
            targetRoot = uniqueNonCollidingURL(for: targetRoot, isDirectoryHint: true)
        }
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        // Filter entries according to mode & Mac junk filter
        let entriesToExtract = filterEntriesForExtract(listing.entries, options: options)

        // When auto-renaming at the same root (single-folder Smart Extract or Extract Here),
        // remap conflicting top-level directory names so old and new directories stay cleanly separated.
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
                expectedTotalBytes: estBytes,
                topLevelDirRenameMap: topLevelDirRenameMap,
                controller: controller,
                progress: progress
            )
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent, processedBytes: estBytes, totalBytes: estBytes))
            return targetRoot
        }

        let totalBytes = entriesToExtract.reduce(UInt64(0)) { $0 + ($1.isDirectory ? 0 : $1.uncompressedSize) }

        if listing.format == .zip {
            let reader = ZipReader(url: archiveURL)
            let parsed = try reader.parseArchive()
            let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
            try accessor.configureVolumes(totalDisks: parsed.totalDisks)
            defer { accessor.closeAll() }

            var recordByPath: [String: ZipRecord] = [:]
            for rec in parsed.records {
                let e = ZipReader.makeEntry(from: rec, encoding: options.encoding)
                recordByPath[e.path] = rec
            }

            // Pre-create directory hierarchy and collect file jobs for multi-core parallel extraction
            var parentDirs: Set<URL> = []
            var fileJobs: [(entry: ArchiveEntry, record: ZipRecord, destURL: URL)] = []
            fileJobs.reserveCapacity(entriesToExtract.count)

            for entry in entriesToExtract {
                try controller?.checkpoint()
                let outputPath = remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
                let destURL = try safeDestinationURL(for: outputPath, under: targetRoot)
                if entry.isDirectory {
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                    continue
                }
                guard let rec = recordByPath[entry.path] else { continue }
                parentDirs.insert(destURL.deletingLastPathComponent())
                fileJobs.append((entry: entry, record: rec, destURL: destURL))
            }

            for dir in parentDirs {
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
                    let plain = try reader.decodePayload(
                        record: job.record,
                        entryPath: job.entry.path,
                        accessor: accessor,
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
                    try writeExtractedFile(plain, to: job.destURL, entry: job.entry, policy: options.overwritePolicy)
                }
            } else {
                let writeCollisionLock = NSLock()
                let progressLock = OSAllocatedUnfairLock(initialState: UInt64(0))
                let renameMapLock = writeCollisionLock
                let policy = options.overwritePolicy
                let pw = options.password

                try ParallelExecutor.forEachBounded(fileJobs, controller: controller) { _, job in
                    let plain = try reader.decodePayload(
                        record: job.record,
                        entryPath: job.entry.path,
                        accessor: accessor,
                        password: pw,
                        controller: controller
                    )
                    if policy == .rename {
                        renameMapLock.lock()
                        defer { renameMapLock.unlock() }
                        try Self.writeExtractedFile(plain, to: job.destURL, entry: job.entry, policy: policy)
                    } else {
                        try Self.writeExtractedFile(plain, to: job.destURL, entry: job.entry, policy: policy)
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
        } else {
            var processedBytes: UInt64 = 0
            let total = entriesToExtract.count
            let payloadMap = try TarCodec.readAllEntries(at: archiveURL, format: listing.format, controller: controller) { readBytes, totalCompressed in
                let curBytes = totalBytes > 0 && totalCompressed > 0
                    ? UInt64(Double(totalBytes) * 0.4 * (Double(readBytes) / Double(totalCompressed)))
                    : readBytes
                let frac = totalCompressed > 0 ? 0.4 * (Double(readBytes) / Double(totalCompressed)) : 0.2
                progress?(OperationProgress(
                    fractionCompleted: frac,
                    currentItem: archiveURL.lastPathComponent,
                    processedBytes: curBytes,
                    totalBytes: totalBytes > 0 ? totalBytes : totalCompressed
                ))
            }
            for (idx, entry) in entriesToExtract.enumerated() {
                try controller?.checkpoint()
                let entryFrac = totalBytes > 0
                    ? 0.4 + 0.6 * (Double(processedBytes) / Double(totalBytes))
                    : (total > 0 ? 0.4 + 0.6 * (Double(idx) / Double(total)) : 1.0)
                let reportedBytes = totalBytes > 0 ? UInt64(Double(totalBytes) * entryFrac) : processedBytes
                progress?(OperationProgress(
                    fractionCompleted: entryFrac,
                    currentItem: entry.path,
                    processedBytes: reportedBytes,
                    totalBytes: totalBytes
                ))
                let outputPath = remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
                let destURL = try safeDestinationURL(for: outputPath, under: targetRoot)
                if entry.isDirectory {
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                    continue
                }
                guard let plain = payloadMap[entry.path] else { continue }
                try writeExtractedFile(plain, to: destURL, entry: entry, policy: options.overwritePolicy)
                processedBytes += entry.uncompressedSize
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

    public static func testIntegrity(
        archiveURL: URL,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> IntegrityReport {
        guard let format = ArchiveFormat.detect(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
        switch format {
        case .zip:
            return try ZipReader(url: archiveURL).testIntegrity(password: password, encoding: encoding, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            return try TarCodec.testIntegrity(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            return try ExtendedArchiveDriver.testIntegrity(at: archiveURL, format: format, password: password)
        }
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

    static func writeExtractedFile(
        _ data: Data,
        to initialURL: URL,
        entry: ArchiveEntry,
        policy: OverwritePolicy
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: initialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var targetURL = initialURL
        if fm.fileExists(atPath: targetURL.path) {
            switch policy {
            case .skip:
                return
            case .overwrite:
                try fm.removeItem(at: targetURL)
            case .rename:
                targetURL = uniqueNonCollidingURL(for: initialURL)
            }
        }

        try data.write(to: targetURL, options: .atomic)
        let attrs: [FileAttributeKey: Any] = [
            .modificationDate: entry.modifiedDate,
            .posixPermissions: NSNumber(value: entry.permissions)
        ]
        try? fm.setAttributes(attrs, ofItemAtPath: targetURL.path)
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
