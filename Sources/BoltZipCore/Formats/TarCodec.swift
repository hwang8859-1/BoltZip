import Foundation

public enum TarCodec {
    private static let blockSize = 512

    public static func listEntries(at url: URL, format: ArchiveFormat) throws -> [ArchiveEntry] {
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            return try listSingleStream(at: url, format: format)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            var entries: [ArchiveEntry] = []
            try withUncompressedTarFile(at: url, format: format) { tarURL in
                entries = try streamScanTar(at: tarURL, methodLabel: format.defaultAlgorithm.shortName, computeCRC: true)
            }
            return entries
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    /// Extracts a single entry payload directly to a file URL on disk without buffering the entire payload in memory.
    public static func extractSingleEntryToFile(
        at url: URL,
        format: ArchiveFormat,
        path: String,
        to destinationFileURL: URL,
        controller: ArchiveTaskController? = nil
    ) throws {
        try controller?.checkpoint()
        let fm = FileManager.default
        try fm.createDirectory(at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let root = destinationFileURL.deletingLastPathComponent()
        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: destinationFileURL, under: root)
        defer { try? fm.removeItem(at: stage) }
        let stagedItem = stage.appendingPathComponent("payload")

        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            let entries = try listSingleStream(at: url, format: format)
            guard let first = entries.first else {
                throw BoltZipError.entryNotFound(path)
            }
            let targetNorm = ArchiveEntry.normalizePath(path, isDirectory: path.hasSuffix("/"))
            guard first.path == targetNorm || targetNorm == url.lastPathComponent else {
                throw BoltZipError.entryNotFound(path)
            }
            try decompressStreamFile(from: url, to: stagedItem, format: format, controller: controller)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            let target = ArchiveEntry.normalizePath(path, isDirectory: path.hasSuffix("/"))
            var found = false
            try withUncompressedTarFile(at: url, format: format, controller: controller) { tarURL in
                try iterateTarHeaders(at: tarURL, methodLabel: "TAR", computeCRC: false, controller: controller) { info, fh in
                    guard info.entry.path == target else { return true }
                    found = true
                    if info.entry.isSymbolicLink {
                        let data = Data(info.symlinkTarget.utf8)
                        try data.write(to: stagedItem, options: .atomic)
                    } else if info.entry.isDirectory {
                        try fm.createDirectory(at: stagedItem, withIntermediateDirectories: true)
                    } else {
                        try fh.seek(toOffset: info.payloadOffset)
                        fm.createFile(atPath: stagedItem.path, contents: nil)
                        let outHandle = try FileHandle(forWritingTo: stagedItem)
                        var closeOut = true
                        defer { if closeOut { try? outHandle.close() } }
                        var rem = info.payloadSize
                        while rem > 0 {
                            try controller?.checkpoint()
                            let want = Int(min(UInt64(BoltConcurrency.streamChunkSize), rem))
                            let chunk = try fh.read(upToCount: want) ?? Data()
                            guard !chunk.isEmpty else { throw BoltZipError.invalidArchive("Truncated TAR entry") }
                            try outHandle.write(contentsOf: chunk)
                            rem -= UInt64(chunk.count)
                        }
                        try outHandle.close()
                        closeOut = false
                    }
                    return false
                }
            }
            if !found {
                throw BoltZipError.entryNotFound(path)
            }
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
        try ArchiveExtractionDestination.commitExtractedItem(stagedItem, to: destinationFileURL, under: root,
                                                  policy: .overwrite,
                                                  protectedSourcePaths: [ArchiveExtractionDestination.pathKey(url)],
                                                  controller: controller)
    }

    public static func readEntryData(at url: URL, format: ArchiveFormat, path: String) throws -> Data {
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            let fm = FileManager.default
            let tmpURL = fm.temporaryDirectory.appendingPathComponent("boltzip-sread-\(UUID().uuidString).tmp")
            defer { try? fm.removeItem(at: tmpURL) }
            try decompressStreamFile(from: url, to: tmpURL, format: format)
            return try Data(contentsOf: tmpURL, options: .mappedIfSafe)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            let target = ArchiveEntry.normalizePath(path, isDirectory: path.hasSuffix("/"))
            var foundData: Data?
            try withUncompressedTarFile(at: url, format: format) { tarURL in
                foundData = try readSingleEntryFromTarFile(at: tarURL, targetPath: target)
            }
            guard let data = foundData else {
                throw BoltZipError.entryNotFound(path)
            }
            return data
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    public static func extract(
        at url: URL,
        format: ArchiveFormat,
        to destinationURL: URL,
        selectedPaths: Set<String>?,
        stripMacJunk: Bool,
        overwritePolicy: OverwritePolicy,
        restoreSymlinks: Bool,
        topLevelDirRenameMap: [String: String],
        totalExpectedBytes: UInt64,
        protectedSourcePaths: Set<String> = [],
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let fm = FileManager.default
        let protected = protectedSourcePaths.union([ArchiveExtractionDestination.pathKey(url)])

        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            let entries = try listSingleStream(at: url, format: format)
            guard let first = entries.first else { return }
            if stripMacJunk && MacJunkFilter.isJunk(path: first.path) { return }
            if let sel = selectedPaths, !sel.isEmpty,
               !ArchiveExtractionDestination.pathMatchesSelection(first.path, selectedPaths: sel) {
                return
            }

            let outputPath = ArchiveExtractionDestination.remapTopLevelFolder(in: first.path, renameMap: topLevelDirRenameMap)
            let initialDest = try ArchiveExtractionDestination.safeDestinationURL(for: outputPath, under: destinationURL)
            guard let targetURL = try ArchiveExtractionDestination.prepareExtractTargetURL(
                initialURL: initialDest,
                under: destinationURL,
                policy: overwritePolicy
            ) else {
                return
            }

            let stage = try ArchiveExtractionDestination.makeExtractionStage(near: targetURL, under: destinationURL)
            defer { try? fm.removeItem(at: stage) }
            let stageURL = stage.appendingPathComponent("payload")
            try decompressStreamFile(from: url, to: stageURL, format: format, controller: controller) { readBytes, totalComp in
                let frac = totalComp > 0 ? min(0.99, Double(readBytes) / Double(totalComp)) : 0.2
                progress?(OperationProgress(
                    fractionCompleted: frac,
                    currentItem: first.path,
                    processedBytes: totalExpectedBytes > 0 ? UInt64(Double(totalExpectedBytes) * frac) : readBytes,
                    totalBytes: totalExpectedBytes
                ))
            }

            try ArchiveExtractionDestination.commitExtractedItem(stageURL, to: targetURL, under: destinationURL,
                                                      policy: overwritePolicy, protectedSourcePaths: protected, controller: controller)
            let attrs: [FileAttributeKey: Any] = [
                .modificationDate: first.modifiedDate,
                .posixPermissions: NSNumber(value: first.permissions)
            ]
            try? fm.setAttributes(attrs, ofItemAtPath: targetURL.path)

        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            try withUncompressedTarFile(at: url, format: format, controller: controller, progress: { readBytes, totalCompressed in
                let curBytes = totalExpectedBytes > 0 && totalCompressed > 0
                    ? UInt64(Double(totalExpectedBytes) * 0.4 * (Double(readBytes) / Double(totalCompressed)))
                    : readBytes
                let frac = totalCompressed > 0 ? 0.4 * (Double(readBytes) / Double(totalCompressed)) : 0.1
                progress?(OperationProgress(
                    fractionCompleted: frac,
                    currentItem: url.lastPathComponent,
                    processedBytes: curBytes,
                    totalBytes: totalExpectedBytes > 0 ? totalExpectedBytes : totalCompressed
                ))
            }) { tarURL in
                try streamExtractTarFile(
                    at: tarURL,
                    to: destinationURL,
                    selectedPaths: selectedPaths,
                    stripMacJunk: stripMacJunk,
                    overwritePolicy: overwritePolicy,
                    restoreSymlinks: restoreSymlinks,
                    topLevelDirRenameMap: topLevelDirRenameMap,
                    baseFrac: format == .tar ? 0.0 : 0.4,
                    totalExpectedBytes: totalExpectedBytes,
                    protectedSourcePaths: protected,
                    controller: controller,
                    progress: progress
                )
            }

        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    public static func create(
        from inputURLs: [URL],
        to outputURL: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let items = try ArchiveInputCollector.collect(
            from: inputURLs,
            excludeMacJunk: options.excludeMacJunk,
            preserveSymlinks: options.preserveSymlinks,
            excluding: [outputURL], controller: controller
        )
        let totalBytes = items.reduce(UInt64(0)) { $0 + $1.fileSize }
        var stagedBytes: UInt64 = 0
        let isRawTar = (options.format == .tar)

        let fm = FileManager.default
        let outputStage = try ArchiveOutputTransaction.makeStage(for: outputURL)
        defer { try? fm.removeItem(at: outputStage) }
        let tempTarURL = outputStage.appendingPathComponent("payload.tar")

        fm.createFile(atPath: tempTarURL.path, contents: nil)
        let tarHandle = try FileHandle(forWritingTo: tempTarURL)
        var shouldCloseTar = true
        defer { if shouldCloseTar { try? tarHandle.close() } }

        for item in items {
            try controller?.checkpoint()
            let stageFrac = totalBytes > 0 ? Double(stagedBytes) / Double(totalBytes) : 0
            progress?(OperationProgress(
                fractionCompleted: isRawTar ? stageFrac * 0.95 : stageFrac * 0.25,
                currentItem: item.archivePath,
                processedBytes: isRawTar ? stagedBytes : UInt64(Double(totalBytes) * (stageFrac * 0.25)),
                totalBytes: totalBytes
            ))
            try streamAppendTarEntry(to: tarHandle, item: item, controller: controller) { chunkBytes in
                let cur = min(totalBytes, stagedBytes + chunkBytes)
                let curFrac = totalBytes > 0 ? Double(cur) / Double(totalBytes) : 0
                progress?(OperationProgress(
                    fractionCompleted: isRawTar ? curFrac * 0.95 : curFrac * 0.25,
                    currentItem: item.archivePath,
                    processedBytes: cur,
                    totalBytes: totalBytes
                ))
            }
            stagedBytes += item.fileSize
        }

        // Two 512-byte zero blocks terminate TAR stream
        try tarHandle.write(contentsOf: Data(count: blockSize * 2))
        try tarHandle.close()
        shouldCloseTar = false
        try controller?.checkpoint()

        if options.format == .tar {
            try ArchiveOutputTransaction.publish([tempTarURL], to: [outputURL])
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent, processedBytes: totalBytes, totalBytes: totalBytes))
            return
        }

        let reportCompressProgress: (UInt64, UInt64) -> Void = { bytesRead, tarTotal in
            let ratio = tarTotal > 0 ? Double(bytesRead) / Double(tarTotal) : 1.0
            let frac = min(0.99, 0.25 + 0.75 * ratio)
            let estBytes = totalBytes > 0 ? UInt64(Double(totalBytes) * frac) : bytesRead
            progress?(OperationProgress(
                fractionCompleted: frac,
                currentItem: outputURL.lastPathComponent,
                processedBytes: estBytes,
                totalBytes: totalBytes > 0 ? totalBytes : tarTotal
            ))
        }

        let workers = BoltConcurrency.resolvedWorkerCount(override: options.workerCount)
        let stageCompURL = outputStage.appendingPathComponent("archive")

        switch options.format {
        case .tarGz:
            try CompressionCodec.compressFile(sourceURL: tempTarURL, destinationURL: stageCompURL, algorithm: .deflate, gzipContainer: true, level: options.level, allowMultiThread: true, workerCount: workers, controller: controller, progress: reportCompressProgress)
        case .tarZst:
            try CompressionCodec.compressFile(sourceURL: tempTarURL, destinationURL: stageCompURL, algorithm: .zstd, gzipContainer: false, level: options.level, allowMultiThread: true, workerCount: workers, controller: controller, progress: reportCompressProgress)
        case .tarXz:
            try CompressionCodec.compressFile(sourceURL: tempTarURL, destinationURL: stageCompURL, algorithm: .xz, gzipContainer: false, level: options.level, allowMultiThread: true, workerCount: workers, controller: controller, progress: reportCompressProgress)
        case .tarBz2:
            try CompressionCodec.compressFile(sourceURL: tempTarURL, destinationURL: stageCompURL, algorithm: .bzip2, gzipContainer: false, level: options.level, allowMultiThread: true, workerCount: workers, controller: controller, progress: reportCompressProgress)
        case .tarLz4:
            try CompressionCodec.compressFile(sourceURL: tempTarURL, destinationURL: stageCompURL, algorithm: .lz4, gzipContainer: false, level: options.level, allowMultiThread: true, workerCount: workers, controller: controller, progress: reportCompressProgress)
        default:
            throw BoltZipError.unsupportedFormat(options.format.displayName)
        }

        try controller?.checkpoint()
        try ArchiveOutputTransaction.publish([stageCompURL], to: [outputURL])
        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent, processedBytes: totalBytes, totalBytes: totalBytes))
    }

    public static func testIntegrity(at url: URL, format: ArchiveFormat) throws -> IntegrityReport {
        let start = CFAbsoluteTimeGetCurrent()
        let isRawTar = (format == .tar)
        let isSingleStream: Bool
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4: isSingleStream = true
        default: isSingleStream = false
        }

        let entries: [ArchiveEntry]
        if isSingleStream {
            entries = try listSingleStream(at: url, format: format)
        } else {
            var scanned: [ArchiveEntry] = []
            try withUncompressedTarFile(at: url, format: format) { tarURL in
                scanned = try streamScanTar(at: tarURL, methodLabel: format.defaultAlgorithm.shortName, computeCRC: false, verifyDataRead: true)
            }
            entries = scanned
        }

        let okDetail: String
        if isSingleStream {
            okDetail = BoltCoreLocalization.t(
                "容器流解码与 CRC 校验通过",
                "容器串流解碼與 CRC 驗證通過",
                "Container stream decode & CRC passed",
                "コンテナストリームのデコードと CRC 検証に合格"
            )
        } else if isRawTar {
            okDetail = BoltCoreLocalization.t(
                "TAR 归档结构读取通过（TAR 格式无内置校验和）",
                "TAR 封存檔結構讀取通過（TAR 格式無內建校驗和）",
                "TAR structure readable (format has no built-in checksums)",
                "TAR 構造の読み込み正常（TAR 形式にチェックサムはありません）"
            )
        } else {
            okDetail = BoltCoreLocalization.t(
                "压缩流校验与 TAR 结构读取通过（TAR 条目无内置校验和）",
                "壓縮串流驗證與 TAR 結構讀取通過（TAR 項目無內建校驗和）",
                "Compressed stream verified & TAR structure OK (no per-entry checksum)",
                "圧縮ストリーム検証および TAR 構造正常（項目別チェックサムなし）"
            )
        }
        let results = entries.map {
            IntegrityEntryResult(path: $0.path, status: .passed, detail: okDetail)
        }
        return IntegrityReport(
            archiveName: url.lastPathComponent,
            totalEntries: results.count,
            passedCount: results.count,
            failedCount: 0,
            skippedEncryptedCount: 0,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
            results: results
        )
    }

    // MARK: - Internal TAR & Stream Codecs

    private static func streamCodecParams(for format: ArchiveFormat) throws -> (algorithm: CompressionAlgorithm, gzip: Bool) {
        switch format {
        case .gz, .tarGz: return (.deflate, true)
        case .zst, .tarZst: return (.zstd, false)
        case .xz, .tarXz: return (.xz, false)
        case .bz2, .tarBz2: return (.bzip2, false)
        case .lz4, .tarLz4: return (.lz4, false)
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    private static func decompressStreamFile(
        from sourceURL: URL,
        to destinationURL: URL,
        format: ArchiveFormat,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws {
        let (algo, gzip) = try streamCodecParams(for: format)
        try CompressionCodec.decompressFile(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            algorithm: algo,
            gzipContainer: gzip,
            controller: controller,
            progress: progress
        )
    }

    internal static func withUncompressedTarFile(
        at url: URL,
        format: ArchiveFormat,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil,
        body: (URL) throws -> Void
    ) throws {
        if format == .tar {
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value) ?? 0
            progress?(size, size)
            try body(url)
            return
        }
        let fm = FileManager.default
        let tempTarURL = fm.temporaryDirectory.appendingPathComponent("boltzip-untar-\(UUID().uuidString).tar")
        defer { try? fm.removeItem(at: tempTarURL) }
        try decompressStreamFile(from: url, to: tempTarURL, format: format, controller: controller, progress: progress)
        try body(tempTarURL)
    }

    private static func listSingleStream(at url: URL, format: ArchiveFormat) throws -> [ArchiveEntry] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let compressedSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()

        var innerName = url.deletingPathExtension().lastPathComponent
        if format == .gz {
            let fh = try FileHandle(forReadingFrom: url)
            let head = try fh.read(upToCount: 4096) ?? Data()
            try? fh.close()
            if let gzName = parseGzipOriginalFilename(head), !gzName.isEmpty {
                innerName = gzName
            }
        }
        if innerName == url.lastPathComponent || innerName.isEmpty {
            innerName = url.lastPathComponent + ".out"
        }

        let (algo, gzip) = try streamCodecParams(for: format)
        let verified = try CompressionCodec.verifyFile(sourceURL: url, algorithm: algo, gzipContainer: gzip)
        return [
            ArchiveEntry(
                path: innerName,
                isDirectory: false,
                uncompressedSize: verified.uncompressedSize,
                compressedSize: compressedSize,
                compressionMethodName: format.defaultAlgorithm.shortName,
                crc32: verified.crc32,
                modifiedDate: modDate
            )
        ]
    }

    private static func parseGzipOriginalFilename(_ data: Data) -> String? {
        guard data.count >= 10, data[0] == 0x1F, data[1] == 0x8B, data[2] == 0x08 else { return nil }
        let flg = data[3]
        var pos = 10
        if (flg & 0x04) != 0 { // FEXTRA
            guard pos + 2 <= data.count else { return nil }
            let xlen = Int(data[pos]) | (Int(data[pos + 1]) << 8)
            pos += 2 + xlen
        }
        if (flg & 0x08) != 0 { // FNAME
            guard pos < data.count else { return nil }
            if let end = data[pos...].firstIndex(of: 0) {
                let nameData = data.subdata(in: pos..<end)
                return String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1)
            }
        }
        return nil
    }

    private struct StreamTarHeaderInfo {
        let entry: ArchiveEntry
        let symlinkTarget: String
        let payloadOffset: UInt64
        let payloadSize: UInt64
        let paddedSize: UInt64
    }

    private static func iterateTarHeaders(
        at tarURL: URL,
        methodLabel: String,
        computeCRC: Bool,
        controller: ArchiveTaskController? = nil,
        visitor: (StreamTarHeaderInfo, FileHandle) throws -> Bool
    ) throws {
        let fh = try FileHandle(forReadingFrom: tarURL)
        defer { try? fh.close() }
        let attrs = try FileManager.default.attributesOfItem(atPath: tarURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        var offset: UInt64 = 0
        var nextPaxAttributes: [String: String] = [:]
        var nextGnuLongName: String?
        var nextGnuLongLink: String?

        while offset + UInt64(blockSize) <= fileSize {
            try controller?.checkpoint()
            try fh.seek(toOffset: offset)
            guard let header = try fh.read(upToCount: blockSize), header.count == blockSize else {
                break
            }
            offset += UInt64(blockSize)

            if header.allSatisfy({ $0 == 0 }) {
                break
            }

            let rawName = readTarString(header, start: 0, length: 100)
            let modeVal = readTarOctal(header, start: 100, length: 8)
            let sizeVal = readTarOctal(header, start: 124, length: 12)
            let mtimeVal = readTarOctal(header, start: 136, length: 12)
            let typeFlag = header[156]
            let rawLinkName = readTarString(header, start: 157, length: 100)
            let prefix = readTarString(header, start: 345, length: 155)

            let resolvedSize = nextPaxAttributes["size"].flatMap(UInt64.init) ?? sizeVal
            guard resolvedSize <= fileSize - offset else {
                throw BoltZipError.invalidArchive(BoltCoreLocalization.t("TAR 数据块提前结束", "TAR 資料區塊提前結束", "Unexpected EOF in TAR data block", "TAR データブロックが途中で終了しました"))
            }

            let paddedLen = ((resolvedSize + UInt64(blockSize) - 1) / UInt64(blockSize)) * UInt64(blockSize)

            // PAX extended header ('x'), GNU long name ('L'), GNU long link ('K')
            if typeFlag == UInt8(ascii: "x") || typeFlag == UInt8(ascii: "g") || typeFlag == UInt8(ascii: "L") || typeFlag == UInt8(ascii: "K") {
                if typeFlag == UInt8(ascii: "x") {
                    let payload = try fh.read(upToCount: Int(resolvedSize)) ?? Data()
                    nextPaxAttributes = parsePAXPayload(payload)
                } else if typeFlag == UInt8(ascii: "L") {
                    let payload = try fh.read(upToCount: Int(resolvedSize)) ?? Data()
                    nextGnuLongName = String(data: payload, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                } else if typeFlag == UInt8(ascii: "K") {
                    let payload = try fh.read(upToCount: Int(resolvedSize)) ?? Data()
                    nextGnuLongLink = String(data: payload, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                }
                offset = min(fileSize, offset + paddedLen)
                continue
            }

            let basePath = prefix.isEmpty ? rawName : "\(prefix)/\(rawName)"
            let resolvedPath = nextPaxAttributes["path"] ?? nextGnuLongName ?? basePath
            let resolvedLinkTarget = nextPaxAttributes["linkpath"] ?? nextGnuLongLink ?? rawLinkName
            let resolvedMtime = nextPaxAttributes["mtime"].flatMap(Double.init) ?? Double(mtimeVal)

            nextPaxAttributes.removeAll()
            nextGnuLongName = nil
            nextGnuLongLink = nil

            let isDir = typeFlag == UInt8(ascii: "5") || resolvedPath.hasSuffix("/")
            let isSymlink = typeFlag == UInt8(ascii: "2")

            var crc: UInt32 = 0
            if computeCRC && !isDir && !isSymlink && resolvedSize > 0 {
                try fh.seek(toOffset: offset)
                var rem = resolvedSize
                while rem > 0 {
                    try controller?.checkpoint()
                    let want = Int(min(UInt64(BoltConcurrency.streamChunkSize), rem))
                    let chunk = try fh.read(upToCount: want) ?? Data()
                    if chunk.isEmpty { break }
                    crc = CompressionCodec.crc32(chunk, initial: crc)
                    rem -= UInt64(chunk.count)
                }
            } else if isSymlink && computeCRC {
                crc = CompressionCodec.crc32(Data(resolvedLinkTarget.utf8))
            }

            let entry = ArchiveEntry(
                path: resolvedPath,
                isDirectory: isDir,
                isSymbolicLink: isSymlink,
                uncompressedSize: isDir ? 0 : (isSymlink ? UInt64(resolvedLinkTarget.utf8.count) : resolvedSize),
                compressedSize: isDir ? 0 : resolvedSize,
                compressionMethodName: methodLabel,
                crc32: crc,
                modifiedDate: Date(timeIntervalSince1970: resolvedMtime),
                permissions: UInt16(modeVal & 0o7777)
            )
            let info = StreamTarHeaderInfo(
                entry: entry,
                symlinkTarget: resolvedLinkTarget,
                payloadOffset: offset,
                payloadSize: isDir ? 0 : resolvedSize,
                paddedSize: paddedLen
            )
            let shouldContinue = try visitor(info, fh)
            offset = min(fileSize, offset + paddedLen)
            if !shouldContinue { break }
        }
    }

    internal static func streamScanTar(
        at tarURL: URL,
        methodLabel: String,
        computeCRC: Bool,
        verifyDataRead: Bool = false
    ) throws -> [ArchiveEntry] {
        var result: [ArchiveEntry] = []
        try iterateTarHeaders(at: tarURL, methodLabel: methodLabel, computeCRC: computeCRC) { info, fh in
            if verifyDataRead && !info.entry.isDirectory && !info.entry.isSymbolicLink && info.payloadSize > 0 {
                // Probe end of payload to confirm underlying stream wasn't truncated prematurely
                let lastByteOffset = info.payloadOffset + info.payloadSize - 1
                try fh.seek(toOffset: lastByteOffset)
                guard let tailByte = try fh.read(upToCount: 1), tailByte.count == 1 else {
                    throw BoltZipError.corruptedEntry(
                        entry: info.entry.path,
                        detail: BoltCoreLocalization.t("TAR 条目数据区提前截断", "TAR 項目資料區提前截斷", "Unexpected EOF in TAR entry payload", "TAR 項目のデータ領域が途中で切れています")
                    )
                }
            }
            result.append(info.entry)
            return true
        }
        return result
    }

    private static func readSingleEntryFromTarFile(at tarURL: URL, targetPath: String) throws -> Data? {
        var found: Data?
        try iterateTarHeaders(at: tarURL, methodLabel: "TAR", computeCRC: false) { info, fh in
            guard info.entry.path == targetPath else { return true }
            if info.entry.isSymbolicLink {
                found = Data(info.symlinkTarget.utf8)
            } else {
                try fh.seek(toOffset: info.payloadOffset)
                found = try fh.read(upToCount: Int(info.payloadSize)) ?? Data()
            }
            return false
        }
        return found
    }

    internal static func streamExtractTarFile(
        at tarURL: URL,
        to destinationURL: URL,
        selectedPaths: Set<String>?,
        stripMacJunk: Bool,
        overwritePolicy: OverwritePolicy,
        restoreSymlinks: Bool,
        topLevelDirRenameMap: [String: String],
        baseFrac: Double,
        totalExpectedBytes: UInt64,
        protectedSourcePaths: Set<String> = [],
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws {
        let fm = FileManager.default
        var processedBytes: UInt64 = 0

        try iterateTarHeaders(at: tarURL, methodLabel: "TAR", computeCRC: false, controller: controller) { info, fh in
            let entry = info.entry
            if stripMacJunk && MacJunkFilter.isJunk(path: entry.path) {
                return true
            }
            if let sel = selectedPaths, !sel.isEmpty,
               !ArchiveExtractionDestination.pathMatchesSelection(entry.path, selectedPaths: sel) {
                return true
            }

            let outputPath = ArchiveExtractionDestination.remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
            let initialDest = try ArchiveExtractionDestination.safeDestinationURL(for: outputPath, under: destinationURL)

            if entry.isDirectory {
                try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: initialDest, under: destinationURL)
                try fm.createDirectory(at: initialDest, withIntermediateDirectories: true)
                return true
            }

            if entry.isSymbolicLink {
                if restoreSymlinks {
                    try ArchiveExtractionDestination.createSafeSymlink(
                        at: initialDest,
                        target: info.symlinkTarget,
                        under: destinationURL,
                        overwritePolicy: overwritePolicy,
                        protectedSourcePaths: protectedSourcePaths
                    )
                }
                return true
            }

            guard let targetURL = try ArchiveExtractionDestination.prepareExtractTargetURL(
                initialURL: initialDest,
                under: destinationURL,
                policy: overwritePolicy
            ) else {
                processedBytes += info.payloadSize
                return true
            }

            let stage = try ArchiveExtractionDestination.makeExtractionStage(near: targetURL, under: destinationURL)
            defer { try? fm.removeItem(at: stage) }
            let stagedFile = stage.appendingPathComponent("payload")
            try fh.seek(toOffset: info.payloadOffset)
            fm.createFile(atPath: stagedFile.path, contents: nil)
            let outHandle = try FileHandle(forWritingTo: stagedFile)
            var closeOut = true
            defer { if closeOut { try? outHandle.close() } }

            var rem = info.payloadSize
            while rem > 0 {
                try controller?.checkpoint()
                let want = Int(min(UInt64(BoltConcurrency.streamChunkSize), rem))
                let chunk = try fh.read(upToCount: want) ?? Data()
                guard !chunk.isEmpty else { throw BoltZipError.invalidArchive("Truncated TAR entry") }
                try outHandle.write(contentsOf: chunk)
                rem -= UInt64(chunk.count)
                processedBytes += UInt64(chunk.count)

                let span = 1.0 - baseFrac
                let itemFrac = totalExpectedBytes > 0 ? Double(processedBytes) / Double(totalExpectedBytes) : 0.5
                let overallFrac = min(0.99, baseFrac + span * itemFrac)
                progress?(OperationProgress(
                    fractionCompleted: overallFrac,
                    currentItem: entry.path,
                    processedBytes: processedBytes,
                    totalBytes: totalExpectedBytes
                ))
            }
            try outHandle.close()
            closeOut = false

            let attrs: [FileAttributeKey: Any] = [
                .modificationDate: entry.modifiedDate,
                .posixPermissions: NSNumber(value: entry.permissions)
            ]
            try? fm.setAttributes(attrs, ofItemAtPath: stagedFile.path)
            try ArchiveExtractionDestination.commitExtractedItem(stagedFile, to: targetURL, under: destinationURL,
                                                      policy: overwritePolicy, protectedSourcePaths: protectedSourcePaths, controller: controller)
            return true
        }
    }

    private static func streamAppendTarEntry(
        to handle: FileHandle,
        item: ArchiveInputItem,
        controller: ArchiveTaskController?,
        onChunkProgress: (UInt64) -> Void
    ) throws {
        let path = item.archivePath
        let symlinkTarget = item.symlinkTarget ?? ""
        let payloadSize = (item.isDirectory || item.isSymbolicLink) ? UInt64(0) : item.fileSize

        let needsPAX = path.utf8.count > 100
            || symlinkTarget.utf8.count > 100
            || payloadSize >= 0o77777777777

        if needsPAX {
            var paxBody = Data()
            if path.utf8.count > 100 {
                paxBody.append(paxRecord(key: "path", value: path))
            }
            if item.isSymbolicLink && symlinkTarget.utf8.count > 100 {
                paxBody.append(paxRecord(key: "linkpath", value: symlinkTarget))
            }
            if payloadSize >= 0o77777777777 {
                paxBody.append(paxRecord(key: "size", value: String(payloadSize)))
            }
            let paxName = "PaxHeaders.0/" + String(path.suffix(70))
            let paxHeader = buildUSTARHeader(
                name: paxName,
                mode: 0o644,
                size: UInt64(paxBody.count),
                mtime: UInt64(max(0, item.modifiedDate.timeIntervalSince1970)),
                typeFlag: UInt8(ascii: "x"),
                linkname: ""
            )
            try handle.write(contentsOf: paxHeader)
            try handle.write(contentsOf: paxBody)
            let paxPad = (blockSize - (paxBody.count % blockSize)) % blockSize
            if paxPad > 0 { try handle.write(contentsOf: Data(count: paxPad)) }
        }

        let headerName = String(path.prefix(99))
        let typeFlag: UInt8
        if item.isSymbolicLink {
            typeFlag = UInt8(ascii: "2")
        } else if item.isDirectory {
            typeFlag = UInt8(ascii: "5")
        } else {
            typeFlag = UInt8(ascii: "0")
        }

        let header = buildUSTARHeader(
            name: headerName,
            mode: item.permissions,
            size: payloadSize,
            mtime: UInt64(max(0, item.modifiedDate.timeIntervalSince1970)),
            typeFlag: typeFlag,
            linkname: item.isSymbolicLink ? String(symlinkTarget.prefix(99)) : ""
        )
        try handle.write(contentsOf: header)

        if let fileURL = item.fileURL, !item.isDirectory && !item.isSymbolicLink && payloadSize > 0 {
            let inHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? inHandle.close() }
            var copied: UInt64 = 0
            while copied < payloadSize {
                try controller?.checkpoint()
                let want = Int(min(UInt64(BoltConcurrency.streamChunkSize), payloadSize - copied))
                let chunk = try inHandle.read(upToCount: want) ?? Data()
                if chunk.isEmpty { break }
                try handle.write(contentsOf: chunk)
                copied += UInt64(chunk.count)
                onChunkProgress(copied)
            }
            let remMod = Int(copied % UInt64(blockSize))
            let pad = (blockSize - remMod) % blockSize
            if pad > 0 { try handle.write(contentsOf: Data(count: pad)) }
        }
    }

    private static func buildUSTARHeader(
        name: String,
        mode: UInt16,
        size: UInt64,
        mtime: UInt64,
        typeFlag: UInt8,
        linkname: String
    ) -> Data {
        var hdr = Data(count: blockSize)
        writeTarBytes(&hdr, string: name, offset: 0, maxLen: 100)
        writeTarOctal(&hdr, value: UInt64(mode & 0o7777), offset: 100, length: 8)
        writeTarOctal(&hdr, value: 0, offset: 108, length: 8) // uid
        writeTarOctal(&hdr, value: 0, offset: 116, length: 8) // gid
        writeTarOctal(&hdr, value: size > 0o77777777777 ? 0 : size, offset: 124, length: 12)
        writeTarOctal(&hdr, value: mtime, offset: 136, length: 12)
        for i in 148..<156 { hdr[i] = UInt8(ascii: " ") }
        hdr[156] = typeFlag
        if !linkname.isEmpty {
            writeTarBytes(&hdr, string: linkname, offset: 157, maxLen: 100)
        }
        writeTarBytes(&hdr, string: "ustar", offset: 257, maxLen: 6)
        hdr[263] = UInt8(ascii: "0")
        hdr[264] = UInt8(ascii: "0")

        let checksum = hdr.reduce(0) { $0 + UInt64($1) }
        let chkStr = String(format: "%06llo", checksum)
        let chkBytes = Array(chkStr.utf8)
        for i in 0..<min(6, chkBytes.count) { hdr[148 + i] = chkBytes[i] }
        hdr[154] = 0
        hdr[155] = UInt8(ascii: " ")
        return hdr
    }

    private static func paxRecord(key: String, value: String) -> Data {
        let base = " \(key)=\(value)\n"
        var totalLen = base.utf8.count + 1
        while true {
            let candidate = "\(totalLen)\(base)"
            if candidate.utf8.count == totalLen {
                return Data(candidate.utf8)
            }
            totalLen = candidate.utf8.count
        }
    }

    private static func parsePAXPayload(_ data: Data) -> [String: String] {
        guard let str = String(data: data, encoding: .utf8) else { return [:] }
        var dict: [String: String] = [:]
        for line in str.split(separator: "\n") {
            guard let spaceIdx = line.firstIndex(of: " "),
                  let eqIdx = line[spaceIdx...].firstIndex(of: "=") else { continue }
            let keyStart = line.index(after: spaceIdx)
            let key = String(line[keyStart..<eqIdx])
            let val = String(line[line.index(after: eqIdx)...])
            dict[key] = val
        }
        return dict
    }

    private static func writeTarBytes(_ hdr: inout Data, string: String, offset: Int, maxLen: Int) {
        let bytes = Array(string.utf8.prefix(maxLen))
        for i in 0..<bytes.count { hdr[offset + i] = bytes[i] }
    }

    private static func writeTarOctal(_ hdr: inout Data, value: UInt64, offset: Int, length: Int) {
        let width = length - 1
        let oct = String(value, radix: 8)
        let padded = String(repeating: "0", count: max(0, width - oct.count)) + oct
        let bytes = Array(padded.utf8.suffix(width))
        for i in 0..<bytes.count { hdr[offset + i] = bytes[i] }
        hdr[offset + length - 1] = 0
    }

    private static func readTarString(_ data: Data, start: Int, length: Int) -> String {
        let slice = data.subdata(in: start..<(start + length))
        let trimmed = slice.prefix { $0 != 0 }
        return String(data: Data(trimmed), encoding: .utf8) ?? String(decoding: trimmed, as: UTF8.self)
    }

    private static func readTarOctal(_ data: Data, start: Int, length: Int) -> UInt64 {
        let raw = readTarString(data, start: start, length: length)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return UInt64(raw, radix: 8) ?? 0
    }
}
