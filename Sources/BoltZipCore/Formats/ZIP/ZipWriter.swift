import Foundation
import os

public enum ArchiveEditOperation: Sendable {
    case addItems(urls: [URL], targetFolder: String)
    case createFolder(path: String)
    case deletePaths(Set<String>)
    case renamePath(oldPath: String, newPath: String)
    case setComment(String)
    case replaceEntry(path: String, fileURL: URL)
}

public typealias ZipEditOperation = ArchiveEditOperation

public enum ZipWriter {

    private enum PreparedPayload: @unchecked Sendable {
        case memory(Data)
        case file(url: URL, size: UInt64, deleteAfterWrite: Bool)

        var compressedSize: UInt64 {
            switch self {
            case .memory(let data): return UInt64(data.count)
            case .file(_, let size, _): return size
            }
        }
    }

    private struct PreparedZipItem: Sendable {
        let rawPathBytes: Data
        let flags: UInt16
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let payload: PreparedPayload
        let uncompressedSize: UInt64
        let externalAttrs: UInt32
        let extraWithoutZip64: Data
        let commentData: Data

        func cleanupTempIfNeeded() {
            if case .file(let url, _, let shouldDelete) = payload, shouldDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    struct CentralDirEntry {
        let rawPathBytes: Data
        let flags: UInt16
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let diskStart: UInt32
        let localOffset: UInt64
        let externalAttrs: UInt32
        let cdExtra: Data
        let commentData: Data
    }

    @discardableResult
    public static func create(
        from inputURLs: [URL],
        to outputURL: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> [URL] {
        try controller?.checkpoint()
        let items = try ArchiveInputCollector.collect(
            from: inputURLs,
            excludeMacJunk: options.excludeMacJunk,
            preserveSymlinks: options.preserveSymlinks,
            excludePatterns: options.excludePatterns,
            excluding: [outputURL], controller: controller
        )
        let sink = try ZipVolumeSink(outputURL: outputURL, splitLimit: options.splitVolumeSizeBytes)
        do {
            let totalBytes = items.reduce(UInt64(0)) { $0 + $1.fileSize }
            var cdEntries: [CentralDirEntry] = []
            cdEntries.reserveCapacity(items.count)

            try writeNewItems(
                items,
                options: options,
                sink: sink,
                controller: controller,
                totalBytes: totalBytes,
                cdEntries: &cdEntries,
                progress: progress
            )

            try controller?.checkpoint()
            try finishCentralDirectory(entries: cdEntries, comment: options.archiveComment, sink: sink)
            let created = try sink.finalizeAll()
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent, processedBytes: totalBytes, totalBytes: totalBytes))
            return created
        } catch {
            sink.abortCleanup()
            throw error
        }
    }

    public static func editArchive(
        at archiveURL: URL,
        operations: [ZipEditOperation],
        options: CreateArchiveOptions = CreateArchiveOptions(),
        encoding: FilenameEncodingOption = .auto,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        let reader = ZipReader(url: archiveURL)
        let parsed = try reader.parseArchive()
        if parsed.totalDisks > 1 || ZipVolumeAccessor.isNumberedVolume(archiveURL) {
            throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t(
                "分卷 ZIP 归档不支持包内原地编辑，请先解压或另存为单文件 ZIP",
                "分卷 ZIP 封存檔不支援封存檔內原地編輯，請先解壓或另存為單一 ZIP",
                "In-place editing is not supported for split-volume ZIP archives",
                "分割 ZIP 書庫の直接編集には対応していません"
            ))
        }
        if parsed.hasOuterData {
            throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t(
                "带额外前缀或尾部数据的 ZIP 归档不支持原地编辑",
                "帶有額外前綴或結尾資料的 ZIP 封存檔不支援原地編輯",
                "In-place editing is not supported for ZIP archives with data before or after the archive",
                "書庫の前後に追加データがある ZIP 書庫の直接編集には対応していません"
            ))
        }
        let accessor = try ZipVolumeAccessor(archiveURL: archiveURL)
        try accessor.configureVolumes(totalDisks: parsed.totalDisks)
        defer { accessor.closeAll() }

        // Represent mutable list of existing records with current decoded path
        struct MutableExisting {
            var decodedPath: String
            var isDirectory: Bool
            var record: ZipRecord
        }

        var existing: [MutableExisting] = parsed.records.map { rec in
            let entry = ZipReader.makeEntry(from: rec, encoding: encoding)
            return MutableExisting(decodedPath: entry.path, isDirectory: entry.isDirectory, record: rec)
        }
        var itemsToAdd: [(targetFolder: String, url: URL)] = []
        var foldersToCreate: [String] = []
        var resolvedComment = parsed.comment
        var replacements: [String: ArchiveInputItem] = [:]

        for op in operations {
            switch op {
            case .deletePaths(let targets):
                let normalizedTargets = targets.map { ArchiveEntry.normalizePath($0, isDirectory: $0.hasSuffix("/")) }
                existing.removeAll { item in
                    normalizedTargets.contains { target in
                        if target.hasSuffix("/") {
                            return item.decodedPath == target || item.decodedPath.hasPrefix(target)
                        } else {
                            return item.decodedPath == target || item.decodedPath.hasPrefix(target + "/")
                        }
                    }
                }
            case .renamePath(let oldPath, let newPath):
                let oldNorm = ArchiveEntry.normalizePath(oldPath, isDirectory: oldPath.hasSuffix("/"))
                let newNorm = ArchiveEntry.normalizePath(newPath, isDirectory: newPath.hasSuffix("/") || oldNorm.hasSuffix("/"))
                if oldNorm.hasSuffix("/") {
                    let newPrefix = newNorm.hasSuffix("/") ? newNorm : (newNorm + "/")
                    for idx in existing.indices {
                        if existing[idx].decodedPath == oldNorm {
                            existing[idx].decodedPath = newPrefix
                        } else if existing[idx].decodedPath.hasPrefix(oldNorm) {
                            let suffix = existing[idx].decodedPath.dropFirst(oldNorm.count)
                            existing[idx].decodedPath = newPrefix + suffix
                        }
                    }
                } else {
                    for idx in existing.indices where existing[idx].decodedPath == oldNorm {
                        existing[idx].decodedPath = newNorm
                    }
                }
            case .createFolder(let path):
                let norm = ArchiveEntry.normalizePath(path, isDirectory: true)
                if !norm.isEmpty {
                    foldersToCreate.append(norm)
                }
            case .addItems(let urls, let targetFolder):
                let prefix = ArchiveEntry.normalizePath(targetFolder, isDirectory: true)
                for url in urls {
                    itemsToAdd.append((targetFolder: prefix, url: url))
                }
            case .setComment(let newComment):
                resolvedComment = newComment
            case .replaceEntry(let path, let fileURL):
                let path = ArchiveEntry.normalizePath(path, isDirectory: false)
                guard let original = existing.first(where: { $0.decodedPath == path && !$0.isDirectory }) else {
                    throw BoltZipError.entryNotFound(path)
                }
                guard existing.filter({ $0.decodedPath == path }).count == 1 else {
                    throw ArchiveEditCompatibilityError.ambiguousEntry(path)
                }
                let entry = ZipReader.makeEntry(from: original.record, encoding: encoding)
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular else { throw BoltZipError.entryNotFound(fileURL.lastPathComponent) }
                replacements[path] = ArchiveInputItem(archivePath: path, fileURL: fileURL, isDirectory: false,
                    isSymbolicLink: false, symlinkTarget: nil, modifiedDate: Date(), permissions: entry.permissions,
                    fileSize: (attrs[.size] as? NSNumber)?.uint64Value ?? 0)
            }
        }

        // Collect new files to add
        var newInputs: [ArchiveInputItem] = []
        for folder in foldersToCreate {
            if !existing.contains(where: { $0.decodedPath == folder }) {
                newInputs.append(ArchiveInputItem(
                    archivePath: folder,
                    fileURL: nil,
                    isDirectory: true,
                    isSymbolicLink: false,
                    symlinkTarget: nil,
                    modifiedDate: Date(),
                    permissions: 0o755,
                    fileSize: 0
                ))
            }
        }
        for pair in itemsToAdd {
            let collected = try ArchiveInputCollector.collect(
                from: [pair.url],
                excludeMacJunk: options.excludeMacJunk,
                preserveSymlinks: options.preserveSymlinks,
                excludePatterns: options.excludePatterns
            )
            for var item in collected {
                let prefixed = pair.targetFolder.isEmpty ? item.archivePath : (pair.targetFolder + item.archivePath)
                item = ArchiveInputItem(
                    archivePath: prefixed,
                    fileURL: item.fileURL,
                    isDirectory: item.isDirectory,
                    isSymbolicLink: item.isSymbolicLink,
                    symlinkTarget: item.symlinkTarget,
                    modifiedDate: item.modifiedDate,
                    permissions: item.permissions,
                    fileSize: item.fileSize
                )
                // Replace same-path existing entry like Windows Zip
                if existing.contains(where: { $0.decodedPath == item.archivePath }) {
                    guard existing.filter({ $0.decodedPath == item.archivePath }).count == 1 else {
                        throw ArchiveEditCompatibilityError.ambiguousEntry(item.archivePath)
                    }
                    replacements[item.archivePath] = item
                } else {
                    newInputs.removeAll { $0.archivePath == item.archivePath }
                    newInputs.append(item)
                }
            }
        }

        // Preflight every replacement before opening output or consuming user edits.
        var replacementOptions: [String: CreateArchiveOptions] = [:]
        for original in existing where replacements[original.decodedPath] != nil {
            var preservedOptions = try ZipEntryStoragePolicy.options(for: original.record,
                path: original.decodedPath, reader: reader, accessor: accessor, base: options)
            preservedOptions.encoding = encoding
            replacementOptions[original.decodedPath] = preservedOptions
        }

        let sink = try ZipVolumeSink(outputURL: archiveURL, splitLimit: nil)
        do {
            var cdEntries: [CentralDirEntry] = []
            let totalCount = existing.count + newInputs.count
            var idx = 0

            for ex in existing {
                progress?(OperationProgress(
                    fractionCompleted: totalCount > 0 ? Double(idx) / Double(totalCount) : 0,
                    currentItem: ex.decodedPath
                ))
                if let replacement = replacements[ex.decodedPath], let entryOptions = replacementOptions[ex.decodedPath] {
                    let prepared = try prepareItem(replacement, options: entryOptions, allowCodecMT: true,
                        workerCount: options.workerCount, preserving: ex.record)
                    defer { prepared.cleanupTempIfNeeded() }
                    cdEntries.append(try writePreparedEntry(prepared, sink: sink))
                    idx += 1
                    continue
                }
                let originalPath = ZipReader.makeEntry(from: ex.record, encoding: encoding).path
                let pathEncoded = ex.decodedPath == originalPath
                    ? (data: ex.record.rawPathBytes, isUTF8: ex.record.flags & 0x0800 != 0)
                    : FilenameEncoding.encode(ex.decodedPath, option: .utf8)
                let entry = try copyRawRecord(
                    ex.record,
                    rawPathBytes: pathEncoded.data,
                    hasUTF8Flag: pathEncoded.isUTF8,
                    reader: reader,
                    accessor: accessor,
                    sink: sink
                )
                cdEntries.append(entry)
                idx += 1
            }

            if !newInputs.isEmpty {
                let baseCount = idx
                let newTotalBytes = newInputs.reduce(UInt64(0)) { $0 + $1.fileSize }
                let resolvedWorkers = BoltConcurrency.resolvedWorkerCount(override: options.workerCount)
                let maxWorkers = newInputs.filter { !$0.isDirectory }.count >= 2 ? resolvedWorkers : 1
                try ParallelExecutor.orderedMap(
                    newInputs,
                    maxWorkers: maxWorkers,
                    byteCost: { max(1, $0.fileSize) }
                ) { _, newItem in
                    try prepareItem(
                        newItem,
                        options: options,
                        allowCodecMT: maxWorkers == 1 && resolvedWorkers > 1,
                        workerCount: resolvedWorkers
                    )
                } consumeInOrder: { offsetIdx, newItem, prepared in
                    defer { prepared.cleanupTempIfNeeded() }
                    let overallIdx = baseCount + offsetIdx
                    progress?(OperationProgress(
                        fractionCompleted: totalCount > 0 ? Double(overallIdx) / Double(totalCount) : 0,
                        currentItem: newItem.archivePath,
                        processedBytes: 0,
                        totalBytes: newTotalBytes
                    ))
                    let entry = try writePreparedEntry(prepared, sink: sink)
                    cdEntries.append(entry)
                }
            }

            try finishCentralDirectory(entries: cdEntries, comment: resolvedComment, sink: sink)
            _ = try sink.finalizeAll()
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent))
        } catch {
            sink.abortCleanup()
            throw error
        }
    }

    // MARK: - Helpers

    private static func writeNewItems(
        _ items: [ArchiveInputItem],
        options: CreateArchiveOptions,
        sink: ZipVolumeSink,
        controller: ArchiveTaskController?,
        totalBytes: UInt64,
        cdEntries: inout [CentralDirEntry],
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws {
        let nonDirCount = items.reduce(0) { $0 + ($1.isDirectory ? 0 : 1) }
        let resolvedWorkers = BoltConcurrency.resolvedWorkerCount(override: options.workerCount)
        if nonDirCount <= 1 || resolvedWorkers <= 1 {
            let allowCodecMT = (nonDirCount <= 1) && (resolvedWorkers > 1)
            var processedBytes: UInt64 = 0
            for item in items {
                try controller?.checkpoint()
                progress?(OperationProgress(
                    fractionCompleted: totalBytes > 0 ? Double(processedBytes) / Double(totalBytes) : 0,
                    currentItem: item.archivePath,
                    processedBytes: processedBytes,
                    totalBytes: totalBytes
                ))
                let base = processedBytes
                let prepared = try prepareItem(
                    item,
                    options: options,
                    allowCodecMT: allowCodecMT,
                    workerCount: resolvedWorkers,
                    controller: controller
                ) { itemRead, _ in
                    let currentTotal = min(totalBytes, base + itemRead)
                    progress?(OperationProgress(
                        fractionCompleted: totalBytes > 0 ? Double(currentTotal) / Double(totalBytes) : 0,
                        currentItem: item.archivePath,
                        processedBytes: currentTotal,
                        totalBytes: totalBytes
                    ))
                }
                defer { prepared.cleanupTempIfNeeded() }
                let entry = try writePreparedEntry(prepared, controller: controller, sink: sink)
                cdEntries.append(entry)
                processedBytes += item.fileSize
            }
            return
        }

        let completedBytesLock = OSAllocatedUnfairLock(initialState: UInt64(0))
        try ParallelExecutor.orderedMap(
            items,
            maxWorkers: resolvedWorkers,
            byteCost: { max(1, $0.fileSize) },
            controller: controller
        ) { _, item in
            try prepareItem(
                item,
                options: options,
                allowCodecMT: false,
                workerCount: 1,
                controller: controller
            )
        } consumeInOrder: { _, item, prepared in
            defer { prepared.cleanupTempIfNeeded() }
            let entry = try writePreparedEntry(prepared, controller: controller, sink: sink)
            cdEntries.append(entry)
            let completedNow = completedBytesLock.withLock { total -> UInt64 in
                total = min(totalBytes, total + item.fileSize)
                return total
            }
            progress?(OperationProgress(
                fractionCompleted: totalBytes > 0 ? Double(completedNow) / Double(totalBytes) : 1.0,
                currentItem: item.archivePath,
                processedBytes: completedNow,
                totalBytes: totalBytes
            ))
        }
    }

    private static func writePreparedEntry(
        _ prepared: PreparedZipItem,
        controller: ArchiveTaskController? = nil,
        sink: ZipVolumeSink
    ) throws -> CentralDirEntry {
        try writeRawEntry(
            rawPathBytes: prepared.rawPathBytes,
            flags: prepared.flags,
            method: prepared.method,
            dosTime: prepared.dosTime,
            dosDate: prepared.dosDate,
            crc32: prepared.crc32,
            compressedSize: prepared.payload.compressedSize,
            uncompressedSize: prepared.uncompressedSize,
            externalAttrs: prepared.externalAttrs,
            extraWithoutZip64: prepared.extraWithoutZip64,
            commentData: prepared.commentData,
            sink: sink
        ) { outSink in
            switch prepared.payload {
            case .memory(let data):
                try outSink.writeData(data)
            case .file(let url, _, _):
                try outSink.writeFile(from: url, controller: controller)
            }
        }
    }

    private static func prepareItem(
        _ item: ArchiveInputItem,
        options: CreateArchiveOptions,
        allowCodecMT: Bool,
        workerCount: Int? = nil,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil,
        preserving original: ZipRecord? = nil
    ) throws -> PreparedZipItem {
        let pathEnc: (data: Data, isUTF8: Bool)
        if let original, ZipReader.makeEntry(from: original, encoding: options.encoding).path == item.archivePath {
            pathEnc = (original.rawPathBytes, original.flags & 0x0800 != 0)
        } else {
            pathEnc = FilenameEncoding.encode(item.archivePath, option: options.encoding)
        }
        let (dosTime, dosDate) = ZipBinary.dosDateTime(from: item.modifiedDate)
        let unixMode: UInt32
        if item.isSymbolicLink {
            unixMode = UInt32(0o120000 | (item.permissions & 0o0777))
        } else if item.isDirectory {
            unixMode = UInt32(0o040000 | item.permissions)
        } else {
            unixMode = UInt32(0o100000 | item.permissions)
        }
        let extAttrs = (unixMode << 16) | (item.isDirectory ? 0x10 : 0x00)

        var flags: UInt16 = pathEnc.isUTF8 ? 0x0800 : 0x0000

        // Directory entries have zero payload and are stored unencrypted
        if item.isDirectory {
            return PreparedZipItem(
                rawPathBytes: pathEnc.data,
                flags: flags,
                method: 0,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: 0,
                payload: .memory(Data()),
                uncompressedSize: 0,
                externalAttrs: extAttrs,
                extraWithoutZip64: buildExtendedTimestampExtra(date: item.modifiedDate),
                commentData: Data()
            )
        }

        // Symbolic links store their UTF-8 target path with mode 0o120000
        if item.isSymbolicLink {
            let targetData = Data((item.symlinkTarget ?? "").utf8)
            let crc = CompressionCodec.crc32(targetData)
            return PreparedZipItem(
                rawPathBytes: pathEnc.data,
                flags: flags,
                method: 0,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: crc,
                payload: .memory(targetData),
                uncompressedSize: UInt64(targetData.count),
                externalAttrs: extAttrs,
                extraWithoutZip64: buildExtendedTimestampExtra(date: item.modifiedDate),
                commentData: Data()
            )
        }

        // Large files exceeding streaming threshold bypass whole-file RAM buffers via temporary chunked files
        if let fileURL = item.fileURL, item.fileSize >= BoltConcurrency.streamingThresholdBytes {
            return try prepareStreamingFileItem(
                fileURL: fileURL,
                fileSize: item.fileSize,
                pathEnc: pathEnc,
                dosTime: dosTime,
                dosDate: dosDate,
                extAttrs: extAttrs,
                modifiedDate: item.modifiedDate,
                options: options,
                allowCodecMT: allowCodecMT,
                workerCount: workerCount,
                controller: controller,
                progress: progress,
                preserving: original
            )
        }

        let plainData: Data
        if let fileURL = item.fileURL {
            plainData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } else {
            plainData = Data()
        }

        let crc = CompressionCodec.crc32(plainData)
        var method = original.map { $0.aesExtra?.actualMethod ?? $0.compressionMethod } ?? options.algorithm.zipMethodCode
        var compressed = try CompressionCodec.compress(
            data: plainData,
            algorithm: options.algorithm,
            gzipContainer: false,
            level: options.level,
            allowMultiThread: allowCodecMT,
            workerCount: allowCodecMT ? workerCount : 1,
            controller: controller,
            progress: progress
        )
        // Store fallback if DEFLATE/Bzip2/Zstd expanded a tiny/incompressible file
        if original == nil && options.algorithm != .store && compressed.count >= plainData.count && plainData.count < 64 {
            method = 0
            compressed = plainData
        }

        var extra = original.map { preservedEntryExtra($0.extraData) } ?? Data()
        extra.append(buildExtendedTimestampExtra(date: item.modifiedDate))
        var finalPayload = compressed
        var headerCRC = crc
        var headerMethod = method

        if options.encryption != .none, let password = options.password, !password.isEmpty {
            flags |= 0x0001
            switch options.encryption {
            case .aes256:
                finalPayload = try ZipCrypto.encryptAES256(plaintext: compressed, password: password)
                headerMethod = 99
                let vendor = original?.aesExtra?.vendorVersion ?? 2
                headerCRC = vendor == 2 ? 0 : crc
                extra.append(buildWinZipAESExtra(actualMethod: method, vendorVersion: vendor))
            case .zipCrypto:
                finalPayload = try ZipCrypto.encryptZipCrypto(plaintext: compressed, crc32: crc, password: password)
            case .none:
                break
            }
        }

        return PreparedZipItem(
            rawPathBytes: pathEnc.data,
            flags: flags,
            method: headerMethod,
            dosTime: dosTime,
            dosDate: dosDate,
            crc32: headerCRC,
            payload: .memory(finalPayload),
            uncompressedSize: UInt64(plainData.count),
            externalAttrs: preservedExternalAttributes(original, fallback: extAttrs),
            extraWithoutZip64: extra,
            commentData: original?.commentData ?? Data()
        )
    }

    private static func prepareStreamingFileItem(
        fileURL: URL,
        fileSize: UInt64,
        pathEnc: (data: Data, isUTF8: Bool),
        dosTime: UInt16,
        dosDate: UInt16,
        extAttrs: UInt32,
        modifiedDate: Date,
        options: CreateArchiveOptions,
        allowCodecMT: Bool,
        workerCount: Int?,
        controller: ArchiveTaskController?,
        progress: ((UInt64, UInt64) -> Void)?,
        preserving original: ZipRecord? = nil
    ) throws -> PreparedZipItem {
        let fm = FileManager.default
        let isEncrypted = options.encryption != .none && !(options.password ?? "").isEmpty
        let vendor = original?.aesExtra?.vendorVersion ?? 2
        let needsHeaderCRC = !(isEncrypted && options.encryption == .aes256 && vendor == 2)
        let crc = needsHeaderCRC ? try CompressionCodec.crc32File(at: fileURL, controller: controller) : 0

        let method = original.map { $0.aesExtra?.actualMethod ?? $0.compressionMethod } ?? options.algorithm.zipMethodCode
        let compURL: URL
        let compSize: UInt64
        let deleteCompAfter: Bool

        if options.algorithm == .store {
            compURL = fileURL
            compSize = fileSize
            deleteCompAfter = false
        } else {
            compURL = fm.temporaryDirectory.appendingPathComponent("boltzip-stream-c-\(UUID().uuidString).tmp")
            do {
                try CompressionCodec.compressFile(
                    sourceURL: fileURL,
                    destinationURL: compURL,
                    algorithm: options.algorithm,
                    gzipContainer: false,
                    level: options.level,
                    allowMultiThread: allowCodecMT,
                    workerCount: allowCodecMT ? workerCount : 1,
                    controller: controller,
                    progress: progress
                )
                let attrs = try fm.attributesOfItem(atPath: compURL.path)
                compSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                deleteCompAfter = true
            } catch {
                try? fm.removeItem(at: compURL)
                throw error
            }
        }

        var flags: UInt16 = pathEnc.isUTF8 ? 0x0800 : 0x0000
        var extra = original.map { preservedEntryExtra($0.extraData) } ?? Data()
        extra.append(buildExtendedTimestampExtra(date: modifiedDate))
        var headerCRC = crc
        var headerMethod = method
        var payload: PreparedPayload = .file(url: compURL, size: compSize, deleteAfterWrite: deleteCompAfter)

        if isEncrypted, let password = options.password, !password.isEmpty {
            flags |= 0x0001
            let encURL = fm.temporaryDirectory.appendingPathComponent("boltzip-stream-e-\(UUID().uuidString).tmp")
            do {
                switch options.encryption {
                case .aes256:
                    try ZipCrypto.encryptAES256Stream(from: compURL, to: encURL, password: password, controller: controller)
                    headerMethod = 99
                    headerCRC = vendor == 2 ? 0 : crc
                    extra.append(buildWinZipAESExtra(actualMethod: method, vendorVersion: vendor))
                case .zipCrypto:
                    try ZipCrypto.encryptZipCryptoStream(from: compURL, to: encURL, crc32: crc, password: password, controller: controller)
                case .none:
                    break
                }
                if deleteCompAfter {
                    try? fm.removeItem(at: compURL)
                }
                let attrs = try fm.attributesOfItem(atPath: encURL.path)
                let encSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                payload = .file(url: encURL, size: encSize, deleteAfterWrite: true)
            } catch {
                try? fm.removeItem(at: encURL)
                if deleteCompAfter {
                    try? fm.removeItem(at: compURL)
                }
                throw error
            }
        }

        return PreparedZipItem(
            rawPathBytes: pathEnc.data,
            flags: flags,
            method: headerMethod,
            dosTime: dosTime,
            dosDate: dosDate,
            crc32: headerCRC,
            payload: payload,
            uncompressedSize: fileSize,
            externalAttrs: preservedExternalAttributes(original, fallback: extAttrs),
            extraWithoutZip64: extra,
            commentData: original?.commentData ?? Data()
        )
    }

    static func copyRawRecord(
        _ record: ZipRecord,
        rawPathBytes: Data,
        hasUTF8Flag: Bool,
        reader: ZipReader,
        accessor: ZipVolumeAccessor,
        sink: ZipVolumeSink
    ) throws -> CentralDirEntry {
        let flags = record.flags | (hasUTF8Flag ? 0x0800 : 0)
        // Preserve bit 3 for untouched legacy ZipCrypto entries encrypted with the data-descriptor header byte
        // so 7-Zip/WinRAR continue validating (dosTime >> 8) properly; emit a compliant Data Descriptor below.
        let isLegacyDataDescCrypto = (record.flags & 0x0001 != 0)
            && (record.compressionMethod != 99)
            && (record.flags & 0x0008 != 0)
        let cleanFlags = isLegacyDataDescCrypto ? flags : (flags & ~UInt16(0x0008))

        return try writeRawEntry(
            rawPathBytes: rawPathBytes,
            flags: cleanFlags,
            method: record.compressionMethod,
            dosTime: record.dosTime,
            dosDate: record.dosDate,
            crc32: record.crc32,
            compressedSize: record.compressedSize,
            uncompressedSize: record.uncompressedSize,
            externalAttrs: record.externalAttributes,
            extraWithoutZip64: stripZip64Extra(record.extraData),
            commentData: record.commentData,
            emitDataDescriptor: isLegacyDataDescCrypto,
            sink: sink
        ) { outSink in
            if record.compressedSize < BoltConcurrency.streamingThresholdBytes {
                let rawPayload = try reader.readRawPayload(for: record, accessor: accessor)
                try outSink.writeData(rawPayload)
            } else {
                try reader.streamRawPayload(for: record, accessor: accessor) { chunk in
                    try outSink.writeData(chunk)
                }
            }
        }
    }

    static func writeRawEntry(
        rawPathBytes: Data,
        flags: UInt16,
        method: UInt16,
        dosTime: UInt16,
        dosDate: UInt16,
        crc32: UInt32,
        compressedSize compSize: UInt64,
        uncompressedSize: UInt64,
        externalAttrs: UInt32,
        extraWithoutZip64: Data,
        commentData: Data,
        emitDataDescriptor: Bool = false,
        sink: ZipVolumeSink,
        writePayloadBody: (ZipVolumeSink) throws -> Void
    ) throws -> CentralDirEntry {
        try sink.ensureRoomBeforeHeader()
        let localDisk = UInt32(sink.currentDisk)
        let localOffset = sink.currentOffset

        let needsZip64Sizes = compSize >= 0xFFFFFFFF || uncompressedSize >= 0xFFFFFFFF
        let needsZip64Offset = localOffset >= 0xFFFFFFFF
        let needsZip64Disk = localDisk >= 0xFFFF

        var localExtra = extraWithoutZip64
        if needsZip64Sizes && !emitDataDescriptor {
            var z64 = Data()
            ZipBinary.appendUInt64LE(&z64, uncompressedSize)
            ZipBinary.appendUInt64LE(&z64, compSize)
            ZipBinary.appendUInt16LE(&localExtra, ZipExtraTag.zip64)
            ZipBinary.appendUInt16LE(&localExtra, UInt16(z64.count))
            localExtra.append(z64)
        }

        var cdExtra = extraWithoutZip64
        if needsZip64Sizes || needsZip64Offset || needsZip64Disk {
            var z64 = Data()
            if uncompressedSize >= 0xFFFFFFFF { ZipBinary.appendUInt64LE(&z64, uncompressedSize) }
            if compSize >= 0xFFFFFFFF { ZipBinary.appendUInt64LE(&z64, compSize) }
            if localOffset >= 0xFFFFFFFF { ZipBinary.appendUInt64LE(&z64, localOffset) }
            if localDisk >= 0xFFFF { ZipBinary.appendUInt32LE(&z64, localDisk) }
            ZipBinary.appendUInt16LE(&cdExtra, ZipExtraTag.zip64)
            ZipBinary.appendUInt16LE(&cdExtra, UInt16(z64.count))
            cdExtra.append(z64)
        }

        let versionNeeded: UInt16 = (method == 99) ? 51 : (needsZip64Sizes || needsZip64Offset ? 45 : 20)

        var lh = Data(capacity: 30 + rawPathBytes.count + localExtra.count)
        ZipBinary.appendUInt32LE(&lh, ZipSignature.localFileHeader)
        ZipBinary.appendUInt16LE(&lh, versionNeeded)
        ZipBinary.appendUInt16LE(&lh, flags)
        ZipBinary.appendUInt16LE(&lh, method)
        ZipBinary.appendUInt16LE(&lh, dosTime)
        ZipBinary.appendUInt16LE(&lh, dosDate)
        if emitDataDescriptor {
            ZipBinary.appendUInt32LE(&lh, 0)
            ZipBinary.appendUInt32LE(&lh, 0)
            ZipBinary.appendUInt32LE(&lh, 0)
        } else {
            ZipBinary.appendUInt32LE(&lh, crc32)
            ZipBinary.appendUInt32LE(&lh, compSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(compSize))
            ZipBinary.appendUInt32LE(&lh, uncompressedSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(uncompressedSize))
        }
        ZipBinary.appendUInt16LE(&lh, UInt16(rawPathBytes.count))
        ZipBinary.appendUInt16LE(&lh, UInt16(localExtra.count))
        lh.append(rawPathBytes)
        lh.append(localExtra)

        try sink.writeData(lh)
        try writePayloadBody(sink)

        if emitDataDescriptor {
            var dd = Data(capacity: needsZip64Sizes ? 24 : 16)
            ZipBinary.appendUInt32LE(&dd, ZipSignature.dataDescriptor)
            ZipBinary.appendUInt32LE(&dd, crc32)
            if needsZip64Sizes {
                ZipBinary.appendUInt64LE(&dd, compSize)
                ZipBinary.appendUInt64LE(&dd, uncompressedSize)
            } else {
                ZipBinary.appendUInt32LE(&dd, UInt32(compSize))
                ZipBinary.appendUInt32LE(&dd, UInt32(uncompressedSize))
            }
            try sink.writeData(dd)
        }

        return CentralDirEntry(
            rawPathBytes: rawPathBytes,
            flags: flags,
            method: method,
            dosTime: dosTime,
            dosDate: dosDate,
            crc32: crc32,
            compressedSize: compSize,
            uncompressedSize: uncompressedSize,
            diskStart: localDisk,
            localOffset: localOffset,
            externalAttrs: externalAttrs,
            cdExtra: cdExtra,
            commentData: commentData
        )
    }

    static func finishCentralDirectory(
        entries: [CentralDirEntry],
        comment: String,
        sink: ZipVolumeSink
    ) throws {
        try sink.ensureRoomBeforeHeader()
        let cdStartDisk = UInt32(sink.currentDisk)
        let cdStartOffset = sink.currentOffset

        var cdBuffer = Data()
        var entriesOnStartDisk: UInt64 = 0

        for e in entries {
            let needsZip64 = e.compressedSize >= 0xFFFFFFFF || e.uncompressedSize >= 0xFFFFFFFF || e.localOffset >= 0xFFFFFFFF || e.diskStart >= 0xFFFF
            let versionNeeded: UInt16 = (e.method == 99) ? 51 : (needsZip64 ? 45 : 20)

            ZipBinary.appendUInt32LE(&cdBuffer, ZipSignature.centralDirectoryHeader)
            ZipBinary.appendUInt16LE(&cdBuffer, 0x031E) // Unix creator, ZIP 3.0
            ZipBinary.appendUInt16LE(&cdBuffer, versionNeeded)
            ZipBinary.appendUInt16LE(&cdBuffer, e.flags)
            ZipBinary.appendUInt16LE(&cdBuffer, e.method)
            ZipBinary.appendUInt16LE(&cdBuffer, e.dosTime)
            ZipBinary.appendUInt16LE(&cdBuffer, e.dosDate)
            ZipBinary.appendUInt32LE(&cdBuffer, e.crc32)
            ZipBinary.appendUInt32LE(&cdBuffer, e.compressedSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(e.compressedSize))
            ZipBinary.appendUInt32LE(&cdBuffer, e.uncompressedSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(e.uncompressedSize))
            ZipBinary.appendUInt16LE(&cdBuffer, UInt16(e.rawPathBytes.count))
            ZipBinary.appendUInt16LE(&cdBuffer, UInt16(e.cdExtra.count))
            ZipBinary.appendUInt16LE(&cdBuffer, UInt16(e.commentData.count))
            ZipBinary.appendUInt16LE(&cdBuffer, e.diskStart >= 0xFFFF ? 0xFFFF : UInt16(e.diskStart))
            ZipBinary.appendUInt16LE(&cdBuffer, 0)
            ZipBinary.appendUInt32LE(&cdBuffer, e.externalAttrs)
            ZipBinary.appendUInt32LE(&cdBuffer, e.localOffset >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(e.localOffset))
            cdBuffer.append(e.rawPathBytes)
            cdBuffer.append(e.cdExtra)
            cdBuffer.append(e.commentData)
            if e.diskStart == cdStartDisk {
                entriesOnStartDisk += 1
            }
        }

        try sink.writeData(cdBuffer)

        let totalEntries = UInt64(entries.count)
        let cdSize = UInt64(cdBuffer.count)
        let lastDisk = UInt32(sink.currentDisk)

        let needsZip64EOCD = totalEntries >= 0xFFFF
            || cdSize >= 0xFFFFFFFF
            || cdStartOffset >= 0xFFFFFFFF
            || cdStartDisk >= 0xFFFF
            || lastDisk >= 0xFFFF

        if needsZip64EOCD {
            try sink.ensureRoomBeforeHeader()
            let z64Disk = UInt32(sink.currentDisk)
            let z64Offset = sink.currentOffset

            var z64 = Data()
            ZipBinary.appendUInt32LE(&z64, ZipSignature.zip64EOCD)
            ZipBinary.appendUInt64LE(&z64, 44) // Remaining size after field
            ZipBinary.appendUInt16LE(&z64, 0x032D)
            ZipBinary.appendUInt16LE(&z64, 45)
            ZipBinary.appendUInt32LE(&z64, lastDisk)
            ZipBinary.appendUInt32LE(&z64, cdStartDisk)
            ZipBinary.appendUInt64LE(&z64, entriesOnStartDisk)
            ZipBinary.appendUInt64LE(&z64, totalEntries)
            ZipBinary.appendUInt64LE(&z64, cdSize)
            ZipBinary.appendUInt64LE(&z64, cdStartOffset)

            // ZIP64 EOCD Locator
            ZipBinary.appendUInt32LE(&z64, ZipSignature.zip64Locator)
            ZipBinary.appendUInt32LE(&z64, z64Disk)
            ZipBinary.appendUInt64LE(&z64, z64Offset)
            ZipBinary.appendUInt32LE(&z64, lastDisk + 1)

            try sink.writeData(z64)
        }

        let commentData = Data(comment.utf8).prefix(65535)
        var eocd = Data()
        ZipBinary.appendUInt32LE(&eocd, ZipSignature.endOfCentralDirectory)
        ZipBinary.appendUInt16LE(&eocd, lastDisk >= 0xFFFF ? 0xFFFF : UInt16(lastDisk))
        ZipBinary.appendUInt16LE(&eocd, cdStartDisk >= 0xFFFF ? 0xFFFF : UInt16(cdStartDisk))
        ZipBinary.appendUInt16LE(&eocd, entriesOnStartDisk >= 0xFFFF ? 0xFFFF : UInt16(entriesOnStartDisk))
        ZipBinary.appendUInt16LE(&eocd, totalEntries >= 0xFFFF ? 0xFFFF : UInt16(totalEntries))
        ZipBinary.appendUInt32LE(&eocd, cdSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(cdSize))
        ZipBinary.appendUInt32LE(&eocd, cdStartOffset >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(cdStartOffset))
        ZipBinary.appendUInt16LE(&eocd, UInt16(commentData.count))
        eocd.append(commentData)

        try sink.writeData(eocd)
    }

    private static func buildExtendedTimestampExtra(date: Date) -> Data {
        var extra = Data()
        let unixSec = UInt32(bitPattern: Int32(clamping: Int(date.timeIntervalSince1970)))
        ZipBinary.appendUInt16LE(&extra, ZipExtraTag.extendedTimestamp)
        ZipBinary.appendUInt16LE(&extra, 5)
        extra.append(0x01)
        ZipBinary.appendUInt32LE(&extra, unixSec)
        return extra
    }

    private static func buildWinZipAESExtra(actualMethod: UInt16, vendorVersion: UInt16 = 2) -> Data {
        var extra = Data()
        ZipBinary.appendUInt16LE(&extra, ZipExtraTag.winZipAES)
        ZipBinary.appendUInt16LE(&extra, 7)
        ZipBinary.appendUInt16LE(&extra, vendorVersion)
        extra.append(0x41) // 'A'
        extra.append(0x45) // 'E'
        extra.append(ZipCrypto.AESStrength.aes256.rawValue)
        ZipBinary.appendUInt16LE(&extra, actualMethod)
        return extra
    }

    private static func preservedExternalAttributes(_ record: ZipRecord?, fallback: UInt32) -> UInt32 {
        guard let record else { return fallback }
        let typeMask: UInt32 = 0o170000 << 16
        // Replacing a symlink with a regular file must also change its Unix file type.
        guard record.externalAttributes & typeMask == fallback & typeMask else { return fallback }
        return record.externalAttributes
    }

    private static func preservedEntryExtra(_ data: Data) -> Data {
        var output = Data()
        var offset = 0
        let regenerated: Set<UInt16> = [ZipExtraTag.zip64, ZipExtraTag.extendedTimestamp, ZipExtraTag.winZipAES, ZipExtraTag.infoZipUnicodePath]
        while offset + 4 <= data.count {
            let tag = ZipBinary.readUInt16LE(data, at: offset)
            let length = Int(ZipBinary.readUInt16LE(data, at: offset + 2))
            guard offset + 4 + length <= data.count else { break }
            if !regenerated.contains(tag) { output.append(data.subdata(in: offset..<(offset + 4 + length))) }
            offset += 4 + length
        }
        return output
    }

    static func stripZip64Extra(_ extra: Data) -> Data {
        var cleaned = Data()
        var pos = 0
        while pos + 4 <= extra.count {
            let tag = ZipBinary.readUInt16LE(extra, at: pos)
            let size = Int(ZipBinary.readUInt16LE(extra, at: pos + 2))
            guard pos + 4 + size <= extra.count else { break }
            if tag != ZipExtraTag.zip64 {
                cleaned.append(extra.subdata(in: pos..<(pos + 4 + size)))
            }
            pos += 4 + size
        }
        return cleaned
    }
}
