import Foundation

public struct ZipRecoveryFailure: Identifiable, Sendable {
    public let id = UUID()
    public let entryPath: String
    public let reason: String

    public init(entryPath: String, reason: String) {
        self.entryPath = entryPath
        self.reason = reason
    }
}

public struct ZipRecoveryReport: Sendable {
    public let sourceURL: URL
    public let recoveredArchiveURL: URL?
    public let totalScannedCount: Int
    public let recoveredEntries: [ArchiveEntry]
    public let unrecoverableEntries: [ZipRecoveryFailure]
    public let usedLocalHeaderFallbackScan: Bool
    public let elapsedSeconds: TimeInterval

    public var recoveredCount: Int { recoveredEntries.count }
    public var unrecoverableCount: Int { unrecoverableEntries.count }
}

extension BoltArchiveEngine {
    public static func recoverZip(
        at sourceURL: URL,
        to destinationURL: URL,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> ZipRecoveryReport {
        let start = CFAbsoluteTimeGetCurrent()
        try controller?.checkpoint()
        try ArchiveOutputTransaction.validate(destinationURL)

        let sourceProtected = (try? extractionSourceURLs(archiveURL: sourceURL, password: password)) ?? [sourceURL]
        let protectedKeys = Set(sourceProtected.map(ArchiveExtractionDestination.pathKey))
        if protectedKeys.contains(ArchiveExtractionDestination.pathKey(destinationURL)) {
            throw ArchiveOperationError.outputIsInput
        }

        let reader = ZipReader(url: sourceURL)
        let candidateRecords: [ZipRecord]
        var comment = ""
        var totalDisks = 1
        var usedFallbackScan = false

        if let parsed = try? reader.parseArchive(allowMissingParts: true) {
            candidateRecords = parsed.records
            comment = parsed.comment
            totalDisks = parsed.totalDisks
        } else {
            usedFallbackScan = true
            candidateRecords = try scanLocalFileHeaders(at: sourceURL, controller: controller)
        }

        guard !candidateRecords.isEmpty else {
            throw ArchiveOperationError.noRecoverableZipEntries
        }

        let accessor = try ZipVolumeAccessor(archiveURL: sourceURL, resolveNumberedVolume: !usedFallbackScan)
        try accessor.configureVolumes(totalDisks: totalDisks, allowMissingParts: true)
        defer { accessor.closeAll() }

        let fm = FileManager.default
        let stageDir = try ArchiveOutputTransaction.makeStage(for: destinationURL)
        defer { try? fm.removeItem(at: stageDir) }
        let stagedZip = stageDir.appendingPathComponent("recovered.zip")

        var recoveredEntries: [ArchiveEntry] = []
        var unrecoverable: [ZipRecoveryFailure] = []
        var seenPaths: Set<String> = []
        var recoveredSpans: [Range<UInt64>] = []
        var scannedCount = 0
        var cdEntries: [ZipWriter.CentralDirEntry] = []
        var sink: ZipVolumeSink? = nil
        var abortSink = true
        defer {
            if abortSink {
                sink?.abortCleanup()
            }
        }

        let total = max(1, candidateRecords.count)
        for (idx, record) in candidateRecords.enumerated() {
            try controller?.checkpoint()
            if usedFallbackScan, record.diskNumberStart == 0,
               recoveredSpans.contains(where: { $0.contains(record.localHeaderOffset) }) {
                continue
            }

            let entry = ZipReader.makeEntry(from: record, encoding: encoding)
            progress?(OperationProgress(
                fractionCompleted: Double(idx) / Double(total),
                currentItem: entry.path,
                processedBytes: UInt64(idx),
                totalBytes: UInt64(total)
            ))

            guard !entry.path.isEmpty else { continue }
            if seenPaths.contains(entry.path) {
                continue
            }
            scannedCount += 1

            let cleanPathSegments = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            if cleanPathSegments.contains("..") || cleanPathSegments.contains(".") {
                unrecoverable.append(ZipRecoveryFailure(
                    entryPath: entry.path,
                    reason: BoltZipError.pathTraversalDetected(entry.path).localizedDescription
                ))
                continue
            }

            let fallbackEndOffset: UInt64? = {
                guard usedFallbackScan, record.diskNumberStart == 0 else { return nil }
                let headerLen = UInt64(30 + record.rawPathBytes.count + record.extraData.count)
                guard let payloadStart = try? ArchiveByteCount.checkedSum(record.localHeaderOffset, headerLen),
                      let payloadEnd = try? ArchiveByteCount.checkedSum(payloadStart, record.compressedSize),
                      payloadEnd > record.localHeaderOffset else {
                    return nil
                }
                return payloadEnd
            }()

            if entry.isDirectory {
                do {
                    let (lh, _, _) = try accessor.readSpanning(
                        disk: Int(record.diskNumberStart),
                        offset: record.localHeaderOffset,
                        length: 4
                    )
                    guard ZipBinary.readUInt32LE(lh, at: 0) == ZipSignature.localFileHeader else {
                        throw BoltZipError.invalidArchive(BoltCoreLocalization.t(
                            "本地文件头签名损坏", "本機檔案標頭簽章損毀",
                            "Corrupted local file header signature", "ローカルファイルヘッダのシグネチャが破損しています"
                        ))
                    }
                    if sink == nil {
                        sink = try ZipVolumeSink(outputURL: stagedZip, splitLimit: nil)
                    }
                    let pathEncoded = FilenameEncoding.encode(entry.path, option: .utf8)
                    let cd = try ZipWriter.copyRawRecord(
                        record,
                        rawPathBytes: pathEncoded.data,
                        hasUTF8Flag: pathEncoded.isUTF8,
                        reader: reader,
                        accessor: accessor,
                        sink: sink!
                    )
                    cdEntries.append(cd)
                    recoveredEntries.append(entry)
                    seenPaths.insert(entry.path)
                    if let fallbackEndOffset {
                        recoveredSpans.append(record.localHeaderOffset..<fallbackEndOffset)
                    }
                } catch {
                    unrecoverable.append(ZipRecoveryFailure(entryPath: entry.path, reason: recoveryReason(for: error)))
                }
                continue
            }

            do {
                try reader.verifyPayloadIntegrity(record: record, entryPath: entry.path, accessor: accessor, password: password)
                if sink == nil {
                    sink = try ZipVolumeSink(outputURL: stagedZip, splitLimit: nil)
                }
                let pathEncoded = FilenameEncoding.encode(entry.path, option: .utf8)
                let cd = try ZipWriter.copyRawRecord(
                    record,
                    rawPathBytes: pathEncoded.data,
                    hasUTF8Flag: pathEncoded.isUTF8,
                    reader: reader,
                    accessor: accessor,
                    sink: sink!
                )
                cdEntries.append(cd)
                recoveredEntries.append(entry)
                seenPaths.insert(entry.path)
                if let fallbackEndOffset {
                    recoveredSpans.append(record.localHeaderOffset..<fallbackEndOffset)
                }
            } catch BoltZipError.cancelled {
                throw BoltZipError.cancelled
            } catch {
                unrecoverable.append(ZipRecoveryFailure(entryPath: entry.path, reason: recoveryReason(for: error)))
            }
        }

        if let activeSink = sink, !recoveredEntries.isEmpty {
            try ZipWriter.finishCentralDirectory(entries: cdEntries, comment: comment, sink: activeSink)
            _ = try activeSink.finalizeAll()
            abortSink = false
            try ArchiveOutputTransaction.publish([stagedZip], to: [destinationURL])
            progress?(OperationProgress(
                fractionCompleted: 1.0,
                currentItem: destinationURL.lastPathComponent,
                processedBytes: UInt64(total),
                totalBytes: UInt64(total)
            ))
            return ZipRecoveryReport(
                sourceURL: sourceURL,
                recoveredArchiveURL: destinationURL,
                totalScannedCount: scannedCount,
                recoveredEntries: recoveredEntries,
                unrecoverableEntries: unrecoverable,
                usedLocalHeaderFallbackScan: usedFallbackScan,
                elapsedSeconds: CFAbsoluteTimeGetCurrent() - start
            )
        }

        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: sourceURL.lastPathComponent))
        return ZipRecoveryReport(
            sourceURL: sourceURL,
            recoveredArchiveURL: nil,
            totalScannedCount: scannedCount,
            recoveredEntries: [],
            unrecoverableEntries: unrecoverable,
            usedLocalHeaderFallbackScan: usedFallbackScan,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start
        )
    }

    private static func recoveryReason(for error: any Error) -> String {
        if case BoltZipError.passwordRequired = error {
            return BoltCoreLocalization.t(
                "已加密且未提供密码",
                "已加密且未提供密碼",
                "Encrypted entry — password required",
                "暗号化された項目です（パスワードが必要です）"
            )
        }
        if case BoltZipError.wrongPassword = error {
            return BoltCoreLocalization.t(
                "密码错误或密钥校验失败",
                "密碼錯誤或金鑰驗證失敗",
                "Incorrect password or HMAC verification failed",
                "パスワードが間違っているか HMAC 検証に失敗しました"
            )
        }
        return error.localizedDescription
    }

    private static func scanLocalFileHeaders(
        at url: URL,
        controller: ArchiveTaskController?
    ) throws -> [ZipRecord] {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= 30 else { return [] }

        let chunkSize = 4 * 1024 * 1024
        let overlap = 65536 + 128
        var filePos: UInt64 = 0
        var lastConsumedOffset: UInt64 = 0
        var records: [ZipRecord] = []

        while filePos < fileSize {
            try controller?.checkpoint()
            try fh.seek(toOffset: filePos)
            let window = try fh.read(upToCount: chunkSize + overlap) ?? Data()
            guard window.count >= 30 else { break }

            let searchLimit = (filePos + UInt64(window.count) < fileSize)
                ? max(0, window.count - overlap)
                : window.count - 30
            var i = 0
            while i <= searchLimit {
                if window[i] == 0x50, window[i + 1] == 0x4B, window[i + 2] == 0x03, window[i + 3] == 0x04 {
                    let absOffset = filePos + UInt64(i)
                    if absOffset < lastConsumedOffset {
                        i += 1
                        continue
                    }
                    if let parsed = tryParseCandidate(at: absOffset, fh: fh, fileSize: fileSize) {
                        records.append(parsed.record)
                        if let advance = parsed.advanceToOffset, advance > absOffset {
                            lastConsumedOffset = advance
                        }
                    }
                }
                i += 1
            }

            if filePos + UInt64(window.count) >= fileSize {
                break
            }
            filePos += UInt64(chunkSize)
        }
        return records
    }

    private static func tryParseCandidate(
        at offset: UInt64,
        fh: FileHandle,
        fileSize: UInt64
    ) -> (record: ZipRecord, advanceToOffset: UInt64?)? {
        guard offset + 30 <= fileSize else { return nil }
        do {
            try fh.seek(toOffset: offset)
            guard let lh = try fh.read(upToCount: 30), lh.count == 30 else { return nil }
            let flags = ZipBinary.readUInt16LE(lh, at: 6)
            let method = ZipBinary.readUInt16LE(lh, at: 8)
            let dosTime = ZipBinary.readUInt16LE(lh, at: 10)
            let dosDate = ZipBinary.readUInt16LE(lh, at: 12)
            var crc = ZipBinary.readUInt32LE(lh, at: 14)
            let comp32 = ZipBinary.readUInt32LE(lh, at: 18)
            let uncomp32 = ZipBinary.readUInt32LE(lh, at: 22)
            let nameLen = Int(ZipBinary.readUInt16LE(lh, at: 26))
            let extraLen = Int(ZipBinary.readUInt16LE(lh, at: 28))

            guard nameLen > 0, nameLen <= 4096, offset + 30 + UInt64(nameLen) + UInt64(extraLen) <= fileSize else {
                return nil
            }
            guard let rawPath = try fh.read(upToCount: nameLen), rawPath.count == nameLen, !rawPath.contains(0) else {
                return nil
            }
            let extraData = extraLen > 0 ? (try fh.read(upToCount: extraLen) ?? Data()) : Data()
            guard extraData.count == extraLen else { return nil }

            let extraParsed = ZipBinary.parseExtraFields(
                extraData,
                rawPathBytes: rawPath,
                compressedSize32: comp32,
                uncompressedSize32: uncomp32,
                offset32: UInt32(min(offset, UInt64(UInt32.max))),
                disk32: 0
            )
            var compSize = extraParsed.compressedSize
            var uncompSize = extraParsed.uncompressedSize
            let payloadStart = offset + 30 + UInt64(nameLen) + UInt64(extraLen)

            var advanceTo: UInt64? = nil
            if (flags & 0x0008) != 0 && compSize == 0 && uncompSize == 0 && crc == 0 {
                if let dd = scanForDataDescriptor(from: payloadStart, fh: fh, fileSize: fileSize) {
                    crc = dd.crc32
                    compSize = dd.compressedSize
                    uncompSize = dd.uncompressedSize
                    advanceTo = payloadStart + compSize + dd.descriptorLength
                }
            }

            if payloadStart + compSize > fileSize {
                if payloadStart < fileSize {
                    compSize = fileSize - payloadStart
                } else {
                    compSize = 0
                }
            }

            let isDir = rawPath.last == UInt8(ascii: "/")
            let extAttrs: UInt32 = isDir ? ((0o040755 << 16) | 0x10) : (0o100644 << 16)

            let record = ZipRecord(
                rawPathBytes: rawPath,
                flags: flags,
                compressionMethod: method,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                diskNumberStart: 0,
                localHeaderOffset: offset,
                externalAttributes: extAttrs,
                extraData: extraData,
                commentData: Data(),
                unicodeExtraPath: extraParsed.unicodePath,
                extendedTimestamp: extraParsed.mtime,
                aesExtra: extraParsed.aes
            )
            return (record, advanceTo)
        } catch {
            return nil
        }
    }

    private static func scanForDataDescriptor(
        from payloadStart: UInt64,
        fh: FileHandle,
        fileSize: UInt64
    ) -> (crc32: UInt32, compressedSize: UInt64, uncompressedSize: UInt64, descriptorLength: UInt64)? {
        let maxScan = min(fileSize - payloadStart, 32 * 1024 * 1024)
        let chunkSize = 512 * 1024
        var scanned: UInt64 = 0
        let overlap = 24

        while scanned < maxScan {
            do {
                try fh.seek(toOffset: payloadStart + scanned)
                let toRead = Int(min(UInt64(chunkSize + overlap), maxScan - scanned))
                guard let buf = try fh.read(upToCount: toRead), buf.count >= 16 else { break }

                var i = 0
                while i + 16 <= buf.count {
                    if buf[i] == 0x50 && buf[i + 1] == 0x4B && buf[i + 2] == 0x07 && buf[i + 3] == 0x08 {
                        let expectedComp = scanned + UInt64(i)
                        let crc = ZipBinary.readUInt32LE(buf, at: i + 4)
                        let c32 = UInt64(ZipBinary.readUInt32LE(buf, at: i + 8))
                        if c32 == expectedComp {
                            let u32 = UInt64(ZipBinary.readUInt32LE(buf, at: i + 12))
                            return (crc, c32, u32, 16)
                        }
                        if i + 24 <= buf.count {
                            let c64 = ZipBinary.readUInt64LE(buf, at: i + 8)
                            if c64 == expectedComp {
                                let u64 = ZipBinary.readUInt64LE(buf, at: i + 16)
                                return (crc, c64, u64, 24)
                            }
                        }
                    }
                    i += 1
                }
                if scanned + UInt64(buf.count) >= maxScan { break }
                scanned += UInt64(chunkSize)
            } catch {
                return nil
            }
        }
        return nil
    }
}
