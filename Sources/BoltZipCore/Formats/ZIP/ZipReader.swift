import Foundation
import os

public final class ZipReader: @unchecked Sendable {
    struct ParsedArchive {
        let records: [ZipRecord]
        let comment: String
        let totalDisks: Int
        let hasOuterData: Bool
    }

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    func parseArchive(resolveNumberedVolume: Bool = true, allowMissingParts: Bool = false) throws -> ParsedArchive {
        let accessor = try ZipVolumeAccessor(archiveURL: url, resolveNumberedVolume: resolveNumberedVolume)
        defer { accessor.closeAll() }

        let mainSize = try accessor.mainFileSize()
        guard mainSize >= 22 else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t("文件过小，不是有效的 ZIP 压缩包", "檔案過小，不是有效的 ZIP 封存檔", "File is too small to be a valid ZIP archive", "ファイルサイズが小さすぎるため有効な ZIP 書庫ではありません"))
        }

        let tailLen = Int(min(mainSize, UInt64(22 + 65535)))
        let tail = try accessor.readFromMainTail(length: tailLen)
        let tailStartOffset = mainSize - UInt64(tail.count)

        var eocdPosInTail: Int?
        var i = tail.count - 22
        while i >= 0 {
            if tail[i] == 0x50 && tail[i + 1] == 0x4B && tail[i + 2] == 0x05 && tail[i + 3] == 0x06 {
                let commentLen = Int(ZipBinary.readUInt16LE(tail, at: i + 20))
                if i + 22 + commentLen == tail.count {
                    eocdPosInTail = i
                    break
                }
            }
            i -= 1
        }

        // Allow trailing bytes after EOCD (SFX stubs, appended certs/padding) by scanning from end and verifying CD signature.
        if eocdPosInTail == nil {
            var j = tail.count - 22
            while j >= 0 {
                if tail[j] == 0x50 && tail[j + 1] == 0x4B && tail[j + 2] == 0x05 && tail[j + 3] == 0x06 {
                    let commentLen = Int(ZipBinary.readUInt16LE(tail, at: j + 20))
                    if j + 22 + commentLen <= tail.count {
                        let candDiskNum = Int(ZipBinary.readUInt16LE(tail, at: j + 4))
                        let candCDStartDisk = Int(ZipBinary.readUInt16LE(tail, at: j + 6))
                        let candCDSize = UInt64(ZipBinary.readUInt32LE(tail, at: j + 12))
                        let candCDOffset = UInt64(ZipBinary.readUInt32LE(tail, at: j + 16))
                        if (try? accessor.configureVolumes(totalDisks: candDiskNum + 1, allowMissingParts: allowMissingParts)) != nil {
                            if candCDSize == 0 {
                                eocdPosInTail = j
                                break
                            }
                            if let (probe, _, _) = try? accessor.readSpanning(disk: candCDStartDisk, offset: candCDOffset, length: 4),
                               probe.count == 4,
                               ZipBinary.readUInt32LE(probe, at: 0) == ZipSignature.centralDirectoryHeader {
                                eocdPosInTail = j
                                break
                            }
                        }
                    }
                }
                j -= 1
            }
        }

        guard let eocdPos = eocdPosInTail else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t("未找到 ZIP 中央目录结束标记 (EOCD)", "找不到 ZIP 中央目錄結尾標記 (EOCD)", "ZIP End of Central Directory (EOCD) record not found", "ZIP セントラルディレクトリ終端 (EOCD) が見つかりません"))
        }

        let diskNumber = Int(ZipBinary.readUInt16LE(tail, at: eocdPos + 4))
        var cdStartDisk = Int(ZipBinary.readUInt16LE(tail, at: eocdPos + 6))
        var totalEntries = UInt64(ZipBinary.readUInt16LE(tail, at: eocdPos + 10))
        var cdSize = UInt64(ZipBinary.readUInt32LE(tail, at: eocdPos + 12))
        var cdOffset = UInt64(ZipBinary.readUInt32LE(tail, at: eocdPos + 16))
        let commentLen = Int(ZipBinary.readUInt16LE(tail, at: eocdPos + 20))
        let commentData = tail.subdata(in: (eocdPos + 22)..<(eocdPos + 22 + commentLen))
        let comment = String(data: commentData, encoding: .utf8) ?? ""

        let totalDisks = diskNumber + 1
        try accessor.configureVolumes(totalDisks: totalDisks, allowMissingParts: allowMissingParts)

        // Check ZIP64 EOCD Locator immediately preceding EOCD
        let eocdGlobalPos = tailStartOffset + UInt64(eocdPos)
        if eocdGlobalPos >= 20 {
            let locDisk = totalDisks - 1
            let (locData, _, _) = try accessor.readSpanning(disk: locDisk, offset: eocdGlobalPos - 20, length: 20)
            if ZipBinary.readUInt32LE(locData, at: 0) == ZipSignature.zip64Locator {
                let z64Disk = Int(ZipBinary.readUInt32LE(locData, at: 4))
                let z64Offset = ZipBinary.readUInt64LE(locData, at: 8)
                let (z64Header, _, _) = try accessor.readSpanning(disk: z64Disk, offset: z64Offset, length: 56)
                guard ZipBinary.readUInt32LE(z64Header, at: 0) == ZipSignature.zip64EOCD else {
                    throw BoltZipError.invalidArchive(BoltCoreLocalization.t("ZIP64 EOCD 签名无效", "ZIP64 EOCD 簽章無效", "Invalid ZIP64 EOCD signature", "ZIP64 EOCD シグネチャが無効です"))
                }
                cdStartDisk = Int(ZipBinary.readUInt32LE(z64Header, at: 20))
                totalEntries = ZipBinary.readUInt64LE(z64Header, at: 32)
                cdSize = ZipBinary.readUInt64LE(z64Header, at: 40)
                cdOffset = ZipBinary.readUInt64LE(z64Header, at: 48)
            }
        }

        let maxCentralDirectoryBytes: UInt64 = 512 * 1024 * 1024
        let availableBytes = try accessor.totalAvailableBytes(allowMissingParts: allowMissingParts)
        guard cdSize <= availableBytes && cdSize <= maxCentralDirectoryBytes && cdSize <= UInt64(Int.max) else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t("ZIP 中央目录声明大小越界或损坏", "ZIP 中央目錄宣告大小越界或損毀", "ZIP central directory size is corrupted or exceeds archive bounds", "ZIP セントラルディレクトリサイズが不正またはアーカイブ範囲外です"))
        }

        let (cdBytes, _, _) = try accessor.readSpanning(disk: cdStartDisk, offset: cdOffset, length: Int(cdSize))
        var records: [ZipRecord] = []
        records.reserveCapacity(Int(min(totalEntries, 100_000)))

        var pos = 0
        while pos + 46 <= cdBytes.count {
            let sig = ZipBinary.readUInt32LE(cdBytes, at: pos)
            guard sig == ZipSignature.centralDirectoryHeader else {
                throw BoltZipError.invalidArchive(BoltCoreLocalization.t("ZIP 中央目录记录签名无效", "ZIP 中央目錄紀錄簽章無效", "Invalid ZIP central directory signature", "ZIP セントラルディレクトリ記録のシグネチャが無効です"))
            }

            let flags = ZipBinary.readUInt16LE(cdBytes, at: pos + 8)
            let method = ZipBinary.readUInt16LE(cdBytes, at: pos + 10)
            let dosTime = ZipBinary.readUInt16LE(cdBytes, at: pos + 12)
            let dosDate = ZipBinary.readUInt16LE(cdBytes, at: pos + 14)
            let crc = ZipBinary.readUInt32LE(cdBytes, at: pos + 16)
            let comp32 = ZipBinary.readUInt32LE(cdBytes, at: pos + 20)
            let uncomp32 = ZipBinary.readUInt32LE(cdBytes, at: pos + 24)
            let nameLen = Int(ZipBinary.readUInt16LE(cdBytes, at: pos + 28))
            let extraLen = Int(ZipBinary.readUInt16LE(cdBytes, at: pos + 30))
            let commentFieldLen = Int(ZipBinary.readUInt16LE(cdBytes, at: pos + 32))
            let diskStart16 = ZipBinary.readUInt16LE(cdBytes, at: pos + 34)
            let extAttrs = ZipBinary.readUInt32LE(cdBytes, at: pos + 38)
            let offset32 = ZipBinary.readUInt32LE(cdBytes, at: pos + 42)

            pos += 46
            guard pos + nameLen + extraLen + commentFieldLen <= cdBytes.count else {
                throw BoltZipError.invalidArchive(BoltCoreLocalization.t("ZIP 中央目录长度越界", "ZIP 中央目錄長度越界", "ZIP central directory entry exceeds bounds", "ZIP セントラルディレクトリ長が範囲外です"))
            }

            let rawPath = cdBytes.subdata(in: pos..<(pos + nameLen))
            pos += nameLen
            let extraData = cdBytes.subdata(in: pos..<(pos + extraLen))
            pos += extraLen
            let entryCommentData = cdBytes.subdata(in: pos..<(pos + commentFieldLen))
            pos += commentFieldLen

            let parsedExtra = ZipBinary.parseExtraFields(
                extraData,
                rawPathBytes: rawPath,
                compressedSize32: comp32,
                uncompressedSize32: uncomp32,
                offset32: offset32,
                disk32: diskStart16
            )

            guard parsedExtra.compressedSize <= availableBytes,
                  parsedExtra.uncompressedSize <= UInt64(Int64.max) else {
                throw BoltZipError.invalidArchive("ZIP entry size exceeds archive bounds or the supported range")
            }

            records.append(
                ZipRecord(
                    rawPathBytes: rawPath,
                    flags: flags,
                    compressionMethod: method,
                    dosTime: dosTime,
                    dosDate: dosDate,
                    crc32: crc,
                    compressedSize: parsedExtra.compressedSize,
                    uncompressedSize: parsedExtra.uncompressedSize,
                    diskNumberStart: parsedExtra.diskStart,
                    localHeaderOffset: parsedExtra.localOffset,
                    externalAttributes: extAttrs,
                    extraData: extraData,
                    commentData: entryCommentData,
                    unicodeExtraPath: parsedExtra.unicodePath,
                    extendedTimestamp: parsedExtra.mtime,
                    aesExtra: parsedExtra.aes
                )
            )
        }

        // The writer only recreates the ZIP records. Keep prefixed or suffixed containers read-only.
        let firstLocalHeader = records.lazy.map(\.localHeaderOffset).min() ?? cdOffset
        let hasOuterData = totalDisks == 1 && (firstLocalHeader > 0 || eocdPos + 22 + commentLen < tail.count)
        return ParsedArchive(records: records, comment: comment, totalDisks: totalDisks, hasOuterData: hasOuterData)
    }

    public func listEntries(encoding: FilenameEncodingOption = .auto) throws -> (entries: [ArchiveEntry], comment: String) {
        let info = try inspectArchive(encoding: encoding)
        return (info.entries, info.comment)
    }

    func inspectArchive(encoding: FilenameEncodingOption = .auto) throws -> (entries: [ArchiveEntry], comment: String, isSplitVolume: Bool) {
        let info = try inspectParsedArchive(encoding: encoding)
        return (info.entries, info.comment, info.isSplitVolume)
    }

    func inspectParsedArchive(encoding: FilenameEncodingOption = .auto) throws -> (entries: [ArchiveEntry], comment: String, isSplitVolume: Bool, parsed: ParsedArchive) {
        let parsed = try parseArchive()
        let entries = parsed.records.map { record in
            Self.makeEntry(from: record, encoding: encoding)
        }
        return (entries, parsed.comment, parsed.totalDisks > 1 || ZipVolumeAccessor.isNumberedVolume(url), parsed)
    }

    static func makeEntry(from record: ZipRecord, encoding: FilenameEncodingOption) -> ArchiveEntry {
        let hasUTF8 = (record.flags & 0x0800) != 0
        let decodedPath = FilenameEncoding.decode(
            record.rawPathBytes,
            hasUTF8Flag: hasUTF8,
            unicodeExtraPath: record.unicodeExtraPath,
            preferred: encoding
        )
        let isDir = decodedPath.hasSuffix("/") || decodedPath.hasSuffix("\\") || ((record.externalAttributes & 0x10) != 0 && record.uncompressedSize == 0 && record.compressedSize == 0 && !decodedPath.contains("."))
        let unixMode = UInt16((record.externalAttributes >> 16) & 0xFFFF)
        let isSymlink = (unixMode & 0xF000) == 0xA000
        let permissions: UInt16 = (unixMode & 0x0FFF) != 0 ? (unixMode & 0x0FFF) : (isDir ? 0o755 : 0o644)
        let isEncrypted = (record.flags & 0x0001) != 0
        let encLabel: String
        if !isEncrypted {
            encLabel = ""
        } else if let aes = record.aesExtra {
            switch aes.strength {
            case .aes256: encLabel = "AES-256"
            case .aes192: encLabel = "AES-192"
            case .aes128: encLabel = "AES-128"
            }
        } else {
            encLabel = "ZipCrypto"
        }

        let modDate = record.extendedTimestamp ?? ZipBinary.dateFromDOS(time: record.dosTime, date: record.dosDate)
        let comment = String(data: record.commentData, encoding: .utf8) ?? ""
        return ArchiveEntry(
            path: decodedPath,
            isDirectory: isDir,
            isSymbolicLink: isSymlink,
            uncompressedSize: record.uncompressedSize,
            compressedSize: record.compressedSize,
            compressionMethodName: ZipBinary.methodDisplayName(compressionMethod: record.compressionMethod, aes: record.aesExtra),
            crc32: record.crc32,
            modifiedDate: modDate,
            permissions: permissions,
            isEncrypted: isEncrypted,
            encryptionLabel: encLabel,
            comment: comment,
            rawPathBytes: record.rawPathBytes,
            hasUTF8Flag: hasUTF8
        )
    }

    private func resolvePayloadStart(for record: ZipRecord, accessor: ZipVolumeAccessor) throws -> (disk: Int, offset: UInt64) {
        let (lh, dataDisk, dataOffset) = try accessor.readSpanning(
            disk: Int(record.diskNumberStart),
            offset: record.localHeaderOffset,
            length: 30
        )
        guard ZipBinary.readUInt32LE(lh, at: 0) == ZipSignature.localFileHeader else {
            throw BoltZipError.invalidArchive(BoltCoreLocalization.t("ZIP 本地文件头签名损坏", "ZIP 本機檔案標頭簽章損毀", "Corrupted ZIP local file header signature", "ZIP ローカルファイルヘッダのシグネチャが破損しています"))
        }
        let localNameLen = Int(ZipBinary.readUInt16LE(lh, at: 26))
        let localExtraLen = Int(ZipBinary.readUInt16LE(lh, at: 28))
        let (_, payloadDisk, payloadOffset) = try accessor.readSpanning(
            disk: dataDisk,
            offset: dataOffset,
            length: localNameLen + localExtraLen
        )
        return (payloadDisk, payloadOffset)
    }

    /// Reads raw compressed bytes directly from local file payload (used both for small extraction and zero-recompress editing).
    func readRawPayload(for record: ZipRecord, accessor: ZipVolumeAccessor) throws -> Data {
        let (payloadDisk, payloadOffset) = try resolvePayloadStart(for: record, accessor: accessor)
        let (payload, _, _) = try accessor.readSpanning(
            disk: payloadDisk,
            offset: payloadOffset,
            length: Int(record.compressedSize)
        )
        return payload
    }

    func streamRawPayload(
        for record: ZipRecord,
        accessor: ZipVolumeAccessor,
        chunkSize: Int = BoltConcurrency.streamChunkSize,
        controller: ArchiveTaskController? = nil,
        onChunk: (Data) throws -> Void
    ) throws {
        let (payloadDisk, payloadOffset) = try resolvePayloadStart(for: record, accessor: accessor)
        let cursor = accessor.makeSpanningCursor(disk: payloadDisk, offset: payloadOffset, totalLength: record.compressedSize)
        while cursor.remaining > 0 {
            try controller?.checkpoint()
            let chunk = try cursor.readNext(maxBytes: chunkSize)
            if chunk.isEmpty { break }
            try onChunk(chunk)
        }
    }

    public func readEntryData(
        path: String,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto
    ) throws -> Data {
        let parsed = try parseArchive()
        let accessor = try ZipVolumeAccessor(archiveURL: url)
        try accessor.configureVolumes(totalDisks: parsed.totalDisks)
        defer { accessor.closeAll() }

        let targetNorm = ArchiveEntry.normalizePath(path, isDirectory: path.hasSuffix("/"))
        guard let record = parsed.records.first(where: { Self.makeEntry(from: $0, encoding: encoding).path == targetNorm }) else {
            throw BoltZipError.entryNotFound(path)
        }
        return try decodePayload(record: record, entryPath: targetNorm, accessor: accessor, password: password)
    }

    func decodePayload(
        record: ZipRecord,
        entryPath: String,
        accessor: ZipVolumeAccessor,
        password: String?,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        try controller?.checkpoint()
        let isEncrypted = (record.flags & 0x0001) != 0
        let actualMethod = record.aesExtra?.actualMethod ?? record.compressionMethod
        let skipCRC32 = (record.compressionMethod == 99 && record.aesExtra?.vendorVersion == 2)

        let bufferLimit: UInt64 = 256 * 1024 * 1024
        guard record.compressedSize <= bufferLimit, record.uncompressedSize <= bufferLimit else {
            throw BoltZipError.invalidArchive("ZIP entry exceeds the memory limit for reading into a buffer")
        }

        // Read-only fallback via macOS system libarchive for Deflate64 (method 9) and LZMA (method 14)
        if actualMethod == 9 || actualMethod == 14 {
            do {
                try controller?.checkpoint()
                let data = try ExtendedArchiveDriver.readEntryData(
                    at: url,
                    format: .zip,
                    path: entryPath,
                    password: password,
                    encoding: .auto,
                    exactOutputSize: record.uncompressedSize
                )
                try controller?.checkpoint()
                if !skipCRC32 {
                    let computed = CompressionCodec.crc32(data)
                    if computed != record.crc32 {
                        try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: computed)
                    }
                }
                return data
            } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
                throw isEncrypted && (password ?? "").isEmpty ? BoltZipError.passwordRequired(entryPath) : BoltZipError.wrongPassword(entryPath)
            } catch let error as BoltZipError {
                switch error {
                case .cancelled, .corruptedEntry, .invalidArchive, .entryNotFound, .missingSplitVolume, .externalToolFailed:
                    throw error
                default:
                    throw BoltZipError.unsupportedCompressionMethod(actualMethod)
                }
            } catch {
                throw BoltZipError.unsupportedCompressionMethod(actualMethod)
            }
        }

        let rawPayload = try readRawPayload(for: record, accessor: accessor)

        let compressedBytes: Data
        if isEncrypted {
            guard let pw = password, !pw.isEmpty else {
                throw BoltZipError.passwordRequired(entryPath)
            }
            if record.compressionMethod == 99, let aes = record.aesExtra {
                compressedBytes = try ZipCrypto.decryptAES(
                    payload: rawPayload,
                    password: pw,
                    strength: aes.strength,
                    entryName: entryPath
                )
            } else {
                compressedBytes = try ZipCrypto.decryptZipCrypto(
                    payload: rawPayload,
                    crc32: record.crc32,
                    dosTime: record.dosTime,
                    hasDataDescriptor: (record.flags & 0x0008) != 0,
                    password: pw,
                    entryName: entryPath
                )
            }
        } else {
            compressedBytes = rawPayload
        }

        let algo = try ZipBinary.codecAlgorithm(for: actualMethod)
        let plaintext = try CompressionCodec.decompress(
            data: compressedBytes,
            algorithm: algo,
            gzipContainer: false,
            expectedSize: Int(record.uncompressedSize),
            exactOutputSize: record.uncompressedSize,
            controller: controller,
            progress: progress
        )

        if !skipCRC32 {
            let computed = CompressionCodec.crc32(plaintext)
            if computed != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: computed)
            }
        }
        return plaintext
    }

    func decodePayloadToFile(
        record: ZipRecord,
        entryPath: String,
        accessor: ZipVolumeAccessor,
        destinationURL initialURL: URL,
        destinationRoot: URL,
        entry: ArchiveEntry,
        overwritePolicy: OverwritePolicy,
        password: String?,
        protectedSourcePaths: Set<String> = [],
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (UInt64, UInt64) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let protected = protectedSourcePaths.isEmpty
            ? Set((accessor.volumeURLs + [url]).map(ArchiveExtractionDestination.pathKey))
            : protectedSourcePaths
        let threshold = BoltConcurrency.streamingThresholdBytes
        let actualMethod = record.aesExtra?.actualMethod ?? record.compressionMethod

        // Fast small-entry path
        if record.compressedSize < threshold && record.uncompressedSize < threshold {
            let plain = try decodePayload(
                record: record,
                entryPath: entryPath,
                accessor: accessor,
                password: password,
                controller: controller,
                progress: progress
            )
            try ArchiveExtractionDestination.writeExtractedFile(plain, to: initialURL, under: destinationRoot, entry: entry,
                                                     policy: overwritePolicy, protectedSourcePaths: protected, controller: controller)
            return
        }

        let fm = FileManager.default
        if actualMethod == 9 || actualMethod == 14 {
            guard let targetURL = try ArchiveExtractionDestination.prepareExtractTargetURL(
                initialURL: initialURL, under: destinationRoot, policy: overwritePolicy
            ) else { return }
            let stageDir = try ArchiveExtractionDestination.makeExtractionStage(near: targetURL, under: destinationRoot)
            defer { try? fm.removeItem(at: stageDir) }
            try ExtendedArchiveDriver.extract(
                at: url,
                format: .zip,
                to: stageDir,
                selectedPaths: [entryPath],
                overwritePolicy: .overwrite,
                password: password,
                encoding: .auto,
                stripMacJunk: false,
                restoreSymlinks: false,
                expectedTotalBytes: record.uncompressedSize,
                exactEntrySize: record.uncompressedSize,
                controller: controller,
                progress: progress.map { cb in
                    { @Sendable (p: OperationProgress) in
                        cb(p.processedBytes, p.totalBytes)
                    }
                }
            )
            let stagedURL = try ArchiveExtractionDestination.safeDestinationURL(for: entryPath, under: stageDir)
            guard fm.fileExists(atPath: stagedURL.path) else {
                throw BoltZipError.entryNotFound(entryPath)
            }
            if !((record.compressionMethod == 99) && (record.aesExtra?.vendorVersion == 2)) {
                let actualCRC = try CompressionCodec.crc32File(at: stagedURL, controller: controller)
                if actualCRC != record.crc32 {
                    try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: actualCRC)
                }
            }
            try ArchiveExtractionDestination.commitExtractedItem(stagedURL, to: targetURL, under: destinationRoot,
                                                      policy: overwritePolicy, protectedSourcePaths: protected, controller: controller)
            let attrs: [FileAttributeKey: Any] = [
                .modificationDate: entry.modifiedDate,
                .posixPermissions: NSNumber(value: entry.permissions)
            ]
            try? fm.setAttributes(attrs, ofItemAtPath: targetURL.path)
            return
        }

        guard let targetURL = try ArchiveExtractionDestination.prepareExtractTargetURL(
            initialURL: initialURL,
            under: destinationRoot,
            policy: overwritePolicy
        ) else {
            return
        }

        let isEncrypted = (record.flags & 0x0001) != 0
        let skipCRC32 = (record.compressionMethod == 99 && record.aesExtra?.vendorVersion == 2)
        let algo = try ZipBinary.codecAlgorithm(for: actualMethod)
        let (payloadDisk, payloadOffset) = try resolvePayloadStart(for: record, accessor: accessor)
        let cursor = accessor.makeSpanningCursor(disk: payloadDisk, offset: payloadOffset, totalLength: record.compressedSize)

        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: targetURL, under: destinationRoot)
        defer { try? fm.removeItem(at: stage) }
        let stagePlainURL = stage.appendingPathComponent("payload")

        if isEncrypted {
            guard let pw = password, !pw.isEmpty else {
                throw BoltZipError.passwordRequired(entryPath)
            }
            let compTargetURL = algo == .store ? stagePlainURL : stage.appendingPathComponent("decrypted")

            fm.createFile(atPath: compTargetURL.path, contents: nil)
            let compHandle = try FileHandle(forWritingTo: compTargetURL)
            var closeComp = true
            defer { if closeComp { try? compHandle.close() } }
            var streamCRC: UInt32 = 0
            var processed: UInt64 = 0
            let totalOut = max(record.compressedSize, 1)

            let writeDecChunk: (Data) throws -> Void = { chunk in
                if algo == .store {
                    guard UInt64(chunk.count) <= record.uncompressedSize - processed else {
                        throw self.decodedSizeMismatch(entryPath)
                    }
                }
                if algo == .store && !skipCRC32 {
                    streamCRC = CompressionCodec.crc32(chunk, initial: streamCRC)
                }
                try compHandle.write(contentsOf: chunk)
                processed += UInt64(chunk.count)
                if algo == .store {
                    progress?(min(record.uncompressedSize, processed), record.uncompressedSize)
                } else {
                    progress?(min(totalOut, processed) / 2, totalOut)
                }
            }

            if record.compressionMethod == 99, let aes = record.aesExtra {
                try ZipCrypto.decryptAESStream(
                    payloadLength: record.compressedSize,
                    password: pw,
                    strength: aes.strength,
                    entryName: entryPath,
                    controller: controller,
                    readBytes: { maxBytes in try cursor.readNext(maxBytes: maxBytes) },
                    writePlaintextChunk: writeDecChunk
                )
            } else {
                try ZipCrypto.decryptZipCryptoStream(
                    payloadLength: record.compressedSize,
                    crc32: record.crc32,
                    dosTime: record.dosTime,
                    hasDataDescriptor: (record.flags & 0x0008) != 0,
                    password: pw,
                    entryName: entryPath,
                    controller: controller,
                    readBytes: { maxBytes in try cursor.readNext(maxBytes: maxBytes) },
                    writePlaintextChunk: writeDecChunk
                )
            }
            try compHandle.close()
            closeComp = false

            if algo == .store && processed != record.uncompressedSize {
                throw decodedSizeMismatch(entryPath)
            }
            if algo != .store {
                try CompressionCodec.decompressFile(
                    sourceURL: compTargetURL,
                    destinationURL: stagePlainURL,
                    algorithm: algo,
                    gzipContainer: false,
                    exactOutputSize: record.uncompressedSize,
                    controller: controller,
                    progress: { r, tot in
                        let base = record.uncompressedSize / 2
                        let scaled = tot > 0 ? UInt64(Double(record.uncompressedSize) * 0.5 * (Double(r) / Double(tot))) : 0
                        progress?(min(record.uncompressedSize, base + scaled), record.uncompressedSize)
                    }
                )
                if !skipCRC32 {
                    streamCRC = try CompressionCodec.crc32File(at: stagePlainURL, controller: controller)
                }
            }
            if !skipCRC32 && streamCRC != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: streamCRC)
            }
        } else if algo == .store {
            guard record.compressedSize == record.uncompressedSize else { throw decodedSizeMismatch(entryPath) }
            fm.createFile(atPath: stagePlainURL.path, contents: nil)
            let outHandle = try FileHandle(forWritingTo: stagePlainURL)
            var closeOut = true
            defer { if closeOut { try? outHandle.close() } }
            var streamCRC: UInt32 = 0
            var written: UInt64 = 0
            while cursor.remaining > 0 {
                try controller?.checkpoint()
                let chunk = try cursor.readNext(maxBytes: BoltConcurrency.streamChunkSize)
                if chunk.isEmpty { break }
                streamCRC = CompressionCodec.crc32(chunk, initial: streamCRC)
                try outHandle.write(contentsOf: chunk)
                written += UInt64(chunk.count)
                progress?(min(record.uncompressedSize, written), record.uncompressedSize)
            }
            try outHandle.close()
            closeOut = false
            if streamCRC != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: streamCRC)
            }
        } else {
            let rawTmpURL = stage.appendingPathComponent("compressed")
            fm.createFile(atPath: rawTmpURL.path, contents: nil)
            let rawHandle = try FileHandle(forWritingTo: rawTmpURL)
            var closeRaw = true
            defer { if closeRaw { try? rawHandle.close() } }
            while cursor.remaining > 0 {
                try controller?.checkpoint()
                let chunk = try cursor.readNext(maxBytes: BoltConcurrency.streamChunkSize)
                if chunk.isEmpty { break }
                try rawHandle.write(contentsOf: chunk)
            }
            try rawHandle.close()
            closeRaw = false

            try CompressionCodec.decompressFile(
                sourceURL: rawTmpURL,
                destinationURL: stagePlainURL,
                algorithm: algo,
                gzipContainer: false,
                exactOutputSize: record.uncompressedSize,
                controller: controller,
                progress: { r, tot in
                    let frac = tot > 0 ? Double(r) / Double(tot) : 0
                    let est = UInt64(Double(record.uncompressedSize) * frac)
                    progress?(min(record.uncompressedSize, est), record.uncompressedSize)
                }
            )
            let computed = try CompressionCodec.crc32File(at: stagePlainURL, controller: controller)
            if computed != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: computed)
            }
        }

        try ArchiveExtractionDestination.commitExtractedItem(stagePlainURL, to: targetURL, under: destinationRoot,
                                                  policy: overwritePolicy, protectedSourcePaths: protected, controller: controller)
        let attrs: [FileAttributeKey: Any] = [
            .modificationDate: entry.modifiedDate,
            .posixPermissions: NSNumber(value: entry.permissions)
        ]
        try? fm.setAttributes(attrs, ofItemAtPath: targetURL.path)
    }

    func verifyPayloadIntegrity(
        record: ZipRecord,
        entryPath: String,
        accessor: ZipVolumeAccessor,
        password: String?
    ) throws {
        let threshold = BoltConcurrency.streamingThresholdBytes
        let actualMethod = record.aesExtra?.actualMethod ?? record.compressionMethod
        if record.compressedSize < threshold && record.uncompressedSize < threshold {
            _ = try decodePayload(record: record, entryPath: entryPath, accessor: accessor, password: password)
            return
        }

        if actualMethod == 9 || actualMethod == 14 {
            let fm = FileManager.default
            let stage = fm.temporaryDirectory.appendingPathComponent("boltzip-verify-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: stage) }
            try decodePayloadToFile(record: record, entryPath: entryPath, accessor: accessor,
                                    destinationURL: stage.appendingPathComponent("payload"), destinationRoot: stage,
                                    entry: Self.makeEntry(from: record, encoding: .auto),
                                    overwritePolicy: .overwrite, password: password)
            return
        }

        let isEncrypted = (record.flags & 0x0001) != 0
        let skipCRC32 = (record.compressionMethod == 99 && record.aesExtra?.vendorVersion == 2)
        let algo = try ZipBinary.codecAlgorithm(for: actualMethod)
        let (payloadDisk, payloadOffset) = try resolvePayloadStart(for: record, accessor: accessor)
        let cursor = accessor.makeSpanningCursor(disk: payloadDisk, offset: payloadOffset, totalLength: record.compressedSize)
        let fm = FileManager.default

        if isEncrypted {
            guard let pw = password, !pw.isEmpty else {
                throw BoltZipError.passwordRequired(entryPath)
            }
            let tmpURL = (algo == .store) ? nil : fm.temporaryDirectory.appendingPathComponent("boltzip-vdec-\(UUID().uuidString).tmp")
            var tmpHandle: FileHandle?
            defer {
                try? tmpHandle?.close()
                if let tmpURL { try? fm.removeItem(at: tmpURL) }
            }
            if let tmpURL {
                fm.createFile(atPath: tmpURL.path, contents: nil)
                tmpHandle = try FileHandle(forWritingTo: tmpURL)
            }
            var streamCRC: UInt32 = 0
            var decodedBytes: UInt64 = 0
            let onChunk: (Data) throws -> Void = { chunk in
                if let tmpHandle {
                    try tmpHandle.write(contentsOf: chunk)
                } else {
                    guard UInt64(chunk.count) <= record.uncompressedSize - decodedBytes else {
                        throw self.decodedSizeMismatch(entryPath)
                    }
                    decodedBytes += UInt64(chunk.count)
                    if !skipCRC32 { streamCRC = CompressionCodec.crc32(chunk, initial: streamCRC) }
                }
            }
            if record.compressionMethod == 99, let aes = record.aesExtra {
                try ZipCrypto.decryptAESStream(
                    payloadLength: record.compressedSize,
                    password: pw,
                    strength: aes.strength,
                    entryName: entryPath,
                    readBytes: { maxBytes in try cursor.readNext(maxBytes: maxBytes) },
                    writePlaintextChunk: onChunk
                )
            } else {
                try ZipCrypto.decryptZipCryptoStream(
                    payloadLength: record.compressedSize,
                    crc32: record.crc32,
                    dosTime: record.dosTime,
                    hasDataDescriptor: (record.flags & 0x0008) != 0,
                    password: pw,
                    entryName: entryPath,
                    readBytes: { maxBytes in try cursor.readNext(maxBytes: maxBytes) },
                    writePlaintextChunk: onChunk
                )
            }
            try tmpHandle?.close()
            tmpHandle = nil
            if let tmpURL {
                let verified = try CompressionCodec.verifyFile(sourceURL: tmpURL, algorithm: algo, exactOutputSize: record.uncompressedSize)
                if !skipCRC32 && verified.crc32 != record.crc32 {
                    try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: verified.crc32)
                }
            } else {
                guard decodedBytes == record.uncompressedSize else { throw decodedSizeMismatch(entryPath) }
                if !skipCRC32 && streamCRC != record.crc32 {
                    try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: streamCRC)
                }
            }
        } else if algo == .store {
            guard record.compressedSize == record.uncompressedSize else { throw decodedSizeMismatch(entryPath) }
            var streamCRC: UInt32 = 0
            while cursor.remaining > 0 {
                let chunk = try cursor.readNext(maxBytes: BoltConcurrency.streamChunkSize)
                if chunk.isEmpty { break }
                streamCRC = CompressionCodec.crc32(chunk, initial: streamCRC)
            }
            if streamCRC != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: streamCRC)
            }
        } else {
            let rawTmp = fm.temporaryDirectory.appendingPathComponent("boltzip-vraw-\(UUID().uuidString).tmp")
            defer { try? fm.removeItem(at: rawTmp) }
            fm.createFile(atPath: rawTmp.path, contents: nil)
            let rawHandle = try FileHandle(forWritingTo: rawTmp)
            while cursor.remaining > 0 {
                let chunk = try cursor.readNext(maxBytes: BoltConcurrency.streamChunkSize)
                if chunk.isEmpty { break }
                try rawHandle.write(contentsOf: chunk)
            }
            try rawHandle.close()
            let verified = try CompressionCodec.verifyFile(sourceURL: rawTmp, algorithm: algo, exactOutputSize: record.uncompressedSize)
            if verified.crc32 != record.crc32 {
                try throwCRC32Mismatch(entryPath: entryPath, expected: record.crc32, actual: verified.crc32)
            }
        }
    }

    private func decodedSizeMismatch(_ entryPath: String) -> BoltZipError {
        .corruptedEntry(entry: entryPath, detail: BoltCoreLocalization.t(
            "解压大小与声明不符", "解壓縮大小與宣告不符",
            "Decoded size does not match the declared entry size", "展開サイズが宣言と一致しません"
        ))
    }

    private func throwCRC32Mismatch(entryPath: String, expected: UInt32, actual: UInt32) throws -> Never {
        let fmt = BoltCoreLocalization.t(
            "CRC32 不匹配 (期望 0x%08X，实际 0x%08X)",
            "CRC32 不符 (預期 0x%08X，實際 0x%08X)",
            "CRC32 mismatch (expected 0x%08X, actual 0x%08X)",
            "CRC32 が一致しません (期待値 0x%08X, 実測値 0x%08X)"
        )
        throw BoltZipError.corruptedEntry(
            entry: entryPath,
            detail: String(format: fmt, expected, actual)
        )
    }

    public func testIntegrity(
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        workerCount: Int? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> IntegrityReport {
        let start = CFAbsoluteTimeGetCurrent()
        let parsed = try parseArchive()
        let accessor = try ZipVolumeAccessor(archiveURL: url)
        try accessor.configureVolumes(totalDisks: parsed.totalDisks)
        defer { accessor.closeAll() }

        let total = parsed.records.count
        struct IntegrityStats {
            var results: [IntegrityEntryResult?]
            var completed = 0
            var passed = 0
            var failed = 0
            var missingPw = 0
        }
        let stateLock = OSAllocatedUnfairLock(initialState: IntegrityStats(results: [IntegrityEntryResult?](repeating: nil, count: total)))
        let indexedRecords = Array(parsed.records.enumerated())
        let maxWorkers = BoltConcurrency.resolvedWorkerCount(override: workerCount)

        try ParallelExecutor.forEachBounded(indexedRecords, maxWorkers: maxWorkers) { _, pair in
            let (index, record) = pair
            let entry = Self.makeEntry(from: record, encoding: encoding)
            let itemResult: IntegrityEntryResult
            enum OutcomeKind { case passed, missingPw, failed }
            let kind: OutcomeKind

            if entry.isDirectory {
                kind = .passed
                itemResult = IntegrityEntryResult(
                    path: entry.path,
                    status: .passed,
                    detail: BoltCoreLocalization.t("目录条目正常", "目錄項目正常", "Directory entry OK", "フォルダ項目正常")
                )
            } else {
                do {
                    try self.verifyPayloadIntegrity(record: record, entryPath: entry.path, accessor: accessor, password: password)
                    kind = .passed
                    let detail = entry.isEncrypted
                        ? BoltCoreLocalization.t("解密与 HMAC/CRC 校验通过", "解密與 HMAC/CRC 驗證通過", "Decryption & HMAC/CRC verified", "復号および HMAC/CRC 検証に合格")
                        : String(
                            format: BoltCoreLocalization.t("CRC32 校验通过 (0x%08X)", "CRC32 驗證通過 (0x%08X)", "CRC32 OK (0x%08X)", "CRC32 正常 (0x%08X)"),
                            entry.crc32
                        )
                    itemResult = IntegrityEntryResult(path: entry.path, status: .passed, detail: detail)
                } catch BoltZipError.passwordRequired {
                    kind = .missingPw
                    itemResult = IntegrityEntryResult(
                        path: entry.path,
                        status: .missingPassword,
                        detail: BoltCoreLocalization.t("已加密，需要密码", "已加密，需要密碼", "Encrypted, password required", "暗号化されています（パスワードが必要）")
                    )
                } catch {
                    kind = .failed
                    itemResult = IntegrityEntryResult(path: entry.path, status: .failed, detail: error.localizedDescription)
                }
            }

            let doneCount = stateLock.withLock { st -> Int in
                st.results[index] = itemResult
                st.completed += 1
                switch kind {
                case .passed: st.passed += 1
                case .missingPw: st.missingPw += 1
                case .failed: st.failed += 1
                }
                return st.completed
            }
            progress?(OperationProgress(
                fractionCompleted: total > 0 ? Double(doneCount) / Double(total) : 1.0,
                currentItem: entry.path,
                processedBytes: UInt64(doneCount),
                totalBytes: UInt64(total)
            ))
        }

        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: BoltCoreLocalization.t("校验完成", "驗證完成", "Verification complete", "検証完了"),
            processedBytes: UInt64(total),
            totalBytes: UInt64(total)
        ))

        let finalState = stateLock.withLock { $0 }
        return IntegrityReport(
            archiveName: url.lastPathComponent,
            totalEntries: total,
            passedCount: finalState.passed,
            failedCount: finalState.failed,
            skippedEncryptedCount: finalState.missingPw,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
            results: finalState.results.compactMap { $0 }
        )
    }
}
