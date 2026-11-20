import BoltZipCore
import Foundation

enum ReportCommands {
    static func engines() -> Int32 {
        for eng in CompressionCodec.engineVersions() {
            print("• \(eng.name) v\(eng.version) [\(eng.license)]")
        }
        print("• Hardware CPU cores: \(BoltConcurrency.hardwareCoreCount) | Effective workers: \(BoltConcurrency.resolvedWorkerCount()) (\(BoltConcurrency.preference.isAuto ? "auto" : "manual"))")
        return 0
    }

    static func benchmark(_ arguments: CLIArguments) throws -> Int32 {
        let workers = try arguments.workerCount()
        let resolvedWorkers = BoltConcurrency.resolvedWorkerCount(override: workers)
        let results = try BenchmarkRunner.run(workerCount: workers)
        if arguments.useJSON {
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
    }

    static func list(_ arguments: CLIArguments) throws -> Int32 {
        guard let archivePath = arguments.positional.first else {
            printUsage()
            return 1
        }
        let enc = arguments.encoding
        let listing = try BoltArchiveEngine.inspect(
            archiveURL: URL(fileURLWithPath: archivePath),
            encoding: enc,
            password: arguments.password
        )
        if arguments.useJSON {
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
    }

    static func test(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard let archivePath = arguments.positional.first else {
            printUsage()
            return 1
        }
        let workers = try arguments.workerCount()
        let report = try BoltArchiveEngine.testIntegrity(
            archiveURL: URL(fileURLWithPath: archivePath),
            password: arguments.password,
            workerCount: workers,
            progress: progress
        )
        if arguments.useJSON {
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
            return report.isHealthy ? 0 : 2
        }
        print("Integrity Test: \(report.archiveName) -> passed \(report.passedCount)/\(report.totalEntries), failed \(report.failedCount), missingPassword \(report.skippedEncryptedCount) (\(String(format: "%.2fs", report.elapsedSeconds)))")
        return report.isHealthy ? 0 : 2
    }
}
