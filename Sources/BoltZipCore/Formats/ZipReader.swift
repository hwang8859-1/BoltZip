import Foundation
import os

final class ZipVolumeAccessor: @unchecked Sendable {
    let mainURL: URL
    let volumeURLs: [URL]
    private var handles: [Int: FileHandle] = [:]
    private var sizes: [Int: UInt64] = [:]
    private let ioLock = NSLock()

    init(archiveURL: URL) throws {
        // If opened via .z01/.z02, locate matching .zip central file
        let ext = archiveURL.pathExtension.lowercased()
        let resolvedMain: URL
        if ext != "zip", ext.hasPrefix("z"), Int(ext.dropFirst()) != nil {
            resolvedMain = archiveURL.deletingPathExtension().appendingPathExtension("zip")
        } else {
            resolvedMain = archiveURL
        }
        guard FileManager.default.fileExists(atPath: resolvedMain.path) else {
            throw BoltZipError.missingSplitVolume(resolvedMain.lastPathComponent)
        }
        self.mainURL = resolvedMain
        self.volumeURLs = [resolvedMain]
    }

    private var allVolumes: [URL] = []

    func configureVolumes(totalDisks: Int) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        if totalDisks <= 1 {
            allVolumes = [mainURL]
            return
        }
        let stem = mainURL.deletingPathExtension()
        var urls: [URL] = []
        for idx in 0..<(totalDisks - 1) {
            let ext = String(format: "z%02d", idx + 1)
            let part = stem.appendingPathExtension(ext)
            guard FileManager.default.fileExists(atPath: part.path) else {
                throw BoltZipError.missingSplitVolume(part.lastPathComponent)
            }
            urls.append(part)
        }
        urls.append(mainURL)
        allVolumes = urls
    }

    func closeAll() {
        ioLock.lock()
        defer { ioLock.unlock() }
        for (_, fh) in handles {
            try? fh.close()
        }
        handles.removeAll()
    }

    deinit {
        closeAll()
    }

    private func handleLocked(forDisk disk: Int) throws -> (FileHandle, UInt64) {
        let list = allVolumes.isEmpty ? [mainURL] : allVolumes
        guard disk >= 0 && disk < list.count else {
            throw BoltZipError.missingSplitVolume("Disk #\(disk + 1)")
        }
        if let fh = handles[disk], let sz = sizes[disk] {
            return (fh, sz)
        }
        let url = list[disk]
        let fh = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let sz = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        handles[disk] = fh
        sizes[disk] = sz
        return (fh, sz)
    }

    func mainFileSize() throws -> UInt64 {
        ioLock.lock()
        defer { ioLock.unlock() }
        let (_, sz) = try handleLocked(forDisk: max(0, allVolumes.count - 1))
        return sz
    }

    func readFromMainTail(length: Int) throws -> Data {
        ioLock.lock()
        defer { ioLock.unlock() }
        let disk = max(0, allVolumes.count - 1)
        let (fh, sz) = try handleLocked(forDisk: disk)
        let count = min(UInt64(length), sz)
        try fh.seek(toOffset: sz - count)
        return try fh.read(upToCount: Int(count)) ?? Data()
    }

    /// Reads `length` bytes starting at `(disk, offset)`, automatically spanning across split volumes if needed.
    func readSpanning(disk startDisk: Int, offset startOffset: UInt64, length: Int) throws -> (data: Data, endDisk: Int, endOffset: UInt64) {
        if length == 0 {
            return (Data(), startDisk, startOffset)
        }
        ioLock.lock()
        defer { ioLock.unlock() }
        var result = Data()
        result.reserveCapacity(length)
        var disk = startDisk
        var offset = startOffset
        var remaining = length

        while remaining > 0 {
            let (fh, diskSize) = try handleLocked(forDisk: disk)
            if offset >= diskSize {
                disk += 1
                offset = 0
                continue
            }
            let available = Int(min(UInt64(remaining), diskSize - offset))
            try fh.seek(toOffset: offset)
            let chunk = try fh.read(upToCount: available) ?? Data()
            if chunk.isEmpty {
                throw BoltZipError.invalidArchive("Unexpected EOF while reading ZIP disk #\(disk + 1)")
            }
            result.append(chunk)
            remaining -= chunk.count
            offset += UInt64(chunk.count)
            if remaining > 0 && offset >= diskSize {
                disk += 1
                offset = 0
            }
        }
        return (result, disk, offset)
    }
}

public final class ZipReader: @unchecked Sendable {
    struct ParsedArchive {
        let records: [ZipRecord]
        let comment: String
        let totalDisks: Int
    }

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    func parseArchive() throws -> ParsedArchive {
        let accessor = try ZipVolumeAccessor(archiveURL: url)
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
        try accessor.configureVolumes(totalDisks: totalDisks)

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

        return ParsedArchive(records: records, comment: comment, totalDisks: totalDisks)
    }

    public func listEntries(encoding: FilenameEncodingOption = .auto) throws -> (entries: [ArchiveEntry], comment: String) {
        let info = try inspectArchive(encoding: encoding)
        return (info.entries, info.comment)
    }

    func inspectArchive(encoding: FilenameEncodingOption = .auto) throws -> (entries: [ArchiveEntry], comment: String, isSplitVolume: Bool) {
        let parsed = try parseArchive()
        let entries = parsed.records.map { record in
            Self.makeEntry(from: record, encoding: encoding)
        }
        let ext = url.pathExtension.lowercased()
        let isSplitExt = ext != "zip" && ext.hasPrefix("z") && Int(ext.dropFirst()) != nil
        return (entries, parsed.comment, parsed.totalDisks > 1 || isSplitExt)
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

    /// Reads raw compressed bytes directly from local file payload (used both for extraction and zero-recompress editing).
    func readRawPayload(for record: ZipRecord, accessor: ZipVolumeAccessor) throws -> Data {
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
        let (payload, _, _) = try accessor.readSpanning(
            disk: payloadDisk,
            offset: payloadOffset,
            length: Int(record.compressedSize)
        )
        return payload
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
        let rawPayload = try readRawPayload(for: record, accessor: accessor)
        let isEncrypted = (record.flags & 0x0001) != 0

        let compressedBytes: Data
        let actualMethod: UInt16
        let skipCRC32: Bool

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
                actualMethod = aes.actualMethod
                // AE-2 clears header CRC32 to 0 and relies on HMAC-SHA1
                skipCRC32 = (aes.vendorVersion == 2)
            } else {
                compressedBytes = try ZipCrypto.decryptZipCrypto(
                    payload: rawPayload,
                    crc32: record.crc32,
                    dosTime: record.dosTime,
                    hasDataDescriptor: (record.flags & 0x0008) != 0,
                    password: pw,
                    entryName: entryPath
                )
                actualMethod = record.compressionMethod
                skipCRC32 = false
            }
        } else {
            compressedBytes = rawPayload
            actualMethod = record.compressionMethod
            skipCRC32 = false
        }

        let algo = try ZipBinary.codecAlgorithm(for: actualMethod)
        let plaintext = try CompressionCodec.decompress(
            data: compressedBytes,
            algorithm: algo,
            gzipContainer: false,
            expectedSize: Int(record.uncompressedSize),
            controller: controller,
            progress: progress
        )

        if !skipCRC32 {
            let computed = CompressionCodec.crc32(plaintext)
            if computed != record.crc32 {
                let fmt = BoltCoreLocalization.t(
                    "CRC32 不匹配 (期望 0x%08X，实际 0x%08X)",
                    "CRC32 不符 (預期 0x%08X，實際 0x%08X)",
                    "CRC32 mismatch (expected 0x%08X, actual 0x%08X)",
                    "CRC32 が一致しません (期待値 0x%08X, 実測値 0x%08X)"
                )
                throw BoltZipError.corruptedEntry(
                    entry: entryPath,
                    detail: String(format: fmt, record.crc32, computed)
                )
            }
        }
        return plaintext
    }

    public func testIntegrity(
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
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

        try ParallelExecutor.forEachBounded(indexedRecords) { _, pair in
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
                    _ = try self.decodePayload(record: record, entryPath: entry.path, accessor: accessor, password: password)
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
