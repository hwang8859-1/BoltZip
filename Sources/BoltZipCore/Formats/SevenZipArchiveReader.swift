import Foundation

enum SevenZipArchiveReader {
    static func readEntry(at url: URL, path: String, entries: [ArchiveEntry],
                          password: String?, exactOutputSize: UInt64?, format: ArchiveFormat = .sevenZip,
                          hardLinkTargets: [String: String] = [:]) throws -> Data {
        let normalized = ArchiveEntry.normalizePath(path, isDirectory: false)
        guard let entry = entries.first(where: { $0.path == normalized && !$0.isDirectory }) else {
            throw BoltZipError.entryNotFound(path)
        }
        try verifyDeclaredSize(entry, exactSize: exactOutputSize)
        let source = try payloadEntry(for: entry, in: entriesByPath(entries), hardLinks: hardLinkTargets)
        var data = Data()
        try streamEntries(at: url, entries: [source], password: password, format: format, controller: nil) { _, chunk in
            data.append(chunk)
        }
        return data
    }

    static func extract(
        at url: URL, entries: [ArchiveEntry], to root: URL, selectedPaths: Set<String>?,
        overwritePolicy: OverwritePolicy, password: String?, stripMacJunk: Bool, restoreSymlinks: Bool, exactEntrySize: UInt64?,
        topLevelDirRenameMap: [String: String], controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?, format: ArchiveFormat = .sevenZip,
        linkTargets: [String: String] = [:], hardLinkTargets: [String: String] = [:],
        protectedSourcePaths: Set<String> = []
    ) throws {
        let selected = entries.filter { entry in
            (!entry.isSymbolicLink || restoreSymlinks) &&
            (!stripMacJunk || !MacJunkFilter.isJunk(path: entry.path)) &&
            (selectedPaths.map { $0.isEmpty || ArchiveExtractionDestination.pathMatchesSelection(entry.path, selectedPaths: $0) } ?? true)
        }
        let fm = FileManager.default
        let destinations = try selected.compactMap { entry -> (entry: ArchiveEntry, destination: URL)? in
            if !entry.isDirectory && !entry.isSymbolicLink { try verifyDeclaredSize(entry, exactSize: exactEntrySize) }
            let raw = try selector(for: entry).replacingOccurrences(of: "\\", with: "/")
            guard !raw.hasPrefix("/"), !raw.split(separator: "/").contains("..") else {
                throw BoltZipError.pathTraversalDetected(raw)
            }
            let outputPath = ArchiveExtractionDestination.remapTopLevelFolder(in: entry.path, renameMap: topLevelDirRenameMap)
            let destination = try ArchiveExtractionDestination.safeDestinationURL(for: outputPath, under: root)
            if overwritePolicy == .skip, !entry.isDirectory, (try? fm.attributesOfItem(atPath: destination.path)) != nil {
                return nil
            }
            return (entry, destination)
        }

        let byPath = entriesByPath(entries)
        var sourcesByOutput: [String: String] = [:]
        var sourceUses: [String: Int] = [:]
        for (entry, _) in destinations where !entry.isDirectory && linkTargets[entry.path] == nil {
            let source = try payloadEntry(for: entry, in: byPath, hardLinks: hardLinkTargets)
            sourcesByOutput[entry.path] = source.path
            sourceUses[source.path, default: 0] += 1
        }
        let payloads = entries.filter { sourceUses[$0.path] != nil }
        let total = try payloads.reduce(UInt64(0)) { try ArchiveByteCount.checkedSum($0, $1.uncompressedSize) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: root.appendingPathComponent("payload"), under: root)
        defer { try? fm.removeItem(at: stage) }

        var processed: UInt64 = 0
        var nextIndex = 0
        var handle: FileHandle?
        defer { try? handle?.close() }
        let stagedFiles = try payloads.indices.map { index -> URL in
            let file = stage.appendingPathComponent(String(index))
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return file
        }
        // Keep the 7zz selectors literal, and keep each batch below the child process' argument limit.
        var batch: [ArchiveEntry] = []
        var argumentBytes = 0
        for entry in payloads {
            let length = entry.rawPathBytes.count + 1
            if !batch.isEmpty && argumentBytes + length > 96 * 1024 {
                try writeBatch()
            }
            batch.append(entry)
            argumentBytes += length
        }
        try writeBatch()
        try controller?.checkpoint()

        let stagedByPath = Dictionary(uniqueKeysWithValues: zip(payloads.map(\.path), stagedFiles))
        for (entry, destination) in destinations where entry.isDirectory {
            try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: destination, under: root)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        for (entry, destination) in destinations where !entry.isDirectory {
            try controller?.checkpoint()
            if let target = linkTargets[entry.path] {
                try ArchiveExtractionDestination.createSafeSymlink(at: destination, target: target, under: root,
                                                                   overwritePolicy: overwritePolicy, protectedSourcePaths: protectedSourcePaths)
                continue
            }
            guard let sourcePath = sourcesByOutput[entry.path], let staged = stagedByPath[sourcePath] else {
                throw BoltZipError.entryNotFound(entry.path)
            }
            if entry.isSymbolicLink {
                guard entry.uncompressedSize <= 4096, let target = String(data: try Data(contentsOf: staged), encoding: .utf8) else {
                    throw BoltZipError.pathTraversalDetected(entry.path)
                }
                try ArchiveExtractionDestination.createSafeSymlink(at: destination, target: target, under: root,
                                                                   overwritePolicy: overwritePolicy, protectedSourcePaths: protectedSourcePaths)
            } else if let final = try ArchiveExtractionDestination.prepareExtractTargetURL(initialURL: destination, under: root, policy: overwritePolicy) {
                let attributes = byPath[sourcePath] ?? entry
                try? fm.setAttributes([.posixPermissions: NSNumber(value: attributes.permissions),
                                      .modificationDate: attributes.modifiedDate], ofItemAtPath: staged.path)
                let item: URL
                if sourceUses[sourcePath, default: 0] > 1 {
                    item = stage.appendingPathComponent(UUID().uuidString)
                    do {
                        try fm.linkItem(at: staged, to: item)
                    } catch {
                        try fm.copyItem(at: staged, to: item)
                    }
                } else {
                    item = staged
                }
                try ArchiveExtractionDestination.commitExtractedItem(item, to: final, under: root,
                                                                      policy: overwritePolicy, protectedSourcePaths: protectedSourcePaths,
                                                                      controller: controller)
            }
        }

        func writeBatch() throws {
            guard !batch.isEmpty else { return }
            let offset = nextIndex
            try streamEntries(at: url, entries: batch, password: password, format: format, controller: controller) { index, chunk in
                if handle == nil || nextIndex != offset + index {
                    try handle?.close()
                    nextIndex = offset + index
                    handle = try FileHandle(forWritingTo: stagedFiles[nextIndex])
                }
                try handle?.write(contentsOf: chunk)
                processed += UInt64(chunk.count)
                progress?(OperationProgress(fractionCompleted: Double(processed) / Double(max(1, total)),
                                            currentItem: payloads[nextIndex].path, processedBytes: processed, totalBytes: total))
            }
            try handle?.close()
            handle = nil
            nextIndex = offset + batch.count
            batch.removeAll(keepingCapacity: true)
            argumentBytes = 0
        }
    }

    static func testIntegrity(at url: URL, entries: [ArchiveEntry], password: String?,
                              format: ArchiveFormat = .sevenZip, archiveName: String? = nil) throws -> IntegrityReport {
        let start = Date()
        if password?.isEmpty != false && entries.contains(where: \.isEncrypted) {
            throw BoltZipError.passwordRequired(url.lastPathComponent)
        }
        let result = try SevenZipCommand.run(
            ["t"] + SevenZipArchiveListing.typeArguments(for: format)
                + ["-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", url.standardizedFileURL.path],
            password: password
        )
        try SevenZipArchiveListing.check(result, archive: url, password: password, format: format)
        let passed = entries.filter { !$0.isDirectory }.map {
            IntegrityEntryResult(path: $0.path, status: .passed, detail: "")
        }
        return IntegrityReport(archiveName: archiveName ?? url.lastPathComponent, totalEntries: passed.count, passedCount: passed.count,
                               failedCount: 0, skippedEncryptedCount: 0, elapsedSeconds: -start.timeIntervalSinceNow, results: passed)
    }

    private static func entriesByPath(_ entries: [ArchiveEntry]) -> [String: ArchiveEntry] {
        Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func payloadEntry(for entry: ArchiveEntry, in entries: [String: ArchiveEntry],
                                     hardLinks: [String: String]) throws -> ArchiveEntry {
        var source = entry
        var seen: Set<String> = []
        while let path = hardLinks[source.path] {
            guard seen.insert(source.path).inserted, let next = entries[path],
                  !next.isDirectory, !next.isSymbolicLink,
                  next.uncompressedSize == entry.uncompressedSize else {
                throw BoltZipError.invalidArchive(entry.path)
            }
            source = next
        }
        return source
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
        at url: URL, entries: [ArchiveEntry], password: String?, format: ArchiveFormat, controller: ArchiveTaskController?,
        write: @escaping (Int, Data) throws -> Void
    ) throws {
        if password?.isEmpty != false && entries.contains(where: \.isEncrypted) {
            throw BoltZipError.passwordRequired(url.lastPathComponent)
        }
        // A selector that matches nothing can still exit successfully. An empty payload
        // cannot be distinguished from that result by size or CRC.
        let emptyEntries = entries.filter { $0.uncompressedSize == 0 }
        if !emptyEntries.isEmpty {
            let matched = try SevenZipArchiveListing.list(archiveURL: url, password: password, format: format,
                                                         matching: emptyEntries.map(selector(for:)), controller: controller)
            let matchedPaths = Set(matched.map(\.rawPathBytes))
            if let missing = emptyEntries.first(where: { !matchedPaths.contains($0.rawPathBytes) }) {
                throw BoltZipError.entryNotFound(missing.path)
            }
        }
        var mismatch: String?
        let result = try SevenZipCommand.run(
            ["x"] + SevenZipArchiveListing.typeArguments(for: format)
                + ["-so", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", url.standardizedFileURL.path]
                + entries.map(selector(for:)),
            password: password, controller: controller, consumeOutput: { reader in
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
                // Encrypted RAR5 may store a password-dependent checksum. The helper verifies it internally.
                if (format != .rar || !entry.isEncrypted) && entry.crc32 != 0 && entry.crc32 != crc {
                    mismatch = mismatch ?? entry.path
                }
            }
            if let excess = try reader.read(upToCount: 1), !excess.isEmpty {
                mismatch = mismatch ?? url.lastPathComponent
            }
        })
        try SevenZipArchiveListing.check(result, archive: url, password: password, format: format)
        if let mismatch {
            throw BoltZipError.corruptedEntry(entry: mismatch, detail: "CRC / size")
        }
    }
}
