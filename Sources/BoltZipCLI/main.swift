import BoltZipCore
import Darwin
import Foundation

func printUsage() {
    print("""
    BoltZip CLI v\(BoltZipVersion.current) (Open-Source macOS Compression Engine)
    Usage:
      boltzip a <output.zip|tar.zst|tar.gz|tar.xz|tar.bz2|tar.lz4|tar|7z> <input1> [input2...] [--algo deflate|zstd|bzip2|xz|lz4|store] [--level N] [--password PW] [--aes256|--zipcrypto] [--split MB] [--comment TEXT] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip x <archive> [dest_dir] [--mode smart|here|subfolder] [--overwrite overwrite|skip|rename] [--password PW] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk] [--no-symlinks]
      boltzip e <archive> [dest_dir] [--overwrite overwrite|skip|rename] [--password PW] [--encoding auto|utf8|gb18030|big5|shiftjis|euckr|cp437] [--threads auto|N] [--keep-junk]
      boltzip add <archive.zip> <input...> [--target folder/] [--algo deflate|zstd|bzip2|store] [--level N] [--password PW] [--aes256|--zipcrypto] [--comment TEXT]
      boltzip rm <archive.zip> <entryPath1> [entryPath2...]
      boltzip mkdir <archive.zip> <folderPath>
      boltzip mv <archive.zip> <oldPath> <newPath>
      boltzip l <archive> [--encoding auto|gb18030|big5|shiftjis|euckr|utf8|cp437] [--password PW] [--json]
      boltzip t <archive> [--password PW] [--threads auto|N] [--json]
      boltzip associate [--status] [--restore] [--include-iso]
      boltzip bench [--threads auto|N] [--json]
      boltzip engines
      boltzip version
    """)
}

func parseWorkerCountOption(_ options: [String: String]) throws -> Int? {
    guard let raw = (options["threads"] ?? options["cores"])?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    if raw.caseInsensitiveCompare("auto") == .orderedSame {
        return 0
    }
    guard let parsed = Int(raw), parsed >= 1 else {
        throw BoltZipError.ioError("Invalid --threads value '\(raw)'. Expected 'auto' or an integer >= 1.")
    }
    return parsed
}

func parseOverwritePolicy(_ raw: String?) throws -> OverwritePolicy {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
        return .overwrite
    }
    switch raw {
    case "overwrite": return .overwrite
    case "skip": return .skip
    case "rename": return .rename
    default:
        throw BoltZipError.ioError("Invalid --overwrite value '\(raw)'. Expected overwrite, skip, or rename.")
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

func makeTTYProgressHandler(enabled: Bool) -> (@Sendable (OperationProgress) -> Void)? {
    guard enabled && isatty(STDERR_FILENO) != 0 else { return nil }
    let iso8601Lock = NSLock()
    return { prog in
        iso8601Lock.lock()
        defer { iso8601Lock.unlock() }
        let width = 24
        let frac = min(1.0, max(0.0, prog.fractionCompleted))
        let filled = Int((frac * Double(width)).rounded(.down))
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: max(0, width - filled))
        let pct = Int((frac * 100.0).rounded())
        let item = prog.currentItem.isEmpty ? "" : " \(prog.currentItem)"
        let line = "\r\u{1B}[K[\(bar)] \(String(format: "%3d", pct))%\(item)"
        fputs(line, stderr)
        if frac >= 1.0 {
            fputs("\r\u{1B}[K", stderr)
        }
        fflush(stderr)
    }
}

func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

func runAssociateCommand(flags: Set<String>) async -> Int32 {
    #if canImport(AppKit) && canImport(UniformTypeIdentifiers)
    if flags.contains("status") {
        let appPath = ArchiveAssociationService.resolveBoltZipAppURL()?.path ?? "Not found"
        let statuses = ArchiveAssociationService.currentStatuses()
        let maxExtLen = max(36, statuses.map { $0.group.extensionsSubtitle.count }.max() ?? 36)
        print("BoltZip.app: \(appPath)")
        for status in statuses {
            let marker = status.isBoltZipDefault ? "[BoltZip]" : "[\(status.currentAppName)]"
            let paddedID = status.group.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            let paddedExts = status.group.extensionsSubtitle.padding(toLength: maxExtLen + 2, withPad: " ", startingAt: 0)
            print("  • \(paddedID) \(paddedExts) -> \(marker)")
        }
        return 0
    }

    let restore = flags.contains("restore")
    let targets: [ArchiveAssociationGroup] = (flags.contains("include-iso") || restore)
        ? ArchiveAssociationGroup.allCases
        : ArchiveAssociationGroup.commonArchiveGroups

    if let err = await ArchiveAssociationService.setDefault(for: targets, toBoltZip: !restore) {
        fputs("Error updating system file associations: \(err)\n", stderr)
        return 1
    }

    let summary = restore
        ? "Restored system default handlers for \(targets.count) archive groups."
        : "Set BoltZip as system default handler for \(targets.count) archive groups."
    print(summary)
    for status in ArchiveAssociationService.currentStatuses() {
        let marker = status.isBoltZipDefault ? "BoltZip" : status.currentAppName
        let paddedID = status.group.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  • \(paddedID) -> \(marker)")
    }
    return 0
    #else
    fputs("Error: File association management requires macOS AppKit.\n", stderr)
    return 1
    #endif
}

func moveFlatExtractedFile(from srcURL: URL, toFlatDir destDir: URL, policy: OverwritePolicy) throws {
    try BoltArchiveEngine.publishExtractedFile(from: srcURL,
                                              to: destDir.appendingPathComponent(srcURL.lastPathComponent),
                                              under: destDir, policy: policy)
}

func collectAndFlattenExtractedFiles(from staging: URL, to destURL: URL, policy: OverwritePolicy) throws -> Int {
    let fm = FileManager.default
    var flatCount = 0
    if let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
        for case let fileURL as URL in enumerator {
            let rv = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if rv.isDirectory == true || rv.isSymbolicLink == true { continue }
            try moveFlatExtractedFile(from: fileURL, toFlatDir: destURL, policy: policy)
            flatCount += 1
        }
    }
    return flatCount
}

func parseArgs() async -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        printUsage()
        return 0
    }

    let booleanFlags: Set<String> = [
        "aes256", "zipcrypto", "keep-junk", "no-symlinks",
        "status", "restore", "include-iso", "json", "quiet"
    ]

    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []
    var i = 1
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if booleanFlags.contains(key) {
                flags.insert(key)
                i += 1
            } else if i + 1 < args.count {
                options[key] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        } else {
            positional.append(a)
            i += 1
        }
    }

    let useJSON = flags.contains("json")
    let ttyProgress = makeTTYProgressHandler(enabled: !useJSON && !flags.contains("quiet"))

    do {
        switch cmd {
        case "version", "--version", "-v":
            print("BoltZip \(BoltZipVersion.current)")
            return 0

        case "associate":
            return await runAssociateCommand(flags: flags)

        case "engines":
            for eng in CompressionCodec.engineVersions() {
                print("• \(eng.name) v\(eng.version) [\(eng.license)]")
            }
            print("• Hardware CPU cores: \(BoltConcurrency.hardwareCoreCount) | Effective workers: \(BoltConcurrency.resolvedWorkerCount()) (\(BoltConcurrency.preference.isAuto ? "auto" : "manual"))")
            return 0

        case "bench":
            let workers = try parseWorkerCountOption(options)
            let resolvedWorkers = BoltConcurrency.resolvedWorkerCount(override: workers)
            let results = try BenchmarkRunner.run(workerCount: workers)
            if useJSON {
                let items: [[String: Any]] = results.map {
                    [
                        "algorithm": $0.algorithm.rawValue,
                        "name": $0.algorithm.shortName,
                        "level": $0.level,
                        "ratioPercent": ($0.ratioPercent * 10).rounded() / 10,
                        "compressMBps": ($0.compressMBps * 100).rounded() / 100,
                        "decompressMBps": ($0.decompressMBps * 100).rounded() / 100
                    ]
                }
                try printJSON([
                    "version": BoltZipVersion.current,
                    "hardwareCores": BoltConcurrency.hardwareCoreCount,
                    "workers": resolvedWorkers,
                    "results": items
                ])
                return 0
            }
            print("Running BoltZip open-source codec benchmark (2 MB structured sample, \(resolvedWorkers) worker(s))...")
            for r in results {
                let line = String(
                    format: "%-8@ | lvl %-2d | ratio %5.1f%% | comp %7.1f MB/s | decomp %7.1f MB/s",
                    r.algorithm.shortName as NSString,
                    r.level,
                    r.ratioPercent,
                    r.compressMBps,
                    r.decompressMBps
                )
                print(line)
            }
            return 0

        case "l":
            guard let archivePath = positional.first else {
                printUsage()
                return 1
            }
            let enc = options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
            let listing = try BoltArchiveEngine.inspect(
                archiveURL: URL(fileURLWithPath: archivePath),
                encoding: enc,
                password: options["password"]
            )
            if useJSON {
                let fmt = ISO8601DateFormatter()
                let entryDicts: [[String: Any]] = listing.entries.map {
                    [
                        "path": $0.path,
                        "isDirectory": $0.isDirectory,
                        "isSymbolicLink": $0.isSymbolicLink,
                        "uncompressedSize": $0.uncompressedSize,
                        "compressedSize": $0.compressedSize,
                        "method": $0.compressionMethodName,
                        "crc32": String(format: "%08X", $0.crc32),
                        "modifiedAt": fmt.string(from: $0.modifiedDate),
                        "isEncrypted": $0.isEncrypted,
                        "encryptionLabel": $0.encryptionLabel
                    ]
                }
                try printJSON([
                    "archive": listing.archiveURL.lastPathComponent,
                    "format": listing.format.rawValue,
                    "comment": listing.comment,
                    "totalEntries": listing.entries.count,
                    "totalUncompressedBytes": listing.totalUncompressedBytes,
                    "totalCompressedBytes": listing.totalCompressedBytes,
                    "overallRatioPercent": (listing.overallCompressionRatioPercent * 10).rounded() / 10,
                    "isSplitVolume": listing.isSplitVolume,
                    "entries": entryDicts
                ])
                return 0
            }
            print("Archive: \(listing.archiveURL.lastPathComponent) [\(listing.format.displayName)]")
            if !listing.comment.isEmpty {
                print("Comment: \(listing.comment)")
            }
            print("Entries: \(listing.entries.count) | Uncompressed: \(formatBytes(listing.totalUncompressedBytes)) | Ratio: \(String(format: "%.1f%%", listing.overallCompressionRatioPercent))")
            for e in listing.entries {
                let lock = e.isEncrypted ? " [\(e.encryptionLabel)]" : ""
                let tag = e.isSymbolicLink ? " [symlink]" : ""
                print(String(format: "%10llu  %-10@  %@%@%@", e.uncompressedSize, e.compressionMethodName as NSString, e.path as NSString, tag as NSString, lock as NSString))
            }
            return 0

        case "t":
            guard let archivePath = positional.first else {
                printUsage()
                return 1
            }
            let workers = try parseWorkerCountOption(options)
            let report = try BoltArchiveEngine.testIntegrity(
                archiveURL: URL(fileURLWithPath: archivePath),
                password: options["password"],
                workerCount: workers,
                progress: ttyProgress
            )
            if useJSON {
                let resDicts: [[String: Any]] = report.results.map {
                    [
                        "path": $0.path,
                        "status": $0.status.rawValue,
                        "detail": $0.detail
                    ]
                }
                try printJSON([
                    "archive": report.archiveName,
                    "totalEntries": report.totalEntries,
                    "passedCount": report.passedCount,
                    "failedCount": report.failedCount,
                    "skippedEncryptedCount": report.skippedEncryptedCount,
                    "elapsedSeconds": (report.elapsedSeconds * 1000).rounded() / 1000,
                    "results": resDicts
                ])
                return report.failedCount == 0 ? 0 : 2
            }
            print("Integrity Test: \(report.archiveName) -> passed \(report.passedCount)/\(report.totalEntries), failed \(report.failedCount), missingPassword \(report.skippedEncryptedCount) (\(String(format: "%.2fs", report.elapsedSeconds)))")
            return report.failedCount == 0 ? 0 : 2

        case "x":
            guard let archivePath = positional.first else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: archivePath)
            let destURL = positional.count > 1 ? URL(fileURLWithPath: positional[1]) : archiveURL.deletingLastPathComponent()
            let mode: ExtractMode
            switch options["mode"] {
            case "here": mode = .here
            case "subfolder": mode = .subfolder
            default: mode = .smart
            }
            let overwrite = try parseOverwritePolicy(options["overwrite"])
            let enc = options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
            let workers = try parseWorkerCountOption(options)
            let opts = ExtractOptions(
                destinationURL: destURL,
                mode: mode,
                overwritePolicy: overwrite,
                password: options["password"],
                encoding: enc,
                stripMacJunk: !flags.contains("keep-junk"),
                workerCount: workers,
                restoreSymlinks: !flags.contains("no-symlinks")
            )
            let out = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: ttyProgress)
            print("Extracted to: \(out.path)")
            return 0

        case "e":
            guard let archivePath = positional.first else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: archivePath)
            let destURL = positional.count > 1 ? URL(fileURLWithPath: positional[1]) : archiveURL.deletingLastPathComponent()
            let overwrite = try parseOverwritePolicy(options["overwrite"])
            let enc = options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
            let workers = try parseWorkerCountOption(options)
            let fm = FileManager.default
            try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

            let staging = fm.temporaryDirectory.appendingPathComponent("boltzip-flat-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            let opts = ExtractOptions(
                destinationURL: staging,
                mode: .here,
                overwritePolicy: .overwrite,
                password: options["password"],
                encoding: enc,
                stripMacJunk: !flags.contains("keep-junk"),
                workerCount: workers,
                restoreSymlinks: false
            )
            _ = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: ttyProgress)
            let flatCount = try collectAndFlattenExtractedFiles(from: staging, to: destURL, policy: overwrite)
            print("Extracted \(flatCount) file(s) flat to: \(destURL.path)")
            return 0

        case "a":
            guard positional.count >= 2 else {
                printUsage()
                return 1
            }
            let outURL = URL(fileURLWithPath: positional[0])
            let inputs = positional.dropFirst().map { URL(fileURLWithPath: $0) }
            let fmt = ArchiveFormat.detect(from: outURL) ?? .zip
            let algo = options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? fmt.defaultAlgorithm
            let lvl = options["level"].flatMap(Int.init) ?? algo.defaultLevel
            let pw = options["password"]
            let encMethod: EncryptionMethod = pw == nil ? .none : (flags.contains("zipcrypto") ? .zipCrypto : .aes256)
            let splitBytes = options["split"].flatMap(UInt64.init).map { $0 * 1024 * 1024 }
            let workers = try parseWorkerCountOption(options)
            let opts = CreateArchiveOptions(
                format: fmt,
                algorithm: algo,
                level: lvl,
                encryption: encMethod,
                password: pw,
                splitVolumeSizeBytes: splitBytes,
                excludeMacJunk: !flags.contains("keep-junk"),
                archiveComment: options["comment"] ?? "",
                workerCount: workers,
                preserveSymlinks: !flags.contains("no-symlinks")
            )
            let created = try BoltArchiveEngine.createArchive(from: inputs, to: outURL, options: opts, progress: ttyProgress)
            print("Created: \(created.map(\.lastPathComponent).joined(separator: ", "))")
            return 0

        case "add":
            guard positional.count >= 2 else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: positional[0])
            let inputs = positional.dropFirst().map { URL(fileURLWithPath: $0) }
            let targetFolder = options["target"] ?? ""
            let algo = options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? .deflate
            let lvl = options["level"].flatMap(Int.init) ?? algo.defaultLevel
            let pw = options["password"]
            let encMethod: EncryptionMethod = pw == nil ? .none : (flags.contains("zipcrypto") ? .zipCrypto : .aes256)
            let workers = try parseWorkerCountOption(options)
            var ops: [ZipEditOperation] = [.addItems(urls: inputs, targetFolder: targetFolder)]
            if let comment = options["comment"] {
                ops.append(.setComment(comment))
            }
            let editOpts = CreateArchiveOptions(
                format: .zip,
                algorithm: algo,
                level: lvl,
                encryption: encMethod,
                password: pw,
                excludeMacJunk: !flags.contains("keep-junk"),
                workerCount: workers,
                preserveSymlinks: !flags.contains("no-symlinks")
            )
            try BoltArchiveEngine.editZip(at: archiveURL, operations: ops, options: editOpts, progress: ttyProgress)
            print("Updated archive: \(archiveURL.lastPathComponent)")
            return 0

        case "rm":
            guard positional.count >= 2 else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: positional[0])
            let paths = Set(positional.dropFirst())
            try BoltArchiveEngine.editZip(at: archiveURL, operations: [.deletePaths(paths)], progress: ttyProgress)
            print("Removed \(paths.count) target(s) from: \(archiveURL.lastPathComponent)")
            return 0

        case "mkdir":
            guard positional.count >= 2 else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: positional[0])
            try BoltArchiveEngine.editZip(at: archiveURL, operations: [.createFolder(path: positional[1])], progress: ttyProgress)
            print("Created folder '\(positional[1])' in: \(archiveURL.lastPathComponent)")
            return 0

        case "mv":
            guard positional.count >= 3 else {
                printUsage()
                return 1
            }
            let archiveURL = URL(fileURLWithPath: positional[0])
            try BoltArchiveEngine.editZip(at: archiveURL, operations: [.renamePath(oldPath: positional[1], newPath: positional[2])], progress: ttyProgress)
            print("Renamed '\(positional[1])' -> '\(positional[2])' in: \(archiveURL.lastPathComponent)")
            return 0

        default:
            printUsage()
            return 1
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

exit(await parseArgs())
