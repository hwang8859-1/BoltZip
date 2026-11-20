import Foundation

enum SevenZipEncryptedReader {
    static func readEntry(at url: URL, path: String, entries: [ArchiveEntry],
                          password: String?, exactOutputSize: UInt64?) throws -> Data {
        let normalized = ArchiveEntry.normalizePath(path, isDirectory: false)
        guard let entry = entries.first(where: { $0.path == normalized && !$0.isDirectory }) else {
            throw BoltZipError.entryNotFound(path)
        }
        try verifyDeclaredSize(entry, exactSize: exactOutputSize)
        var data = Data()
        try streamEntries(at: url, entries: [entry], password: password, controller: nil) { _, chunk in
            data.append(chunk)
        }
        return data
    }

    static func extract(
        at url: URL, entries: [ArchiveEntry], to root: URL, selectedPaths: Set<String>?,
        overwritePolicy: OverwritePolicy, password: String?, stripMacJunk: Bool, restoreSymlinks: Bool, exactEntrySize: UInt64?,
        topLevelDirRenameMap: [String: String], controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws {
        let selected = entries.filter { entry in
            (!entry.isSymbolicLink || restoreSymlinks) &&
            (!stripMacJunk || !MacJunkFilter.isJunk(path: entry.path)) &&
            (selectedPaths.map { $0.isEmpty || ArchiveExtractionDestination.pathMatchesSelection(entry.path, selectedPaths: $0) } ?? true)
        }
        let destinations = try selected.map { entry -> URL in
            if !entry.isDirectory && !entry.isSymbolicLink { try verifyDeclaredSize(entry, exactSize: exactEntrySize) }
            let raw = try selector(for: entry).replacingOccurrences(of: "\\", with: "/")
            guard !raw.hasPrefix("/"), !raw.split(separator: "/").contains("..") else {
                throw BoltZipError.pathTraversalDetected(raw)
            }
            let outputPath = ArchiveExtractionDestination.remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
            return try ArchiveExtractionDestination.safeDestinationURL(for: outputPath, under: root)
        }

        let items = zip(selected, destinations).filter { !$0.0.isDirectory }
        let total = try items.reduce(UInt64(0)) { try ArchiveByteCount.checkedSum($0, $1.0.uncompressedSize) }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: root.appendingPathComponent("payload"), under: root)
        defer { try? fm.removeItem(at: stage) }

        var processed: UInt64 = 0
        var nextIndex = 0
        var handle: FileHandle?
        defer { try? handle?.close() }
        let stagedFiles = try items.enumerated().map { index, item -> URL in
            let file = stage.appendingPathComponent(String(index))
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return file
        }
        // Keep the 7zz selectors literal, and keep each batch below the child process' argument limit.
        var batch: [ArchiveEntry] = []
        var argumentBytes = 0
        for (entry, _) in items {
            let length = entry.rawPathBytes.count + 1
            if !batch.isEmpty && argumentBytes + length > 96 * 1024 {
                try writeBatch()
            }
            batch.append(entry)
            argumentBytes += length
        }
        try writeBatch()
        try controller?.checkpoint()

        for (entry, destination) in zip(selected, destinations) where entry.isDirectory {
            try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: destination, under: root)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        for (index, item) in items.enumerated() {
            try controller?.checkpoint()
            let (entry, destination) = item
            if entry.isSymbolicLink {
                guard entry.uncompressedSize <= 4096,
                      let target = String(data: try Data(contentsOf: stagedFiles[index]), encoding: .utf8) else {
                    throw BoltZipError.pathTraversalDetected(entry.path)
                }
                try ArchiveExtractionDestination.createSafeSymlink(at: destination, target: target, under: root, overwritePolicy: overwritePolicy)
            } else if let final = try ArchiveExtractionDestination.prepareExtractTargetURL(initialURL: destination, under: root, policy: overwritePolicy) {
                try? fm.setAttributes([.posixPermissions: NSNumber(value: entry.permissions),
                                      .modificationDate: entry.modifiedDate], ofItemAtPath: stagedFiles[index].path)
                try ArchiveExtractionDestination.commitExtractedItem(stagedFiles[index], to: final, under: root,
                                                                      policy: overwritePolicy, controller: controller)
            }
        }

        func writeBatch() throws {
            guard !batch.isEmpty else { return }
            let offset = nextIndex
            try streamEntries(at: url, entries: batch, password: password, controller: controller) { index, chunk in
                if handle == nil || nextIndex != offset + index {
                    try handle?.close()
                    nextIndex = offset + index
                    handle = try FileHandle(forWritingTo: stagedFiles[nextIndex])
                }
                try handle?.write(contentsOf: chunk)
                processed += UInt64(chunk.count)
                progress?(OperationProgress(fractionCompleted: Double(processed) / Double(max(1, total)),
                                            currentItem: items[nextIndex].0.path, processedBytes: processed, totalBytes: total))
            }
            try handle?.close()
            handle = nil
            nextIndex = offset + batch.count
            batch.removeAll(keepingCapacity: true)
            argumentBytes = 0
        }
    }

    static func testIntegrity(at url: URL, entries: [ArchiveEntry], password: String?) throws -> IntegrityReport {
        let start = Date()
        if password?.isEmpty != false && entries.contains(where: \.isEncrypted) {
            throw BoltZipError.passwordRequired(url.lastPathComponent)
        }
        let result = try SevenZipCommand.run(
            ["t", "-t7z", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", url.standardizedFileURL.path],
            password: password
        )
        try SevenZipEncryption.check(result, archive: url, password: password)
        let passed = entries.filter { !$0.isDirectory }.map {
            IntegrityEntryResult(path: $0.path, status: .passed, detail: "")
        }
        return IntegrityReport(archiveName: url.lastPathComponent, totalEntries: passed.count, passedCount: passed.count,
                               failedCount: 0, skippedEncryptedCount: 0, elapsedSeconds: -start.timeIntervalSinceNow, results: passed)
    }

    private static func selector(for entry: ArchiveEntry) throws -> String {
        guard let raw = String(data: entry.rawPathBytes, encoding: .utf8), !raw.isEmpty,
              !raw.utf8.contains(0) else { throw BoltZipError.invalidArchive(entry.path) }
        return raw
    }

    private static func verifyDeclaredSize(_ entry: ArchiveEntry, exactSize: UInt64?) throws {
        if let exactSize, exactSize != entry.uncompressedSize {
            throw BoltZipError.corruptedEntry(entry: entry.path, detail: "Decoded size does not match the declared entry size")
        }
    }

    private static func streamEntries(
        at url: URL, entries: [ArchiveEntry], password: String?, controller: ArchiveTaskController?,
        write: @escaping (Int, Data) throws -> Void
    ) throws {
        if password?.isEmpty != false && entries.contains(where: \.isEncrypted) {
            throw BoltZipError.passwordRequired(url.lastPathComponent)
        }
        // A selector that matches nothing can still exit successfully. An empty payload
        // cannot be distinguished from that result by size or CRC.
        let emptyEntries = entries.filter { $0.uncompressedSize == 0 }
        if !emptyEntries.isEmpty {
            let matched = try SevenZipEncryption.list(archiveURL: url, password: password,
                                                       matching: emptyEntries.map(selector(for:)), controller: controller)
            let matchedPaths = Set(matched.map(\.rawPathBytes))
            if let missing = emptyEntries.first(where: { !matchedPaths.contains($0.rawPathBytes) }) {
                throw BoltZipError.entryNotFound(missing.path)
            }
        }
        var mismatch: String?
        let result = try SevenZipCommand.run(
            ["x", "-t7z", "-so", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", url.standardizedFileURL.path]
                + entries.map(selector(for:)),
            password: password, controller: controller
        ) { reader in
            // 7zz concatenates the selected payloads in archive order.
            for (index, entry) in entries.enumerated() {
                var remaining = entry.uncompressedSize
                var crc: UInt32 = 0
                while remaining > 0 {
                    try controller?.checkpoint()
                    guard let chunk = try reader.read(upToCount: Int(min(remaining, 1024 * 1024))), !chunk.isEmpty else {
                        mismatch = entry.path
                        return
                    }
                    remaining -= UInt64(chunk.count)
                    crc = CompressionCodec.crc32(chunk, initial: crc)
                    try write(index, chunk)
                }
                if entry.crc32 != 0 && entry.crc32 != crc { mismatch = mismatch ?? entry.path }
            }
            if let excess = try reader.read(upToCount: 1), !excess.isEmpty {
                mismatch = mismatch ?? url.lastPathComponent
            }
        }
        try SevenZipEncryption.check(result, archive: url, password: password)
        if let mismatch {
            throw BoltZipError.corruptedEntry(entry: mismatch, detail: "7z CRC / size")
        }
    }
}
