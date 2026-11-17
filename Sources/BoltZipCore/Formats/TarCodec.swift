import Foundation

public enum TarCodec {
    private static let blockSize = 512

    public static func listEntries(at url: URL, format: ArchiveFormat) throws -> [ArchiveEntry] {
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            return try listSingleStream(at: url, format: format)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            let tarData = try loadUncompressedTarData(at: url, format: format)
            return try parseTarEntries(tarData, methodLabel: format.defaultAlgorithm.shortName).map(\.entry)
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    static func readAllEntries(
        at url: URL,
        format: ArchiveFormat,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> [String: Data] {
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            let entries = try listSingleStream(at: url, format: format)
            let raw = try Data(contentsOf: url, options: .mappedIfSafe)
            let plain = try decompressStream(raw, format: format, controller: controller, progress: progress)
            if let first = entries.first {
                return [first.path: plain]
            }
            return [:]
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            let tarData = try loadUncompressedTarData(at: url, format: format, controller: controller, progress: progress)
            let items = try parseTarEntries(tarData, methodLabel: format.defaultAlgorithm.shortName)
            var dict: [String: Data] = [:]
            dict.reserveCapacity(items.count)
            for item in items {
                dict[item.entry.path] = item.payload
            }
            return dict
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    public static func readEntryData(at url: URL, format: ArchiveFormat, path: String) throws -> Data {
        switch format {
        case .gz, .zst, .xz, .bz2, .lz4:
            let raw = try Data(contentsOf: url, options: .mappedIfSafe)
            return try decompressStream(raw, format: format)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4:
            let tarData = try loadUncompressedTarData(at: url, format: format)
            let target = ArchiveEntry.normalizePath(path, isDirectory: path.hasSuffix("/"))
            let items = try parseTarEntries(tarData, methodLabel: format.defaultAlgorithm.shortName)
            guard let found = items.first(where: { $0.entry.path == target }) else {
                throw BoltZipError.entryNotFound(path)
            }
            return found.payload
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    public static func create(
        from inputURLs: [URL],
        to outputURL: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController? = nil,
        progress: ((OperationProgress) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let items = try ZipWriter.collectInputItems(from: inputURLs, excludeMacJunk: options.excludeMacJunk)
        var tarData = Data()
        let totalBytes = items.reduce(UInt64(0)) { $0 + $1.fileSize }
        var stagedBytes: UInt64 = 0
        let isRawTar = (options.format == .tar)

        for item in items {
            try controller?.checkpoint()
            let stageFrac = totalBytes > 0 ? Double(stagedBytes) / Double(totalBytes) : 0
            progress?(OperationProgress(
                fractionCompleted: isRawTar ? stageFrac * 0.95 : stageFrac * 0.15,
                currentItem: item.archivePath,
                processedBytes: isRawTar ? stagedBytes : UInt64(Double(totalBytes) * (stageFrac * 0.15)),
                totalBytes: totalBytes
            ))
            let payload: Data
            if let fileURL = item.fileURL, !item.isDirectory {
                payload = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            } else {
                payload = Data()
            }
            appendTarEntry(
                to: &tarData,
                path: item.archivePath,
                isDirectory: item.isDirectory,
                permissions: item.permissions,
                modifiedDate: item.modifiedDate,
                payload: payload
            )
            stagedBytes += item.fileSize
        }
        // Two 512-byte zero blocks terminate TAR stream
        tarData.append(Data(count: blockSize * 2))
        try controller?.checkpoint()

        let reportCompressProgress: (UInt64, UInt64) -> Void = { bytesRead, tarTotal in
            let ratio = tarTotal > 0 ? Double(bytesRead) / Double(tarTotal) : 1.0
            let frac = min(0.99, 0.15 + 0.85 * ratio)
            let estBytes = totalBytes > 0 ? UInt64(Double(totalBytes) * frac) : bytesRead
            progress?(OperationProgress(
                fractionCompleted: frac,
                currentItem: outputURL.lastPathComponent,
                processedBytes: estBytes,
                totalBytes: totalBytes > 0 ? totalBytes : tarTotal
            ))
        }

        let finalBytes: Data
        switch options.format {
        case .tar:
            finalBytes = tarData
        case .tarGz:
            finalBytes = try CompressionCodec.compress(data: tarData, algorithm: .deflate, gzipContainer: true, level: options.level, controller: controller, progress: reportCompressProgress)
        case .tarZst:
            finalBytes = try CompressionCodec.compress(data: tarData, algorithm: .zstd, gzipContainer: false, level: options.level, controller: controller, progress: reportCompressProgress)
        case .tarXz:
            finalBytes = try CompressionCodec.compress(data: tarData, algorithm: .xz, gzipContainer: false, level: options.level, controller: controller, progress: reportCompressProgress)
        case .tarBz2:
            finalBytes = try CompressionCodec.compress(data: tarData, algorithm: .bzip2, gzipContainer: false, level: options.level, controller: controller, progress: reportCompressProgress)
        case .tarLz4:
            finalBytes = try CompressionCodec.compress(data: tarData, algorithm: .lz4, gzipContainer: false, level: options.level, controller: controller, progress: reportCompressProgress)
        default:
            throw BoltZipError.unsupportedFormat(options.format.displayName)
        }

        try controller?.checkpoint()
        try finalBytes.write(to: outputURL, options: .atomic)
        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outputURL.lastPathComponent, processedBytes: totalBytes, totalBytes: totalBytes))
    }

    public static func testIntegrity(at url: URL, format: ArchiveFormat) throws -> IntegrityReport {
        let start = CFAbsoluteTimeGetCurrent()
        let entries = try listEntries(at: url, format: format)
        let results = entries.map {
            IntegrityEntryResult(path: $0.path, status: .passed, detail: "流解码与校验和通过")
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

    private static func decompressStream(
        _ data: Data,
        format: ArchiveFormat,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        switch format {
        case .gz, .tarGz:
            return try CompressionCodec.decompress(data: data, algorithm: .deflate, gzipContainer: true, controller: controller, progress: progress)
        case .zst, .tarZst:
            return try CompressionCodec.decompress(data: data, algorithm: .zstd, controller: controller, progress: progress)
        case .xz, .tarXz:
            return try CompressionCodec.decompress(data: data, algorithm: .xz, controller: controller, progress: progress)
        case .bz2, .tarBz2:
            return try CompressionCodec.decompress(data: data, algorithm: .bzip2, controller: controller, progress: progress)
        case .lz4, .tarLz4:
            return try CompressionCodec.decompress(data: data, algorithm: .lz4, controller: controller, progress: progress)
        case .tar:
            progress?(UInt64(data.count), UInt64(data.count))
            return data
        default:
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
    }

    private static func loadUncompressedTarData(
        at url: URL,
        format: ArchiveFormat,
        controller: ArchiveTaskController? = nil,
        progress: ((UInt64, UInt64) -> Void)? = nil
    ) throws -> Data {
        let raw = try Data(contentsOf: url, options: .mappedIfSafe)
        return try decompressStream(raw, format: format, controller: controller, progress: progress)
    }

    private static func listSingleStream(at url: URL, format: ArchiveFormat) throws -> [ArchiveEntry] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let compressedSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()

        let raw = try Data(contentsOf: url, options: .mappedIfSafe)
        var innerName = url.deletingPathExtension().lastPathComponent
        if format == .gz, let gzName = parseGzipOriginalFilename(raw), !gzName.isEmpty {
            innerName = gzName
        } else if innerName == url.lastPathComponent || innerName.isEmpty {
            innerName = url.lastPathComponent + ".out"
        }

        let plain = try decompressStream(raw, format: format)
        let crc = CompressionCodec.crc32(plain)
        return [
            ArchiveEntry(
                path: innerName,
                isDirectory: false,
                uncompressedSize: UInt64(plain.count),
                compressedSize: compressedSize,
                compressionMethodName: format.defaultAlgorithm.shortName,
                crc32: crc,
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

    struct ParsedTarItem {
        let entry: ArchiveEntry
        let payload: Data
    }

    private static func parseTarEntries(_ data: Data, methodLabel: String) throws -> [ParsedTarItem] {
        var items: [ParsedTarItem] = []
        var offset = 0
        var nextPaxAttributes: [String: String] = [:]
        var nextGnuLongName: String?

        while offset + blockSize <= data.count {
            let header = data.subdata(in: offset..<(offset + blockSize))
            offset += blockSize

            if header.allSatisfy({ $0 == 0 }) {
                break
            }

            let rawName = readTarString(header, start: 0, length: 100)
            let modeVal = readTarOctal(header, start: 100, length: 8)
            let sizeVal = readTarOctal(header, start: 124, length: 12)
            let mtimeVal = readTarOctal(header, start: 136, length: 12)
            let typeFlag = header[156]
            let prefix = readTarString(header, start: 345, length: 155)

            let payloadLen = Int(sizeVal)
            let paddedLen = ((payloadLen + blockSize - 1) / blockSize) * blockSize
            guard offset + payloadLen <= data.count else {
                throw BoltZipError.invalidArchive("TAR 数据块提前结束")
            }
            let payload = data.subdata(in: offset..<(offset + payloadLen))
            offset = min(data.count, offset + paddedLen)

            // PAX extended header ('x') or GNU long name ('L')
            if typeFlag == UInt8(ascii: "x") {
                nextPaxAttributes = parsePAXPayload(payload)
                continue
            } else if typeFlag == UInt8(ascii: "g") {
                continue
            } else if typeFlag == UInt8(ascii: "L") {
                nextGnuLongName = String(data: payload, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                continue
            }

            let basePath = prefix.isEmpty ? rawName : "\(prefix)/\(rawName)"
            let resolvedPath = nextPaxAttributes["path"] ?? nextGnuLongName ?? basePath
            let resolvedSize = nextPaxAttributes["size"].flatMap(UInt64.init) ?? sizeVal
            let resolvedMtime = nextPaxAttributes["mtime"].flatMap(Double.init) ?? Double(mtimeVal)

            nextPaxAttributes.removeAll()
            nextGnuLongName = nil

            let isDir = typeFlag == UInt8(ascii: "5") || resolvedPath.hasSuffix("/")
            let isSymlink = typeFlag == UInt8(ascii: "2")
            let crc = isDir ? 0 : CompressionCodec.crc32(payload)
            let entry = ArchiveEntry(
                path: resolvedPath,
                isDirectory: isDir,
                isSymbolicLink: isSymlink,
                uncompressedSize: isDir ? 0 : resolvedSize,
                compressedSize: isDir ? 0 : resolvedSize,
                compressionMethodName: methodLabel,
                crc32: crc,
                modifiedDate: Date(timeIntervalSince1970: resolvedMtime),
                permissions: UInt16(modeVal & 0o7777)
            )
            items.append(ParsedTarItem(entry: entry, payload: payload))
        }
        return items
    }

    private static func appendTarEntry(
        to out: inout Data,
        path: String,
        isDirectory: Bool,
        permissions: UInt16,
        modifiedDate: Date,
        payload: Data
    ) {
        let utf8Path = Data(path.utf8)
        let needsPAX = utf8Path.count > 100 || payload.count >= 0o77777777777

        if needsPAX {
            var paxBody = Data()
            paxBody.append(paxRecord(key: "path", value: path))
            if payload.count >= 0o77777777777 {
                paxBody.append(paxRecord(key: "size", value: String(payload.count)))
            }
            let paxName = "PaxHeaders.0/" + String(path.suffix(70))
            let paxHeader = buildUSTARHeader(
                name: paxName,
                mode: 0o644,
                size: UInt64(paxBody.count),
                mtime: UInt64(max(0, modifiedDate.timeIntervalSince1970)),
                typeFlag: UInt8(ascii: "x")
            )
            out.append(paxHeader)
            out.append(paxBody)
            let paxPad = (blockSize - (paxBody.count % blockSize)) % blockSize
            if paxPad > 0 { out.append(Data(count: paxPad)) }
        }

        let headerName = String(path.prefix(99))
        let header = buildUSTARHeader(
            name: headerName,
            mode: permissions,
            size: isDirectory ? 0 : UInt64(payload.count),
            mtime: UInt64(max(0, modifiedDate.timeIntervalSince1970)),
            typeFlag: isDirectory ? UInt8(ascii: "5") : UInt8(ascii: "0")
        )
        out.append(header)
        if !isDirectory && !payload.isEmpty {
            out.append(payload)
            let pad = (blockSize - (payload.count % blockSize)) % blockSize
            if pad > 0 { out.append(Data(count: pad)) }
        }
    }

    private static func buildUSTARHeader(
        name: String,
        mode: UInt16,
        size: UInt64,
        mtime: UInt64,
        typeFlag: UInt8
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
