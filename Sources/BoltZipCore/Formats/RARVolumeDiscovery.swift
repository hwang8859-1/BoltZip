import Foundation

enum RARVolumeDiscovery {
    struct VolumeSet {
        let first: URL
        let paths: [String]
        let isSplitVolume: Bool
        let needsVolumeProbe: Bool
        let isLegacySolid: Bool
        let isRAR5: Bool
    }

    static func resolve(_ url: URL, confirmedMultiVolume: Bool = false) throws -> VolumeSet {
        let selected = url.standardizedFileURL
        let info = try readHeader(selected)
        guard let header = info, header.isVolume ?? confirmedMultiVolume else {
            return VolumeSet(first: selected, paths: [selected.path], isSplitVolume: false,
                             needsVolumeProbe: info?.isVolume == nil, isLegacySolid: info?.isLegacySolid ?? false,
                             isRAR5: info?.version == .rar5)
        }

        let directory = selected.deletingLastPathComponent()
        let selectedName = selected.lastPathComponent
        let selectedSeries = NamingSeries(selected, usesNumberedNames: header.usesNumberedNames)
        let selectedIndex = header.index ?? max(0, selectedSeries?.index ?? 0)
        var first = selected
        var current = header
        if selectedIndex > 0 {
            guard let selectedSeries else {
                throw BoltZipError.missingSplitVolume(selected.deletingPathExtension().appendingPathExtension("part1.rar").lastPathComponent)
            }
            let firstIndex = selectedSeries.width > 0 ? max(-1, selectedSeries.index - selectedIndex) : 0
            let expected = selectedSeries.name(at: firstIndex)
            guard let candidate = try findFirst(in: directory, series: selectedSeries, firstIndex: firstIndex, version: header.version),
                  candidate.url.lastPathComponent != selectedName else {
                throw BoltZipError.missingSplitVolume(expected)
            }
            first = candidate.url
            current = candidate.header
        }

        var volumes = [first.path]
        if let series = NamingSeries(first, usesNumberedNames: current.usesNumberedNames) {
            while current.hasNext != false {
                let index = volumes.count
                let (nameIndex, overflow) = series.index.addingReportingOverflow(index)
                guard !overflow, nameIndex < Int.max else { throw BoltZipError.invalidArchive(selectedName) }
                let nextURL = directory.appendingPathComponent(series.name(at: nameIndex))
                guard let next = try readHeader(nextURL), next.version == header.version,
                      next.isVolume != false, next.index.map({ $0 == index }) ?? true else {
                    if current.hasNext == true || index <= selectedIndex {
                        throw BoltZipError.missingSplitVolume(nextURL.lastPathComponent)
                    }
                    break
                }
                volumes.append(nextURL.path)
                current = next
            }
        }
        if selectedIndex > 0 && (selectedIndex >= volumes.count ||
            volumes[selectedIndex] != selected.path && volumes[selectedIndex].caseInsensitiveCompare(selected.path) != .orderedSame) {
            throw BoltZipError.missingSplitVolume(selectedSeries?.name(at: selectedIndex - 1) ?? selectedName)
        }
        return VolumeSet(first: first, paths: volumes, isSplitVolume: true, needsVolumeProbe: false,
                         isLegacySolid: header.isLegacySolid, isRAR5: header.version == .rar5)
    }

    private static func findFirst(in directory: URL, series: NamingSeries, firstIndex: Int,
                                  version: Version) throws -> (url: URL, header: Header)? {
        let named = directory.appendingPathComponent(series.name(at: firstIndex))
        if let header = try readHeader(named), header.isFirst(of: version) {
            return (named, header)
        }

        // The final part may have an extra digit compared to the first part (part100 versus part01).
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let candidates = try contents.compactMap { url -> (URL, Header)? in
            guard url != named, let other = NamingSeries(url, usesNumberedNames: series.width > 0),
                  other.index == firstIndex, series.matches(other),
                  let header = try readHeader(url), header.isFirst(of: version) else { return nil }
            return (url, header)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private struct NamingSeries {
        let prefix: String
        let suffix: String
        let width: Int
        let index: Int

        init?(_ url: URL, usesNumberedNames: Bool) {
            let ext = url.pathExtension
            let stem = url.deletingPathExtension().lastPathComponent
            if usesNumberedNames, ext.caseInsensitiveCompare("rar") == .orderedSame,
               let numberRange = stem.range(of: #"[0-9]+$"#, options: .regularExpression),
               let number = Int(stem[numberRange]) {
                prefix = String(stem[..<numberRange.lowerBound])
                width = stem[numberRange].count
                index = number - 1
                suffix = "." + ext
                return
            }
            prefix = stem + "."
            suffix = ""
            width = 0
            if ext.caseInsensitiveCompare("rar") == .orderedSame {
                index = 0
            } else {
                let bytes = Array(ext.lowercased().utf8)
                guard bytes.count == 3, (114...122).contains(bytes[0]),
                      let number = Int(ext.dropFirst()), number >= 0, number <= 99 else { return nil }
                index = (Int(bytes[0]) - 114) * 100 + number + 1
            }
        }

        func name(at index: Int) -> String {
            if width > 0 {
                let digits = String(index + 1)
                return prefix + String(repeating: "0", count: max(0, width - digits.count)) + digits + suffix
            }
            if index == 0 { return prefix + "rar" }
            // Old-style extensions run from .r00 through .z99.
            let letter = UnicodeScalar(114 + (index - 1) / 100) ?? "r"
            return prefix + String(letter) + String(format: "%02d", (index - 1) % 100)
        }

        func matches(_ other: NamingSeries) -> Bool {
            prefix.caseInsensitiveCompare(other.prefix) == .orderedSame &&
            suffix.caseInsensitiveCompare(other.suffix) == .orderedSame
        }
    }

    private enum Version {
        case rar4
        case rar5
    }

    private struct Header {
        let version: Version
        let isVolume: Bool?
        let index: Int?
        let hasNext: Bool?
        var isLegacySolid: Bool = false
        var usesNumberedNames: Bool = true

        func isFirst(of version: Version) -> Bool {
            self.version == version && isVolume != false && (index == nil || index == 0)
        }
    }

    private static let signature = Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07])

    private static func readHeader(_ url: URL) throws -> Header? {
        guard FileManager.default.fileExists(atPath: url.path),
              try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = try handle.read(upToCount: 2048) ?? Data()
        if !bytes.starts(with: signature) {
            // The RAR signature may follow a self-extracting module.
            try handle.seek(toOffset: 0)
            bytes = try handle.read(upToCount: 1024 * 1024 + 2048) ?? Data()
        }
        guard let sig = bytes.range(of: signature), sig.upperBound < bytes.count else { return nil }
        if bytes[sig.upperBound] == 0 {
            let start = sig.upperBound + 1
            guard bytes.count - start >= 13, bytes[start + 2] == 0x73,
                  checkRAR4CRC(bytes, at: start, length: 13) else { return nil }
            let flags = word(bytes, start + 3)
            let volume = flags & 0x0001 != 0
            let footer = volume && flags & 0x0080 == 0 ? try rar4Footer(readTail(handle)) : nil
            let index = flags & 0x0100 != 0 ? 0 : footer?.index
            return Header(version: .rar4, isVolume: volume, index: index, hasNext: footer?.hasNext,
                          isLegacySolid: flags & 0x0008 != 0, usesNumberedNames: flags & 0x0010 != 0)
        }
        guard bytes.count - sig.upperBound >= 2, bytes[sig.upperBound] == 1, bytes[sig.upperBound + 1] == 0,
              let block = rar5Block(bytes, at: sig.upperBound + 2) else { return nil }
        if block.type == 4 { return Header(version: .rar5, isVolume: nil, index: nil, hasNext: nil) }
        guard block.type == 1 else { return nil }
        var position = block.body
        guard let flags = vint(bytes, position: &position, until: block.end) else { return nil }
        let volume = flags & 0x0001 != 0
        let index: Int?
        if volume && flags & 0x0002 != 0 {
            guard let rawIndex = vint(bytes, position: &position, until: block.end),
                  let number = Int(exactly: rawIndex) else { return nil }
            index = number
        } else {
            index = 0
        }
        return Header(version: .rar5, isVolume: volume, index: index, hasNext: volume ? try rar5Footer(readTail(handle)) : nil)
    }

    private static func readTail(_ handle: FileHandle) throws -> Data {
        let size = try handle.seekToEnd()
        let length = min(size, 128)
        try handle.seek(toOffset: size - length)
        return try handle.read(upToCount: Int(length)) ?? Data()
    }

    private static func rar4Footer(_ data: Data) -> (index: Int?, hasNext: Bool)? {
        guard data.count >= 7 else { return nil }
        for i in (0...(data.count - 7)).reversed() where data[i + 2] == 0x7b {
            let length = word(data, i + 5)
            guard length >= 7, length <= data.count - i, checkRAR4CRC(data, at: i, length: length) else { continue }
            let flags = word(data, i + 3)
            let volumeField = i + 7 + (flags & 0x0002 != 0 ? 4 : 0)
            let index = flags & 0x0008 != 0 && volumeField + 2 <= i + length ? word(data, volumeField) : nil
            return (index, flags & 0x0001 != 0)
        }
        return nil
    }

    private static func rar5Footer(_ data: Data) -> Bool? {
        guard data.count >= 8 else { return nil }
        for i in (0...(data.count - 8)).reversed() {
            guard let block = rar5Block(data, at: i), block.type == 5 else { continue }
            var position = block.body
            if let flags = vint(data, position: &position, until: block.end) {
                return flags & 0x0001 != 0
            }
        }
        return nil
    }

    private static func rar5Block(_ data: Data, at start: Int) -> (type: UInt64, body: Int, end: Int)? {
        guard data.count - start >= 7 else { return nil }
        var position = start + 4
        guard let size = vint(data, position: &position, until: min(data.count, start + 7)),
              size <= UInt64(data.count - position) else { return nil }
        let end = position + Int(size)
        let crc = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(data[start + $1]) << (8 * $1)) }
        guard CompressionCodec.crc32(data.subdata(in: (start + 4)..<end)) == crc,
              let type = vint(data, position: &position, until: end),
              let flags = vint(data, position: &position, until: end) else { return nil }
        for flag in [UInt64(1), 2] where flags & flag != 0 {
            guard vint(data, position: &position, until: end) != nil else { return nil }
        }
        return (type, position, end)
    }

    private static func vint(_ data: Data, position: inout Int, until end: Int) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard position < end else { return nil }
            let byte = data[position]
            position += 1
            guard shift < 63 || byte <= 1 else { return nil }
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }

    private static func checkRAR4CRC(_ data: Data, at start: Int, length: Int) -> Bool {
        let crc = CompressionCodec.crc32(data.subdata(in: (start + 2)..<(start + length)))
        return Int(crc & 0xffff) == word(data, start)
    }

    private static func word(_ data: Data, _ index: Int) -> Int {
        Int(data[index]) | (Int(data[index + 1]) << 8)
    }
}
