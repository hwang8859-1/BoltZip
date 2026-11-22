import Foundation
import os

extension BoltArchiveEngine {
    public static func extractionSourceURLs(archiveURL: URL, password: String? = nil) throws -> [URL] {
        switch try ArchiveFormat.requireForReading(from: archiveURL) {
        case .zip:
            let parsed = try ZipReader(url: archiveURL).parseArchive()
            let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
            try accessor.configureVolumes(totalDisks: parsed.totalDisks)
            return accessor.volumeURLs + [archiveURL]
        case .rar:
            let volumes = try ExtendedArchiveDriver.rarVolumes(at: archiveURL, password: password)
            return volumes.paths.map { URL(fileURLWithPath: $0) } + [archiveURL]
        case .sevenZip:
            let volumes = try SevenZipVolumeDiscovery.resolve(archiveURL)
            return volumes.paths.map { URL(fileURLWithPath: $0) } + [archiveURL]
        default:
            return [archiveURL]
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
        let format = try ArchiveFormat.requireForReading(from: archiveURL)
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
            try ArchiveExtractionDestination.protectSources(accessor.volumeURLs + [archiveURL], from: destinationFileURL)

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
            try ArchiveExtractionDestination.protectSources([archiveURL], from: destinationFileURL)
            try TarCodec.extractSingleEntryToFile(
                at: archiveURL,
                format: format,
                path: entryPath,
                to: destinationFileURL,
                controller: controller
            )

        case .rar, .sevenZip, .iso, .cab, .xar:
            let protected = Set(try extractionSourceURLs(archiveURL: archiveURL, password: password)
                .map(ArchiveExtractionDestination.pathKey))
            try ArchiveExtractionDestination.protectSourcePaths(protected, from: destinationFileURL)
            let stageDir = try ArchiveExtractionDestination.makeExtractionStage(near: destinationFileURL, under: destParent)
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
            let stagedFile = try ArchiveExtractionDestination.safeDestinationURL(for: targetNorm, under: stageDir)
            guard fm.fileExists(atPath: stagedFile.path) else {
                throw BoltZipError.entryNotFound(entryPath)
            }
            try ArchiveExtractionDestination.commitExtractedItem(stagedFile, to: destinationFileURL, under: destParent,
                                                                 policy: .overwrite, protectedSourcePaths: protected, controller: controller)
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
        let format = try ArchiveFormat.requireForReading(from: archiveURL)

        switch format {
        case .zip:
            return try extractZip(archiveURL: archiveURL, options: options, controller: controller, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            return try extractTar(archiveURL: archiveURL, format: format, options: options, controller: controller, progress: progress)
        default:
            return try extractOtherFormats(archiveURL: archiveURL, options: options, controller: controller, progress: progress)
        }
    }

    private static func extractZip(
        archiveURL: URL,
        options: ExtractOptions,
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws -> URL {
        let fm = FileManager.default
        let reader = ZipReader(url: archiveURL)
        let parsedInfo = try reader.inspectParsedArchive(encoding: options.encoding)
        let listing = try makeListing(
            archiveURL: archiveURL,
            format: .zip,
            entries: parsedInfo.entries,
            comment: parsedInfo.comment,
            isSplitVolume: parsedInfo.isSplitVolume,
            hasZIPOuterData: parsedInfo.parsed.hasOuterData
        )
        try controller?.checkpoint()
        let parsed = parsedInfo.parsed
        let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
        try accessor.configureVolumes(totalDisks: parsed.totalDisks)
        defer { accessor.closeAll() }
        let plan = try ArchiveExtractionPlan.prepare(listing: listing, options: options, sourceURLs: accessor.volumeURLs + [archiveURL])
        let targetRoot = plan.targetRoot
        let totalBytes = plan.totalBytes

        let selectedPaths = Set(plan.entries.map(\.path))

        var parentDirs: Set<URL> = []
        var fileJobs: [(entry: ArchiveEntry, record: ZipRecord, destURL: URL)] = []
        fileJobs.reserveCapacity(plan.entries.count)

        for rec in parsed.records {
            let entry = ZipReader.makeEntry(from: rec, encoding: options.encoding)
            guard selectedPaths.contains(entry.path) else { continue }
            try controller?.checkpoint()
            let outputPath = ArchiveExtractionDestination.remapTopLevelFolder(in: entry.path, renameMap: plan.topLevelDirRenameMap)
            let destURL = try ArchiveExtractionDestination.safeDestinationURL(for: outputPath, under: targetRoot)
            if entry.isDirectory {
                try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: destURL, under: targetRoot)
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
                    try ArchiveExtractionDestination.createSafeSymlink(
                        at: destURL,
                        target: linkTarget,
                        under: targetRoot,
                        overwritePolicy: options.overwritePolicy,
                        protectedSourcePaths: plan.protectedSourcePaths
                    )
                }
                continue
            }
            parentDirs.insert(destURL.deletingLastPathComponent())
            fileJobs.append((entry: entry, record: rec, destURL: destURL))
        }

        for dir in parentDirs {
            try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: dir.appendingPathComponent("probe"), under: targetRoot)
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
                    protectedSourcePaths: plan.protectedSourcePaths,
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
                do {
                    if policy == .rename { renameMapLock.lock() }
                    defer { if policy == .rename { renameMapLock.unlock() } }
                    try reader.decodePayloadToFile(
                        record: job.record,
                        entryPath: job.entry.path,
                        accessor: accessor,
                        destinationURL: job.destURL,
                        destinationRoot: rootDest,
                        entry: job.entry,
                        overwritePolicy: policy,
                        password: pw,
                        protectedSourcePaths: plan.protectedSourcePaths,
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

    private static func extractTar(
        archiveURL: URL,
        format: ArchiveFormat,
        options: ExtractOptions,
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws -> URL {
        var resolvedRoot = options.destinationURL
        let selectedSet = selectedPaths(for: options.mode)
        try TarCodec.withUncompressedTarFile(at: archiveURL, format: format, controller: controller, progress: { readBytes, totalCompressed in
            let frac = totalCompressed > 0 ? 0.35 * (Double(readBytes) / Double(totalCompressed)) : 0.1
            progress?(OperationProgress(fractionCompleted: frac, currentItem: archiveURL.lastPathComponent, processedBytes: readBytes, totalBytes: totalCompressed))
        }) { tarURL in
            let entries = try TarCodec.streamScanTar(at: tarURL, methodLabel: format.defaultAlgorithm.shortName, computeCRC: false)
            let listing = try makeListing(archiveURL: archiveURL, format: format, entries: entries)
            try controller?.checkpoint()
            let plan = try ArchiveExtractionPlan.prepare(listing: listing, options: options, sourceURLs: [archiveURL])
            resolvedRoot = plan.targetRoot

            try TarCodec.streamExtractTarFile(
                at: tarURL,
                to: plan.targetRoot,
                selectedPaths: selectedSet,
                stripMacJunk: options.stripMacJunk,
                overwritePolicy: options.overwritePolicy,
                restoreSymlinks: options.restoreSymlinks,
                topLevelDirRenameMap: plan.topLevelDirRenameMap,
                baseFrac: format == .tar ? 0.0 : 0.35,
                totalExpectedBytes: plan.totalBytes,
                protectedSourcePaths: plan.protectedSourcePaths,
                controller: controller,
                progress: progress
            )
            progress?(OperationProgress(
                fractionCompleted: 1.0,
                currentItem: archiveURL.lastPathComponent,
                processedBytes: plan.totalBytes,
                totalBytes: plan.totalBytes
            ))
        }
        return resolvedRoot
    }

    private static func extractOtherFormats(
        archiveURL: URL,
        options: ExtractOptions,
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws -> URL {
        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        try controller?.checkpoint()
        let sources = try extractionSourceURLs(archiveURL: archiveURL, password: options.password)
        let plan = try ArchiveExtractionPlan.prepare(listing: listing, options: options, sourceURLs: sources)
        let targetRoot = plan.targetRoot

        let selectedSet = selectedPaths(for: options.mode)
        if listing.format == .rar || listing.format == .sevenZip || listing.format == .iso || listing.format == .cab || listing.format == .xar {
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
                topLevelDirRenameMap: plan.topLevelDirRenameMap,
                protectedSourcePaths: plan.protectedSourcePaths,
                controller: controller,
                progress: progress
            )
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent, processedBytes: estBytes, totalBytes: estBytes))
            return targetRoot
        }

        try TarCodec.extract(
            at: archiveURL,
            format: listing.format,
            to: targetRoot,
            selectedPaths: selectedSet,
            stripMacJunk: options.stripMacJunk,
            overwritePolicy: options.overwritePolicy,
            restoreSymlinks: options.restoreSymlinks,
            topLevelDirRenameMap: plan.topLevelDirRenameMap,
            totalExpectedBytes: plan.totalBytes,
            protectedSourcePaths: plan.protectedSourcePaths,
            controller: controller,
            progress: progress
        )

        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: archiveURL.lastPathComponent,
            processedBytes: plan.totalBytes,
            totalBytes: plan.totalBytes
        ))
        return targetRoot
    }

    private static func selectedPaths(for mode: ExtractMode) -> Set<String>? {
        if case .selected(let paths) = mode { return paths }
        return nil
    }
}
