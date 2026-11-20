import Foundation

public enum ArchiveEditCompatibilityError: LocalizedError, Sendable {
    case unsupportedCompression(path: String, method: UInt16)
    case unsupportedEncryption(path: String)
    case ambiguousEntry(String)

    public var errorDescription: String? { BoltCoreLocalization.archiveEditCompatibilityMessage(self) }
}

public struct ArchiveEntryCompressionProfile: Sendable {
    public let method: UInt16
    public let algorithm: CompressionAlgorithm?
    public let recordedLevel: Int?
    public var defaultLevel: Int? { algorithm == .store ? nil : algorithm?.defaultLevel }
}

enum ZipEntryStoragePolicy {
    static func profile(for record: ZipRecord, reader: ZipReader, accessor: ZipVolumeAccessor) throws -> ArchiveEntryCompressionProfile {
        let method = record.aesExtra?.actualMethod ?? record.compressionMethod
        let algorithm: CompressionAlgorithm?
        switch method {
        case 0: algorithm = .store
        case 8: algorithm = .deflate
        case 12: algorithm = .bzip2
        case 20, 93: algorithm = .zstd
        default: algorithm = nil
        }
        var level: Int?
        if method == 12, record.flags & 1 == 0, record.compressedSize <= 1024 * 1024 {
            let bytes = try reader.readRawPayload(for: record, accessor: accessor)
            if bytes.count >= 4, bytes.starts(with: [0x42, 0x5a, 0x68]), (49...57).contains(bytes[3]) {
                level = Int(bytes[3] - 48)
            }
        }
        return ArchiveEntryCompressionProfile(method: method, algorithm: algorithm, recordedLevel: level)
    }

    static func options(for record: ZipRecord, path: String, reader: ZipReader,
                        accessor: ZipVolumeAccessor, base: CreateArchiveOptions) throws -> CreateArchiveOptions {
        let profile = try profile(for: record, reader: reader, accessor: accessor)
        guard let algorithm = profile.algorithm else {
            throw ArchiveEditCompatibilityError.unsupportedCompression(path: path, method: profile.method)
        }
        var options = base
        options.algorithm = algorithm
        options.level = profile.recordedLevel ?? algorithm.defaultLevel
        if record.flags & 1 == 0 {
            options.encryption = .none
            options.password = nil
        } else {
            guard !(base.password ?? "").isEmpty else { throw BoltZipError.passwordRequired(path) }
            if let aes = record.aesExtra {
                guard aes.strength == .aes256 else { throw ArchiveEditCompatibilityError.unsupportedEncryption(path: path) }
                options.encryption = .aes256
            } else {
                guard record.flags & 0x40 == 0 else { throw ArchiveEditCompatibilityError.unsupportedEncryption(path: path) }
                options.encryption = .zipCrypto
            }
        }
        return options
    }
}

extension BoltArchiveEngine {
    public static func entryCompressionProfile(at archive: URL, path: String,
                                               encoding: FilenameEncodingOption = .auto) throws -> ArchiveEntryCompressionProfile {
        let reader = ZipReader(url: archive)
        let parsed = try reader.parseArchive()
        let records = parsed.records.filter { ZipReader.makeEntry(from: $0, encoding: encoding).path == path }
        guard records.count == 1, let record = records.first else {
            if records.isEmpty { throw BoltZipError.entryNotFound(path) }
            throw ArchiveEditCompatibilityError.ambiguousEntry(path)
        }
        let accessor = try ZipVolumeAccessor(archiveURL: archive)
        defer { accessor.closeAll() }
        try accessor.configureVolumes(totalDisks: parsed.totalDisks)
        return try ZipEntryStoragePolicy.profile(for: record, reader: reader, accessor: accessor)
    }
}
