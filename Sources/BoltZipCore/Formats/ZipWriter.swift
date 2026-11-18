import Foundation
import os

public enum ZipEditOperation: Sendable {
    case addItems(urls: [URL], targetFolder: String)
    case createFolder(path: String)
    case deletePaths(Set<String>)
    case renamePath(oldPath: String, newPath: String)
}

private final class SplitVolumeSink {
    let baseURL: URL
    let splitLimit: UInt64?
    private(set) var currentDisk: Int = 0
    private(set) var currentOffset: UInt64 = 0
    private var currentHandle: FileHandle?
    private(set) var createdFiles: [URL] = []
    private let tempPrefix: String

    init(outputURL: URL, splitLimit: UInt64?) throws {
        self.baseURL = outputURL
        self.splitLimit = (splitLimit ?? 0) >= 65536 ? splitLimit : nil
        self.tempPrefix = ".\(outputURL.lastPathComponent).boltzip.tmp.\(UUID().uuidString)"
        try openDisk(0)
        if self.splitLimit != nil {
            // Standard PKWARE split archive signature 0x08074B50 at start of disk 0
            var sig = Data()
            ZipBinary.appendUInt32LE(&sig, ZipSignature.dataDescriptor)
            try writeData(sig)
        }
    }

    private func tempURL(forDisk disk: Int) -> URL {
        let dir = baseURL.deletingLastPathComponent()
        return dir.appendingPathComponent("\(tempPrefix).part\(disk)")
    }

    private func finalURL(forDisk disk: Int, totalDisks: Int) -> URL {
        if disk == totalDisks - 1 {
            return baseURL
        }
        let stem = baseURL.deletingPathExtension()
        return stem.appendingPathExtension(String(format: "z%02d", disk + 1))
    }

    private func openDisk(_ disk: Int) throws {
        if let fh = currentHandle {
            try fh.close()
        }
        let url = tempURL(forDisk: disk)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fh = try FileHandle(forWritingTo: url)
        currentHandle = fh
        currentDisk = disk
        currentOffset = 0
        createdFiles.append(url)
    }

    func ensureRoomBeforeHeader() throws {
        if let limit = splitLimit, currentOffset >= limit {
            try openDisk(currentDisk + 1)
        }
    }

    func writeData(_ data: Data) throws {
        guard !data.isEmpty else { return }
        guard let limit = splitLimit else {
            try currentHandle?.write(contentsOf: data)
            currentOffset += UInt64(data.count)
            return
        }

        var pos = 0
        while pos < data.count {
            if currentOffset >= limit {
                try openDisk(currentDisk + 1)
            }
            let room = Int(limit - currentOffset)
            let chunkLen = min(room, data.count - pos)
            let sub = data.subdata(in: pos..<(pos + chunkLen))
            try currentHandle?.write(contentsOf: sub)
            currentOffset += UInt64(chunkLen)
            pos += chunkLen
        }
    }

    func finalizeAll() throws -> [URL] {
        try currentHandle?.close()
        currentHandle = nil

        let totalDisks = createdFiles.count
        var finalURLs: [URL] = []
        let fm = FileManager.default
        for (idx, tmp) in createdFiles.enumerated() {
            let dest = finalURL(forDisk: idx, totalDisks: totalDisks)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: tmp, to: dest)
            finalURLs.append(dest)
        }
        createdFiles.removeAll()
        return finalURLs
    }

    func abortCleanup() {
        try? currentHandle?.close()
        currentHandle = nil
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdFiles.removeAll()
    }
}

public enum ZipWriter {
    struct InputItem: Sendable {
        let archivePath: String
        let fileURL: URL? // nil if synthetic directory
        let isDirectory: Bool
        let modifiedDate: Date
        let permissions: UInt16
        let fileSize: UInt64
    }

    private struct PreparedZipItem: Sendable {
        let rawPathBytes: Data
        let flags: UInt16
        let method: UInt16
        let dosTime: UInt16
        let dosDate: UInt16
        let crc32: UInt32
        let compressedPayload: Data
        let uncompressedSize: UInt64
        let externalAttrs: UInt32
        let extraWithoutZip64: Data
        let commentData: Data
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
        let items = try collectInputItems(from: inputURLs, excludeMacJunk: options.excludeMacJunk)
        let sink = try SplitVolumeSink(outputURL: outputURL, splitLimit: options.splitVolumeSizeBytes)
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
        let ext = archiveURL.pathExtension.lowercased()
        if parsed.totalDisks > 1 || ext != "zip" {
            throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t(
                "分卷 ZIP 归档不支持包内原地编辑，请先解压或另存为单文件 ZIP",
                "分卷 ZIP 封存檔不支援封存檔內原地編輯，請先解壓或另存為單一 ZIP",
                "In-place editing is not supported for split-volume ZIP archives",
                "分割 ZIP 書庫の直接編集には対応していません"
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
            }
        }

        // Collect new files to add
        var newInputs: [InputItem] = []
        for folder in foldersToCreate {
            if !existing.contains(where: { $0.decodedPath == folder }) {
                newInputs.append(InputItem(
                    archivePath: folder,
                    fileURL: nil,
                    isDirectory: true,
                    modifiedDate: Date(),
                    permissions: 0o755,
                    fileSize: 0
                ))
            }
        }
        for pair in itemsToAdd {
            let collected = try collectInputItems(from: [pair.url], excludeMacJunk: options.excludeMacJunk)
            for var item in collected {
                let prefixed = pair.targetFolder.isEmpty ? item.archivePath : (pair.targetFolder + item.archivePath)
                item = InputItem(
                    archivePath: prefixed,
                    fileURL: item.fileURL,
                    isDirectory: item.isDirectory,
                    modifiedDate: item.modifiedDate,
                    permissions: item.permissions,
                    fileSize: item.fileSize
                )
                // Replace same-path existing entry like Windows Zip
                existing.removeAll { $0.decodedPath == item.archivePath }
                newInputs.append(item)
            }
        }

        let sink = try SplitVolumeSink(outputURL: archiveURL, splitLimit: nil)
        do {
            var cdEntries: [CentralDirEntry] = []
            let totalCount = existing.count + newInputs.count
            var idx = 0

            for ex in existing {
                progress?(OperationProgress(
                    fractionCompleted: totalCount > 0 ? Double(idx) / Double(totalCount) : 0,
                    currentItem: ex.decodedPath
                ))
                let rawPayload = try reader.readRawPayload(for: ex.record, accessor: accessor)
                let pathEncoded = FilenameEncoding.encode(ex.decodedPath, option: .utf8)
                let flags = ex.record.flags | (pathEncoded.isUTF8 ? 0x0800 : 0)
                // Remove old bit 3 data descriptor flag since we know compressedSize & crc32
                let cleanFlags = flags & ~UInt16(0x0008)

                let entry = try writeRawEntry(
                    rawPathBytes: pathEncoded.data,
                    flags: cleanFlags,
                    method: ex.record.compressionMethod,
                    dosTime: ex.record.dosTime,
                    dosDate: ex.record.dosDate,
                    crc32: ex.record.crc32,
                    compressedPayload: rawPayload,
                    uncompressedSize: ex.record.uncompressedSize,
                    externalAttrs: ex.record.externalAttributes,
                    extraWithoutZip64: stripZip64Extra(ex.record.extraData),
                    commentData: ex.record.commentData,
                    sink: sink
                )
                cdEntries.append(entry)
                idx += 1
            }

            if !newInputs.isEmpty {
                let baseCount = idx
                let newTotalBytes = newInputs.reduce(UInt64(0)) { $0 + $1.fileSize }
                let maxWorkers = newInputs.filter { !$0.isDirectory }.count >= 2 ? ParallelExecutor.defaultWorkerCount : 1
                try ParallelExecutor.orderedMap(
                    newInputs,
                    maxWorkers: maxWorkers,
                    byteCost: { $0.fileSize }
                ) { _, newItem in
                    try prepareItem(newItem, options: options, allowCodecMT: maxWorkers == 1)
                } consumeInOrder: { offsetIdx, newItem, prepared in
                    let overallIdx = baseCount + offsetIdx
                    progress?(OperationProgress(
                        fractionCompleted: totalCount > 0 ? Double(overallIdx) / Double(totalCount) : 0,
                        currentItem: newItem.archivePath,
                        processedBytes: 0,
                        totalBytes: newTotalBytes
                    ))
                    let entry = try writeRawEntry(
                        rawPathBytes: prepared.rawPathBytes,
                        flags: prepared.flags,
                        method: prepared.method,
                        dosTime: prepared.dosTime,
                        dosDate: prepared.dosDate,
                        crc32: prepared.crc32,
                        compressedPayload: prepared.compressedPayload,
                        uncompressedSize: prepared.uncompressedSize,
                        externalAttrs: prepared.externalAttrs,
                        extraWithoutZip64: prepared.extraWithoutZip64,
                        commentData: prepared.commentData,
                        sink: sink
                    )
                    cdEntries.append(entry)
                }
            }

            try finishCentralDirectory(entries: cdEntries, comment: parsed.comment, sink: sink)
            _ = try sink.finalizeAll()
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent))
        } catch {
            sink.abortCleanup()
            throw error
        }
    }

    // MARK: - Helpers

    static func collectInputItems(from inputURLs: [URL], excludeMacJunk: Bool) throws -> [InputItem] {
        let fm = FileManager.default
        var items: [InputItem] = []

        for rootURL in inputURLs {
            var isDirObj: ObjCBool = false
            guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDirObj) else {
                throw BoltZipError.ioError(BoltCoreLocalization.t(
                    "找不到文件或文件夹：\(rootURL.path)",
                    "找不到檔案或資料夾：\(rootURL.path)",
                    "File or folder not found: \(rootURL.path)",
                    "ファイルまたはフォルダが見つかりません: \(rootURL.path)"
                ))
            }

            let rootName = rootURL.lastPathComponent
            if excludeMacJunk && MacJunkFilter.isJunk(path: rootName) {
                continue
            }

            let rootAttrs = try fm.attributesOfItem(atPath: rootURL.path)
            let rootMod = (rootAttrs[.modificationDate] as? Date) ?? Date()
            let rootPerms = UInt16((rootAttrs[.posixPermissions] as? NSNumber)?.uint16Value ?? (isDirObj.boolValue ? 0o755 : 0o644))

            if !isDirObj.boolValue {
                let sz = (rootAttrs[.size] as? NSNumber)?.uint64Value ?? 0
                items.append(InputItem(
                    archivePath: rootName,
                    fileURL: rootURL,
                    isDirectory: false,
                    modifiedDate: rootMod,
                    permissions: rootPerms,
                    fileSize: sz
                ))
                continue
            }

            // Directory entry itself
            items.append(InputItem(
                archivePath: rootName + "/",
                fileURL: nil,
                isDirectory: true,
                modifiedDate: rootMod,
                permissions: rootPerms,
                fileSize: 0
            ))

            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            let basePath = rootURL.standardizedFileURL.path
            for case let childURL as URL in enumerator {
                let childStd = childURL.standardizedFileURL.path
                let rel = String(childStd.dropFirst(basePath.count + (basePath.hasSuffix("/") ? 0 : 1)))
                let archiveRel = "\(rootName)/\(rel)"

                if excludeMacJunk && MacJunkFilter.isJunk(path: archiveRel) {
                    if (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                let rv = try childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                if rv.isSymbolicLink == true { continue }
                let isSubDir = rv.isDirectory == true
                let attrs = try? fm.attributesOfItem(atPath: childURL.path)
                let perms = UInt16((attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? (isSubDir ? 0o755 : 0o644))
                let mod = rv.contentModificationDate ?? Date()
                let sz = isSubDir ? 0 : UInt64(rv.fileSize ?? 0)

                items.append(InputItem(
                    archivePath: isSubDir ? (archiveRel + "/") : archiveRel,
                    fileURL: isSubDir ? nil : childURL,
                    isDirectory: isSubDir,
                    modifiedDate: mod,
                    permissions: perms,
                    fileSize: sz
                ))
            }
        }
        return items
    }

    private static func writeNewItems(
        _ items: [InputItem],
        options: CreateArchiveOptions,
        sink: SplitVolumeSink,
        controller: ArchiveTaskController?,
        totalBytes: UInt64,
        cdEntries: inout [CentralDirEntry],
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws {
        let nonDirCount = items.reduce(0) { $0 + ($1.isDirectory ? 0 : 1) }
        if nonDirCount <= 1 {
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
                    allowCodecMT: true,
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
                let entry = try writeRawEntry(
                    rawPathBytes: prepared.rawPathBytes,
                    flags: prepared.flags,
                    method: prepared.method,
                    dosTime: prepared.dosTime,
                    dosDate: prepared.dosDate,
                    crc32: prepared.crc32,
                    compressedPayload: prepared.compressedPayload,
                    uncompressedSize: prepared.uncompressedSize,
                    externalAttrs: prepared.externalAttrs,
                    extraWithoutZip64: prepared.extraWithoutZip64,
                    commentData: prepared.commentData,
                    sink: sink
                )
                cdEntries.append(entry)
                processedBytes += item.fileSize
            }
            return
        }

        let completedBytesLock = OSAllocatedUnfairLock(initialState: UInt64(0))
        try ParallelExecutor.orderedMap(
            items,
            maxWorkers: ParallelExecutor.defaultWorkerCount,
            byteCost: { max(1, $0.fileSize) },
            controller: controller
        ) { _, item in
            let prepared = try prepareItem(
                item,
                options: options,
                allowCodecMT: false,
                controller: controller
            )
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
            return prepared
        } consumeInOrder: { _, _, prepared in
            let entry = try writeRawEntry(
                rawPathBytes: prepared.rawPathBytes,
                flags: prepared.flags,
                method: prepared.method,
                dosTime: prepared.dosTime,
                dosDate: prepared.dosDate,
                crc32: prepared.crc32,
                compressedPayload: prepared.compressedPayload,
                uncompressedSize: prepared.uncompressedSize,
                externalAttrs: prepared.externalAttrs,
                extraWithoutZip64: prepared.extraWithoutZip64,
                commentData: prepared.commentData,
                sink: sink
            )
            cdEntries.append(entry)
        }
    }

    private static func prepareItem(
        _ item: InputItem,
        options: CreateArchiveOptions,
        allowCodecMT: Bool,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> PreparedZipItem {
        let pathEnc = FilenameEncoding.encode(item.archivePath, option: options.encoding)
        let (dosTime, dosDate) = ZipBinary.dosDateTime(from: item.modifiedDate)
        let unixMode = UInt32(item.isDirectory ? (0o040000 | item.permissions) : (0o100000 | item.permissions))
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
                compressedPayload: Data(),
                uncompressedSize: 0,
                externalAttrs: extAttrs,
                extraWithoutZip64: buildExtendedTimestampExtra(date: item.modifiedDate),
                commentData: Data()
            )
        }

        let plainData: Data
        if let fileURL = item.fileURL {
            plainData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } else {
            plainData = Data()
        }

        let crc = CompressionCodec.crc32(plainData)
        var method = options.algorithm.zipMethodCode
        var compressed = try CompressionCodec.compress(
            data: plainData,
            algorithm: options.algorithm,
            gzipContainer: false,
            level: options.level,
            allowMultiThread: allowCodecMT,
            controller: controller,
            progress: progress
        )
        // Store fallback if DEFLATE/Bzip2/Zstd expanded a tiny/incompressible file
        if options.algorithm != .store && compressed.count >= plainData.count && plainData.count < 64 {
            method = 0
            compressed = plainData
        }

        var extra = buildExtendedTimestampExtra(date: item.modifiedDate)
        var finalPayload = compressed
        var headerCRC = crc
        var headerMethod = method

        if options.encryption != .none, let password = options.password, !password.isEmpty {
            flags |= 0x0001
            switch options.encryption {
            case .aes256:
                finalPayload = try ZipCrypto.encryptAES256(plaintext: compressed, password: password)
                headerMethod = 99
                headerCRC = 0 // AE-2 spec zeroes CRC32 and relies on HMAC-SHA1
                extra.append(buildWinZipAESExtra(actualMethod: method))
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
            compressedPayload: finalPayload,
            uncompressedSize: UInt64(plainData.count),
            externalAttrs: extAttrs,
            extraWithoutZip64: extra,
            commentData: Data()
        )
    }

    private static func writeRawEntry(
        rawPathBytes: Data,
        flags: UInt16,
        method: UInt16,
        dosTime: UInt16,
        dosDate: UInt16,
        crc32: UInt32,
        compressedPayload: Data,
        uncompressedSize: UInt64,
        externalAttrs: UInt32,
        extraWithoutZip64: Data,
        commentData: Data,
        sink: SplitVolumeSink
    ) throws -> CentralDirEntry {
        try sink.ensureRoomBeforeHeader()
        let localDisk = UInt32(sink.currentDisk)
        let localOffset = sink.currentOffset
        let compSize = UInt64(compressedPayload.count)

        let needsZip64Sizes = compSize >= 0xFFFFFFFF || uncompressedSize >= 0xFFFFFFFF
        let needsZip64Offset = localOffset >= 0xFFFFFFFF
        let needsZip64Disk = localDisk >= 0xFFFF

        var localExtra = extraWithoutZip64
        if needsZip64Sizes {
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
        ZipBinary.appendUInt32LE(&lh, crc32)
        ZipBinary.appendUInt32LE(&lh, compSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(compSize))
        ZipBinary.appendUInt32LE(&lh, uncompressedSize >= 0xFFFFFFFF ? 0xFFFFFFFF : UInt32(uncompressedSize))
        ZipBinary.appendUInt16LE(&lh, UInt16(rawPathBytes.count))
        ZipBinary.appendUInt16LE(&lh, UInt16(localExtra.count))
        lh.append(rawPathBytes)
        lh.append(localExtra)

        try sink.writeData(lh)
        try sink.writeData(compressedPayload)

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

    private static func finishCentralDirectory(
        entries: [CentralDirEntry],
        comment: String,
        sink: SplitVolumeSink
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
            entriesOnStartDisk += 1
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

    private static func buildWinZipAESExtra(actualMethod: UInt16) -> Data {
        var extra = Data()
        ZipBinary.appendUInt16LE(&extra, ZipExtraTag.winZipAES)
        ZipBinary.appendUInt16LE(&extra, 7)
        ZipBinary.appendUInt16LE(&extra, 2) // AE-2
        extra.append(0x41) // 'A'
        extra.append(0x45) // 'E'
        extra.append(ZipCrypto.AESStrength.aes256.rawValue)
        ZipBinary.appendUInt16LE(&extra, actualMethod)
        return extra
    }

    private static func stripZip64Extra(_ extra: Data) -> Data {
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
