import Darwin
import Foundation

enum ArchiveOutputTransaction {
    static func validate(_ destination: URL) throws {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
           attrs[.type] as? FileAttributeType == .typeDirectory {
            throw ArchiveOperationError.outputIsDirectory(destination.lastPathComponent)
        }
    }

    static func makeStage(for destination: URL) throws -> URL {
        try validate(destination)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".boltzip-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return stage
    }

    static func publish(_ staged: [URL], to destinations: [URL]) throws {
        precondition(staged.count == destinations.count)
        for destination in destinations { try validate(destination) }
        if staged.count == 1 {
            let status = staged[0].withUnsafeFileSystemRepresentation { source in
                destinations[0].withUnsafeFileSystemRepresentation { target in
                    guard let source, let target else { return EINVAL }
                    return Darwin.rename(source, target) == 0 ? 0 : errno
                }
            }
            guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(status)) }
            return
        }

        let fm = FileManager.default
        var backups: [(original: URL, backup: URL)] = []
        var published: [URL] = []
        do {
            for destination in destinations {
                if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
                    let backup = destination.deletingLastPathComponent().appendingPathComponent(".boltzip-previous-\(UUID().uuidString)")
                    try fm.moveItem(at: destination, to: backup)
                    backups.append((destination, backup))
                }
            }
            for (source, destination) in zip(staged, destinations) {
                try fm.moveItem(at: source, to: destination)
                published.append(destination)
            }
        } catch {
            for destination in published { try? fm.removeItem(at: destination) }
            for pair in backups { try fm.moveItem(at: pair.backup, to: pair.original) }
            throw error
        }
        for pair in backups { try? fm.removeItem(at: pair.backup) }
    }
}
