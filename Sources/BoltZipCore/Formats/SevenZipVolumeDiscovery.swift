import Foundation

enum SevenZipVolumeDiscovery {
    struct VolumeSet {
        let first: URL
        let paths: [String]
        let isSplitVolume: Bool
    }

    static func isSevenZipSplitFilename(_ url: URL) -> Bool {
        guard parseNumericExtension(url) != nil else { return false }
        let baseExt = url.deletingPathExtension().pathExtension.lowercased()
        return baseExt == "7z" || baseExt == "cb7"
    }

    static func stripSplitSuffix(from url: URL) -> URL {
        isSevenZipSplitFilename(url) ? url.deletingPathExtension() : url
    }

    static func formatVolumeExtension(_ index: Int, width: Int = 3) -> String {
        let digits = String(index)
        if digits.count >= width {
            return digits
        }
        return String(repeating: "0", count: width - digits.count) + digits
    }

    static func hasValidFirstVolumeHeader(forContinuation url: URL) -> Bool {
        guard let series = NamingSeries(url), series.index > 1 else { return false }
        let first = series.url(at: 1)
        guard isRegularFile(first), (try? readStartHeader(at: first)) != nil else {
            return false
        }
        return true
    }

    static func resolve(_ url: URL) throws -> VolumeSet {
        let selected = url.standardizedFileURL
        guard let series = NamingSeries(selected) else {
            return VolumeSet(first: selected, paths: [selected.path], isSplitVolume: false)
        }

        let firstURL = series.url(at: 1)
        guard isRegularFile(firstURL) else {
            throw BoltZipError.missingSplitVolume(firstURL.lastPathComponent)
        }

        let header = try readStartHeader(at: firstURL)
        let firstSize = try fileSize(of: firstURL)

        var volumes: [(url: URL, size: UInt64)] = [(firstURL, firstSize)]
        var accumulated = firstSize

        while accumulated < header.expectedTotalSize {
            let nextIndex = volumes.count + 1
            let nextURL = series.url(at: nextIndex)
            guard isRegularFile(nextURL) else {
                throw BoltZipError.missingSplitVolume(nextURL.lastPathComponent)
            }
            let nextSize = try fileSize(of: nextURL)
            guard nextSize > 0 else {
                throw BoltZipError.invalidArchive(nextURL.lastPathComponent)
            }
            accumulated = try ArchiveByteCount.checkedSum(accumulated, nextSize)
            volumes.append((nextURL, nextSize))
        }

        guard series.index >= 1,
              series.index <= volumes.count,
              volumes[series.index - 1].url.path.caseInsensitiveCompare(selected.path) == .orderedSame else {
            throw BoltZipError.invalidArchive(selected.lastPathComponent)
        }

        try verifyNextHeaderCRC(header: header, in: volumes, contextName: firstURL.lastPathComponent)

        return VolumeSet(
            first: firstURL,
            paths: volumes.map(\.url.path),
            isSplitVolume: volumes.count > 1
        )
    }

    private struct NamingSeries {
        let baseURL: URL
        let width: Int
        let index: Int

        init?(_ url: URL) {
            guard let (extCount, number) = SevenZipVolumeDiscovery.parseNumericExtension(url) else {
                return nil
            }
            let base = url.deletingPathExtension()
            guard !base.lastPathComponent.isEmpty else { return nil }
            self.baseURL = base
            self.index = number
            if number >= 1000 {
                // 7-Zip pads 1...999 to 3 digits and emits .1000+ without a leading zero.
                let threeDigitFirst = base.appendingPathExtension("001")
                if SevenZipVolumeDiscovery.isRegularFile(threeDigitFirst) {
                    self.width = 3
                } else {
                    let sameWidthFirst = base.appendingPathExtension(String(repeating: "0", count: extCount - 1) + "1")
                    self.width = SevenZipVolumeDiscovery.isRegularFile(sameWidthFirst) ? extCount : 3
                }
            } else {
                self.width = extCount
            }
        }

        func url(at volumeIndex: Int) -> URL {
            let suffix = SevenZipVolumeDiscovery.formatVolumeExtension(volumeIndex, width: width)
            return baseURL.appendingPathExtension(suffix)
        }
    }

    private struct StartHeader {
        let nextHeaderStart: UInt64
        let nextHeaderSize: UInt64
        let nextHeaderCRC: UInt32
        let expectedTotalSize: UInt64
    }

    private static let signature: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]

    private static func parseNumericExtension(_ url: URL) -> (length: Int, number: Int)? {
        let ext = url.pathExtension
        guard ext.count >= 3,
              ext.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let number = Int(ext), number >= 1 else {
            return nil
        }
        return (ext.count, number)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func fileSize(of url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func readStartHeader(at url: URL) throws -> StartHeader {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 32) ?? Data()
        guard bytes.count == 32,
              bytes.starts(with: signature),
              bytes[6] == 0 else {
            throw BoltZipError.invalidArchive(url.lastPathComponent)
        }
        let startCRC = uint32LE(bytes, at: 8)
        let computedStartCRC = CompressionCodec.crc32(bytes.subdata(in: 12..<32))
        guard startCRC == computedStartCRC else {
            throw BoltZipError.invalidArchive(url.lastPathComponent)
        }
        let nextHeaderOffset = uint64LE(bytes, at: 12)
        let nextHeaderSize = uint64LE(bytes, at: 20)
        let nextHeaderCRC = uint32LE(bytes, at: 28)
        let nextHeaderStart = try ArchiveByteCount.checkedSum(32, nextHeaderOffset)
        let expectedTotalSize = try ArchiveByteCount.checkedSum(nextHeaderStart, nextHeaderSize)
        return StartHeader(
            nextHeaderStart: nextHeaderStart,
            nextHeaderSize: nextHeaderSize,
            nextHeaderCRC: nextHeaderCRC,
            expectedTotalSize: expectedTotalSize
        )
    }

    private static func verifyNextHeaderCRC(
        header: StartHeader,
        in volumes: [(url: URL, size: UInt64)],
        contextName: String
    ) throws {
        if header.nextHeaderSize == 0 {
            guard header.nextHeaderCRC == 0 else {
                throw BoltZipError.invalidArchive(contextName)
            }
            return
        }

        var volumeStartOffset: UInt64 = 0
        var cursor = header.nextHeaderStart
        var remaining = header.nextHeaderSize
        var crc: UInt32 = 0

        for (volURL, volSize) in volumes {
            let volumeEndOffset = volumeStartOffset + volSize
            if cursor < volumeEndOffset && remaining > 0 {
                let localOffset = cursor - volumeStartOffset
                var volumeRemaining = min(remaining, volSize - localOffset)
                let handle = try FileHandle(forReadingFrom: volURL)
                defer { try? handle.close() }
                try handle.seek(toOffset: localOffset)

                while volumeRemaining > 0 {
                    let count = Int(min(volumeRemaining, 64 * 1024))
                    guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                        throw BoltZipError.invalidArchive(volURL.lastPathComponent)
                    }
                    crc = CompressionCodec.crc32(chunk, initial: crc)
                    let readBytes = UInt64(chunk.count)
                    volumeRemaining -= readBytes
                    cursor += readBytes
                    remaining -= readBytes
                }
            }
            volumeStartOffset = volumeEndOffset
            if remaining == 0 { break }
        }

        guard remaining == 0, crc == header.nextHeaderCRC else {
            throw BoltZipError.invalidArchive(contextName)
        }
    }

    private static func uint32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func uint64LE(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { partial, idx in
            partial | (UInt64(data[offset + idx]) << (8 * idx))
        }
    }
}
