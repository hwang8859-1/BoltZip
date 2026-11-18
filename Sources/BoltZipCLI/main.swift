import BoltZipCore
import Foundation

func printUsage() {
    print("""
    BoltZip CLI v1.0.0 (Open-Source macOS Compression Engine)
    Usage:
      boltzip a <output.zip|tar.zst|tar.gz|tar.xz|7z> <input1> [input2...] [--algo deflate|zstd|bzip2|xz|lz4|store] [--level N] [--password PW] [--aes256|--zipcrypto] [--split MB] [--keep-junk]
      boltzip x <archive> [dest_dir] [--mode smart|here|subfolder] [--password PW] [--encoding auto|utf8|gb18030|big5|shiftjis]
      boltzip l <archive> [--encoding auto|gb18030|big5|shiftjis|utf8]
      boltzip t <archive> [--password PW]
      boltzip associate [--status] [--restore] [--include-iso]
      boltzip bench
      boltzip engines
      boltzip version
    """)
}

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
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

func parseArgs() async -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        printUsage()
        return 0
    }

    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []
    var i = 1
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if ["aes256", "zipcrypto", "keep-junk", "status", "restore", "include-iso"].contains(key) {
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

    do {
        switch cmd {
        case "version", "--version", "-v":
            print("BoltZip 1.0.0")
            return 0

        case "associate":
            return await runAssociateCommand(flags: flags)

        case "engines":
            for eng in CompressionCodec.engineVersions() {
                print("• \(eng.name) v\(eng.version) [\(eng.license)]")
            }
            return 0

        case "bench":
            print("Running BoltZip open-source codec benchmark (2 MB structured sample)...")
            let results = try BenchmarkRunner.run()
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
            let listing = try BoltArchiveEngine.inspect(archiveURL: URL(fileURLWithPath: archivePath), encoding: enc)
            print("Archive: \(listing.archiveURL.lastPathComponent) [\(listing.format.displayName)]")
            print("Entries: \(listing.entries.count) | Uncompressed: \(formatBytes(listing.totalUncompressedBytes)) | Ratio: \(String(format: "%.1f%%", listing.overallCompressionRatioPercent))")
            for e in listing.entries {
                let lock = e.isEncrypted ? " [\(e.encryptionLabel)]" : ""
                print(String(format: "%10llu  %-10@  %@%@", e.uncompressedSize, e.compressionMethodName as NSString, e.path as NSString, lock as NSString))
            }
            return 0

        case "t":
            guard let archivePath = positional.first else {
                printUsage()
                return 1
            }
            let report = try BoltArchiveEngine.testIntegrity(archiveURL: URL(fileURLWithPath: archivePath), password: options["password"])
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
            let enc = options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
            let opts = ExtractOptions(
                destinationURL: destURL,
                mode: mode,
                overwritePolicy: .overwrite,
                password: options["password"],
                encoding: enc,
                stripMacJunk: !flags.contains("keep-junk")
            )
            let out = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts)
            print("Extracted to: \(out.path)")
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
            let opts = CreateArchiveOptions(
                format: fmt,
                algorithm: algo,
                level: lvl,
                encryption: encMethod,
                password: pw,
                splitVolumeSizeBytes: splitBytes,
                excludeMacJunk: !flags.contains("keep-junk")
            )
            let created = try BoltArchiveEngine.createArchive(from: inputs, to: outURL, options: opts)
            print("Created: \(created.map(\.lastPathComponent).joined(separator: ", "))")
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
