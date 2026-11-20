import CBoltCompression
import Foundation

extension ArchiveFormat {
    static func requireForReading(from archiveURL: URL) throws -> ArchiveFormat {
        guard let format = try detectForReading(from: archiveURL) else {
            throw BoltZipError.unsupportedFormat(archiveURL.pathExtension)
        }
        return format
    }

    /// Reading uses content; `detect(from:)` remains the filename policy for output names and split volumes.
    public static func detectForReading(from url: URL) throws -> ArchiveFormat? {
        // A directory or special file is not an archive input. Opening a named pipe could block waiting for a writer.
        guard try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            return nil
        }
        let named = detect(from: url)
        let ext = url.pathExtension.lowercased()
        if ext.hasPrefix("z"), Int(ext.dropFirst()) != nil { return .zip }
        if ext.count == 3, ext.hasPrefix("r"), Int(ext.dropFirst()) != nil { return .rar }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 512) ?? Data()
        if head.starts(with: [0x50, 0x4b, 0x03, 0x04]) || head.starts(with: [0x50, 0x4b, 0x05, 0x06]) || head.starts(with: [0x50, 0x4b, 0x07, 0x08]) { return .zip }
        if head.starts(with: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) { return .sevenZip }
        if head.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]) { return .rar }
        if head.starts(with: Array("MSCF".utf8)) { return .cab }
        if head.starts(with: Array("xar!".utf8)) { return .xar }

        let stream: ArchiveFormat?
        if head.starts(with: [0x1f, 0x8b]) { stream = .gz }
        else if head.starts(with: [0x28, 0xb5, 0x2f, 0xfd]) { stream = .zst }
        else if head.starts(with: [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]) { stream = .xz }
        else if head.starts(with: Array("BZh".utf8)) { stream = .bz2 }
        else if head.starts(with: [0x04, 0x22, 0x4d, 0x18]) { stream = .lz4 }
        else { stream = nil }

        var format: Int32 = 0
        var filter: Int32 = 0
        let result = url.path.withCString { bolt_la_probe($0, &format, &filter) }
        if result == 0 {
            // Only TAR wrappers are expanded as containers by our readers. A gzip-wrapped
            // ZIP, for example, remains a gzip stream whose payload is a ZIP file.
            let filtered: ArchiveFormat? = [1: .gz, 2: .bz2, 5: .xz, 6: .xz, 13: .lz4, 14: .zst][filter]
            if format != 0x30000, let filtered { return filtered }
            switch format {
            case 0x30000:
                switch filter {
                case 1: return .tarGz
                case 2: return .tarBz2
                case 5, 6: return .tarXz
                case 13: return .tarLz4
                case 14: return .tarZst
                default: return .tar
                }
            case 0x50000: return .zip
            case 0x40000: return .iso
            case 0xa0000: return .xar
            case 0xc0000: return .cab
            case 0xd0000, 0x100000: return .rar
            case 0xe0000: return .sevenZip
            default: break
            }
        }
        return stream ?? named
    }
}
