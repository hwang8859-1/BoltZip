import CBoltCompression
import Foundation

enum SevenZipWriter {
    static func create(from inputs: [URL], to output: URL, algorithm: CompressionAlgorithm, level: Int?,
                       excludeMacJunk: Bool, preserveSymlinks: Bool, controller: ArchiveTaskController?,
                       progress: (@Sendable (OperationProgress) -> Void)?) throws {
        try controller?.checkpoint()
        try ArchiveOutputTransaction.validate(output)
        let items = try ZipWriter.collectInputItems(from: inputs, excludeMacJunk: excludeMacJunk,
                                                    preserveSymlinks: preserveSymlinks,
                                                    excluding: [output], controller: controller)
        let total = try items.reduce(UInt64(0)) { try BoltArchiveEngine.checkedArchiveSize($0, adding: $1.fileSize) }
        let stage = try ArchiveOutputTransaction.makeStage(for: output)
        defer { try? FileManager.default.removeItem(at: stage) }
        let stagedArchive = stage.appendingPathComponent("archive.7z")
        let codec: String
        switch algorithm {
        case .xz: codec = "lzma2"
        case .bzip2: codec = "bzip2"
        case .deflate: codec = "deflate"
        case .store: codec = "store"
        default: throw BoltZipError.unsupportedFormat(algorithm.shortName)
        }
        let options = "7zip:compression=\(codec)" + (algorithm == .store ? "" : ",7zip:compression-level=\(min(9, max(algorithm == .xz ? 0 : 1, level ?? algorithm.defaultLevel)))")
        var error = [CChar](repeating: 0, count: 1024)
        let writer = stagedArchive.path.withCString { path in
            options.withCString { bolt_la_7z_open(path, $0, &error, error.count) }
        }
        guard let writer else { throw failure(error) }
        defer { bolt_la_7z_free(writer) }
        var processed: UInt64 = 0
        for (index, item) in items.enumerated() {
            try controller?.checkpoint()
            let kind: UInt8 = item.isDirectory ? 1 : (item.isSymbolicLink ? 2 : 0)
            let status = item.archivePath.withCString { path in
                (item.symlinkTarget ?? "").withCString {
                    bolt_la_7z_header(writer, path, kind, $0, item.fileSize, item.permissions,
                                      Int64(item.modifiedDate.timeIntervalSince1970), &error, error.count)
                }
            }
            guard status == 0 else { throw failure(error) }
            if let source = item.fileURL, !item.isDirectory, !item.isSymbolicLink {
                let handle = try FileHandle(forReadingFrom: source)
                defer { try? handle.close() }
                var read: UInt64 = 0
                while true {
                    try controller?.checkpoint()
                    let chunk = try handle.read(upToCount: BoltConcurrency.streamChunkSize) ?? Data()
                    if chunk.isEmpty { break }
                    guard read <= item.fileSize, UInt64(chunk.count) <= item.fileSize - read else {
                        throw ArchiveOperationError.inputChanged(item.archivePath)
                    }
                    let result = chunk.withUnsafeBytes {
                        bolt_la_7z_write(writer, $0.bindMemory(to: UInt8.self).baseAddress, chunk.count, &error, error.count)
                    }
                    guard result == 0 else { throw failure(error) }
                    read += UInt64(chunk.count)
                    let done = processed + read
                    progress?(OperationProgress(fractionCompleted: total > 0 ? 0.95 * Double(done) / Double(total) : 0,
                                                currentItem: item.archivePath, processedBytes: done, totalBytes: total))
                }
                guard read == item.fileSize else { throw ArchiveOperationError.inputChanged(item.archivePath) }
            }
            processed += item.fileSize
            progress?(OperationProgress(fractionCompleted: total > 0 ? 0.95 * Double(processed) / Double(total) : 0.95 * Double(index + 1) / Double(max(items.count, 1)),
                                        currentItem: item.archivePath, processedBytes: processed, totalBytes: total))
        }
        try controller?.checkpoint()
        guard bolt_la_7z_close(writer, &error, error.count) == 0 else { throw failure(error) }
        try controller?.checkpoint()
        try ArchiveOutputTransaction.publish([stagedArchive], to: [output])
        progress?(OperationProgress(fractionCompleted: 1, currentItem: output.lastPathComponent, processedBytes: total, totalBytes: total))
    }

    private static func failure(_ error: [CChar]) -> BoltZipError {
        .compressionFailed(error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
    }
}
