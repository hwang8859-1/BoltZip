import Foundation

enum ZipSignature {
    static let localFileHeader: UInt32 = 0x04034B50
    static let dataDescriptor: UInt32 = 0x08074B50
    static let centralDirectoryHeader: UInt32 = 0x02014B50
    static let endOfCentralDirectory: UInt32 = 0x06054B50
    static let zip64EOCD: UInt32 = 0x06064B50
    static let zip64Locator: UInt32 = 0x07064B50
}

enum ZipExtraTag {
    static let zip64: UInt16 = 0x0001
    static let extendedTimestamp: UInt16 = 0x5455
    static let infoZipUnicodePath: UInt16 = 0x7075
    static let winZipAES: UInt16 = 0x9901
}

struct ZipRecord {
    let rawPathBytes: Data
    let flags: UInt16
    let compressionMethod: UInt16
    let dosTime: UInt16
    let dosDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let diskNumberStart: UInt32
    let localHeaderOffset: UInt64
    let externalAttributes: UInt32
    let extraData: Data
    let commentData: Data

    // Parsed extra metadata
    let unicodeExtraPath: String?
    let extendedTimestamp: Date?
    let aesExtra: WinZipAESExtra?
}

struct WinZipAESExtra {
    let vendorVersion: UInt16 // 1 = AE-1, 2 = AE-2
    let strength: ZipCrypto.AESStrength
    let actualMethod: UInt16
}

enum ZipBinary {
    static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32LE(data, at: offset))
            | (UInt64(readUInt32LE(data, at: offset + 4)) << 32)
    }

    static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    static func appendUInt64LE(_ data: inout Data, _ value: UInt64) {
        appendUInt32LE(&data, UInt32(value & 0xFFFFFFFF))
        appendUInt32LE(&data, UInt32((value >> 32) & 0xFFFFFFFF))
    }

    static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, comps.year ?? 2026)) - 1980
        let month = max(1, min(12, comps.month ?? 1))
        let day = max(1, min(31, comps.day ?? 1))
        let hour = max(0, min(23, comps.hour ?? 0))
        let minute = max(0, min(59, comps.minute ?? 0))
        let second = max(0, min(59, comps.second ?? 0)) / 2

        let dosDate = UInt16((year << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | second)
        return (dosTime, dosDate)
    }

    static func dateFromDOS(time: UInt16, date: UInt16) -> Date {
        let second = Int((time & 0x1F) * 2)
        let minute = Int((time >> 5) & 0x3F)
        let hour = Int((time >> 11) & 0x1F)
        let day = max(1, Int(date & 0x1F))
        let month = max(1, Int((date >> 5) & 0x0F))
        let year = Int((date >> 9) & 0x7F) + 1980

        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return comps.date ?? Date(timeIntervalSince1970: 0)
    }

    static func parseExtraFields(
        _ extra: Data,
        rawPathBytes: Data,
        compressedSize32: UInt32,
        uncompressedSize32: UInt32,
        offset32: UInt32,
        disk32: UInt16
    ) -> (
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        localOffset: UInt64,
        diskStart: UInt32,
        unicodePath: String?,
        mtime: Date?,
        aes: WinZipAESExtra?
    ) {
        var comp = UInt64(compressedSize32)
        var uncomp = UInt64(uncompressedSize32)
        var offset = UInt64(offset32)
        var disk = UInt32(disk32)
        var unicodePath: String?
        var mtime: Date?
        var aes: WinZipAESExtra?

        var pos = 0
        while pos + 4 <= extra.count {
            let tag = readUInt16LE(extra, at: pos)
            let size = Int(readUInt16LE(extra, at: pos + 2))
            pos += 4
            guard pos + size <= extra.count else { break }
            let payload = extra.subdata(in: pos..<(pos + size))
            pos += size

            switch tag {
            case ZipExtraTag.zip64:
                var p = 0
                if uncompressedSize32 == 0xFFFFFFFF && p + 8 <= payload.count {
                    uncomp = readUInt64LE(payload, at: p)
                    p += 8
                }
                if compressedSize32 == 0xFFFFFFFF && p + 8 <= payload.count {
                    comp = readUInt64LE(payload, at: p)
                    p += 8
                }
                if offset32 == 0xFFFFFFFF && p + 8 <= payload.count {
                    offset = readUInt64LE(payload, at: p)
                    p += 8
                }
                if disk32 == 0xFFFF && p + 4 <= payload.count {
                    disk = readUInt32LE(payload, at: p)
                }
            case ZipExtraTag.infoZipUnicodePath:
                if payload.count >= 5, payload[0] == 1 {
                    let expectedCRC = readUInt32LE(payload, at: 1)
                    if CompressionCodec.crc32(rawPathBytes) == expectedCRC {
                        let strData = payload.subdata(in: 5..<payload.count)
                        unicodePath = String(data: strData, encoding: .utf8)
                    }
                }
            case ZipExtraTag.extendedTimestamp:
                if payload.count >= 5, (payload[0] & 0x01) != 0 {
                    let unixSec = Int32(bitPattern: readUInt32LE(payload, at: 1))
                    mtime = Date(timeIntervalSince1970: TimeInterval(unixSec))
                }
            case ZipExtraTag.winZipAES:
                if payload.count >= 7 {
                    let ver = readUInt16LE(payload, at: 0)
                    // Vendor ID is 'AE' (0x41, 0x45)
                    if payload[2] == 0x41 && payload[3] == 0x45 {
                        let strengthRaw = payload[4]
                        let actualMethod = readUInt16LE(payload, at: 5)
                        if let strength = ZipCrypto.AESStrength(rawValue: strengthRaw) {
                            aes = WinZipAESExtra(vendorVersion: ver, strength: strength, actualMethod: actualMethod)
                        }
                    }
                }
            default:
                break
            }
        }
        return (comp, uncomp, offset, disk, unicodePath, mtime, aes)
    }

    static func methodDisplayName(compressionMethod: UInt16, aes: WinZipAESExtra?) -> String {
        let effective = aes?.actualMethod ?? compressionMethod
        switch effective {
        case 0: return "Store"
        case 8: return "DEFLATE"
        case 9: return "Deflate64"
        case 12: return "Bzip2"
        case 14: return "LZMA"
        case 93: return "Zstandard"
        case 95: return "XZ"
        case 99: return "AES"
        default: return "Method \(effective)"
        }
    }

    static func codecAlgorithm(for method: UInt16) throws -> CompressionAlgorithm {
        switch method {
        case 0: return .store
        case 8: return .deflate
        case 12: return .bzip2
        case 93: return .zstd
        case 95: return .xz
        default: throw BoltZipError.unsupportedCompressionMethod(method)
        }
    }
}
