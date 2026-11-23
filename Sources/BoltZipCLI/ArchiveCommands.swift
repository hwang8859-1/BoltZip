import BoltZipCore
import Foundation

enum ArchiveCommands {
    static func create(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let targetArg = URL(fileURLWithPath: arguments.positional[0])
        let inputs = arguments.positional.dropFirst().map { URL(fileURLWithPath: $0) }

        let targetIsDir = (try? targetArg.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let fmt: ArchiveFormat
        if let explicitFmt = arguments.options["format"].flatMap(parseArchiveFormat) {
            fmt = explicitFmt
        } else if let detected = ArchiveFormat.detect(from: targetArg) {
            fmt = detected
        } else {
            fmt = .zip
        }

        let splitBytes = try arguments.splitVolumeSizeBytes()
        let resolvedOutURL: URL
        if targetIsDir {
            let baseStem = BoltArchiveEngine.defaultBaseStem(for: inputs, format: fmt)
            resolvedOutURL = BoltArchiveEngine.makeOutputURL(
                stem: baseStem,
                format: fmt,
                splitVolumeSizeBytes: splitBytes,
                in: targetArg,
                deduplicating: true
            )
        } else {
            resolvedOutURL = targetArg
        }

        let password = try CLIPasswordInput.resolveInitialPassword(arguments: arguments, promptForCreationIfNeeded: true)
        let workers = try arguments.workerCount()

        let algorithm = arguments.options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? fmt.defaultAlgorithm
        let level = arguments.options["level"].flatMap(Int.init) ?? algorithm.defaultLevel

        let excludes = arguments.excludePatterns
        let excludeJunk = !arguments.flags.contains("keep-junk")
        let preserveSymlinks = !arguments.flags.contains("no-symlinks")
        let encryption = arguments.resolvedEncryption(password: password, defaultEncryption: .none)
        let encryptNames = arguments.flags.contains("encrypt-filenames")

        let opts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: password,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: excludeJunk,
            excludePatterns: excludes,
            encoding: arguments.options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .utf8,
            archiveComment: arguments.options["comment"] ?? "",
            workerCount: workers,
            preserveSymlinks: preserveSymlinks,
            encryptFileNames: encryptNames
        )
        let created = try BoltArchiveEngine.createArchive(from: inputs, to: resolvedOutURL, options: opts, progress: progress)
        print("Created: \(created.map(\.lastPathComponent).joined(separator: ", "))")
        return 0
    }

    static func extract(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard let (archiveURL, destURL) = arguments.extractionPaths else {
            printUsage()
            return 1
        }
        let mode: ExtractMode
        switch arguments.options["mode"] {
        case "here": mode = .here
        case "subfolder": mode = .subfolder
        default: mode = .smart
        }
        let overwrite = try arguments.overwritePolicy()
        let enc = arguments.encoding
        let workers = try arguments.workerCount()
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)
        let out = try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            let opts = ExtractOptions(
                destinationURL: destURL,
                mode: mode,
                overwritePolicy: overwrite,
                password: password,
                encoding: enc,
                stripMacJunk: arguments.stripMacJunk,
                workerCount: workers,
                restoreSymlinks: arguments.restoreSymlinks
            )
            return try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: progress)
        }
        print("Extracted to: \(out.path)")
        return 0
    }

    static func extractFlat(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard let (archiveURL, destURL) = arguments.extractionPaths else {
            printUsage()
            return 1
        }
        let overwrite = try arguments.overwritePolicy()
        let enc = arguments.encoding
        let workers = try arguments.workerCount()
        let fm = FileManager.default
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        let flatCount = try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            let archiveSources = try BoltArchiveEngine.extractionSourceURLs(archiveURL: archiveURL, password: password)
            let staging = fm.temporaryDirectory.appendingPathComponent("boltzip-flat-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            let opts = ExtractOptions(
                destinationURL: staging,
                mode: .here,
                overwritePolicy: .overwrite,
                password: password,
                encoding: enc,
                stripMacJunk: arguments.stripMacJunk,
                workerCount: workers,
                restoreSymlinks: false
            )
            _ = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: progress)
            return try publishFlatFiles(from: staging, to: destURL, policy: overwrite, protectedSources: archiveSources)
        }
        print("Extracted \(flatCount) file(s) flat to: \(destURL.path)")
        return 0
    }

    static func add(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        let inputs = arguments.positional.dropFirst().map { URL(fileURLWithPath: $0) }
        let targetFolder = arguments.options["target"] ?? ""
        let detected = try ArchiveFormat.requireForReading(from: archiveURL)
        let (algorithm, level) = arguments.compression(default: detected.defaultAlgorithm)
        let workers = try arguments.workerCount()
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)

        try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            var ops: [ArchiveEditOperation] = [.addItems(urls: inputs, targetFolder: targetFolder)]
            if let comment = arguments.options["comment"] {
                ops.append(.setComment(comment))
            }
            let editOpts = CreateArchiveOptions(
                format: detected,
                algorithm: algorithm,
                level: level,
                encryption: arguments.resolvedEncryption(password: password),
                password: password,
                excludeMacJunk: arguments.stripMacJunk,
                excludePatterns: arguments.excludePatterns,
                workerCount: workers,
                preserveSymlinks: arguments.restoreSymlinks,
                encryptFileNames: arguments.flags.contains("encrypt-filenames")
            )
            try BoltArchiveEngine.editArchive(at: archiveURL, operations: ops, options: editOpts, encoding: arguments.encoding, progress: progress)
        }
        print("Updated archive: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func remove(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        let paths = Set(arguments.positional.dropFirst())
        let detected = try ArchiveFormat.requireForReading(from: archiveURL)
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)

        try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            let opts = CreateArchiveOptions(
                format: detected,
                algorithm: detected.defaultAlgorithm,
                encryption: arguments.resolvedEncryption(password: password),
                password: password
            )
            try BoltArchiveEngine.editArchive(at: archiveURL, operations: [.deletePaths(paths)], options: opts, encoding: arguments.encoding, progress: progress)
        }
        print("Removed \(paths.count) target(s) from: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func makeDirectory(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        let detected = try ArchiveFormat.requireForReading(from: archiveURL)
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)

        try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            let opts = CreateArchiveOptions(
                format: detected,
                algorithm: detected.defaultAlgorithm,
                encryption: arguments.resolvedEncryption(password: password),
                password: password
            )
            try BoltArchiveEngine.editArchive(at: archiveURL, operations: [.createFolder(path: arguments.positional[1])], options: opts, encoding: arguments.encoding, progress: progress)
        }
        print("Created folder '\(arguments.positional[1])' in: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func move(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 3 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        let detected = try ArchiveFormat.requireForReading(from: archiveURL)
        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)

        try CLIPasswordInput.withPasswordRetry(
            archiveURL: archiveURL,
            initialPassword: initialPassword,
            allowTTYPrompt: arguments.allowInteractivePasswordPrompt
        ) { password in
            let opts = CreateArchiveOptions(
                format: detected,
                algorithm: detected.defaultAlgorithm,
                encryption: arguments.resolvedEncryption(password: password),
                password: password
            )
            try BoltArchiveEngine.editArchive(at: archiveURL, operations: [.renamePath(oldPath: arguments.positional[1], newPath: arguments.positional[2])], options: opts, encoding: arguments.encoding, progress: progress)
        }
        print("Renamed '\(arguments.positional[1])' -> '\(arguments.positional[2])' in: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func recover(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let sourceURL = URL(fileURLWithPath: arguments.positional[0])
        let outputURL = URL(fileURLWithPath: arguments.positional[1])
        var initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)
        if initialPassword == nil && arguments.flags.contains("ask-password") {
            guard let entered = CLIPasswordInput.promptTTY(message: "Enter password for \(sourceURL.lastPathComponent): ") else {
                throw BoltZipError.cancelled
            }
            initialPassword = entered
        }

        let report = try BoltArchiveEngine.recoverZip(
            at: sourceURL,
            to: outputURL,
            password: initialPassword,
            encoding: arguments.encoding,
            progress: progress
        )

        if arguments.useJSON {
            try printJSON([
                "source": report.sourceURL.lastPathComponent,
                "recoveredArchive": report.recoveredArchiveURL?.path as Any,
                "totalScanned": report.totalScannedCount,
                "recoveredCount": report.recoveredCount,
                "unrecoverableCount": report.unrecoverableCount,
                "usedLocalHeaderFallbackScan": report.usedLocalHeaderFallbackScan,
                "recoveredEntries": report.recoveredEntries.map(\.path),
                "unrecoverableEntries": report.unrecoverableEntries.map {
                    ["entry": $0.entryPath, "reason": $0.reason]
                }
            ])
            return report.recoveredCount > 0 ? 0 : 2
        }

        print("ZIP Recovery: scanned \(report.totalScannedCount), recovered \(report.recoveredCount), unrecoverable \(report.unrecoverableCount)\(report.usedLocalHeaderFallbackScan ? " [Local Header Fallback Scan]" : "")")
        if let saved = report.recoveredArchiveURL {
            print("Saved recovered archive: \(saved.path)")
        }
        for fail in report.unrecoverableEntries {
            print("  [UNRECOVERABLE] \(fail.entryPath) — \(fail.reason)")
        }
        return report.recoveredCount > 0 ? 0 : 2
    }

    private static func parseArchiveFormat(_ raw: String) -> ArchiveFormat? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch lower {
        case "zip": return .zip
        case "7z", "sevenzip": return .sevenZip
        case "tar": return .tar
        case "tar.gz", "tgz", "targz": return .tarGz
        case "tar.zst", "tzst", "tarzst": return .tarZst
        case "tar.xz", "txz", "tarxz": return .tarXz
        case "tar.bz2", "tbz2", "tbz", "tarbz2": return .tarBz2
        case "tar.lz4", "tlz4", "tarlz4": return .tarLz4
        case "gz", "gzip": return .gz
        case "xz": return .xz
        default:
            return ArchiveFormat(rawValue: lower).flatMap { ArchiveFormat.creatableFormats.contains($0) ? $0 : nil }
        }
    }

    private static func publishFlatFiles(from staging: URL, to destURL: URL, policy: OverwritePolicy,
                                         protectedSources: [URL]) throws -> Int {
        let fm = FileManager.default
        var flatCount = 0
        if let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            for case let fileURL as URL in enumerator {
                let rv = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if rv.isDirectory == true || rv.isSymbolicLink == true { continue }
                if try BoltArchiveEngine.publishExtractedFile(from: fileURL,
                                                             to: destURL.appendingPathComponent(fileURL.lastPathComponent),
                                                             under: destURL, policy: policy, protectedSources: protectedSources) != nil {
                    flatCount += 1
                }
            }
        }
        return flatCount
    }
}
