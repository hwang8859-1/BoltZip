import BoltZipCore
import Foundation

enum ArchiveCommands {
    private static func resolvePreset(for arguments: CLIArguments) throws -> CompressionProfile? {
        guard let key = arguments.presetName?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        guard let profile = CompressionProfileStore.shared.find(namedOrID: key) else {
            throw BoltZipError.entryNotFound("Preset '\(key)'")
        }
        return profile
    }

    static func create(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let targetArg = URL(fileURLWithPath: arguments.positional[0])
        let inputs = arguments.positional.dropFirst().map { URL(fileURLWithPath: $0) }
        let preset = try resolvePreset(for: arguments)

        let targetIsDir = (try? targetArg.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let fmt: ArchiveFormat
        if let explicitFmt = arguments.options["format"].flatMap(parseArchiveFormat) {
            fmt = explicitFmt
        } else if targetIsDir, let preset {
            fmt = preset.format
        } else if let detected = ArchiveFormat.detect(from: targetArg) {
            fmt = detected
        } else {
            fmt = preset?.format ?? .zip
        }

        let splitBytes = try arguments.splitVolumeSizeBytes() ?? preset?.splitVolumeSizeBytes
        let effectivePattern = arguments.namePattern ?? preset?.namingTemplate ?? "{name}"
        let resolvedOutURL: URL
        if targetIsDir {
            var tempProfile = preset ?? CompressionProfile(name: "cli", format: fmt)
            tempProfile.format = fmt
            tempProfile.namingTemplate = effectivePattern
            tempProfile.splitVolumeSizeBytes = splitBytes
            resolvedOutURL = tempProfile.resolveOutputURL(for: inputs, in: targetArg)
        } else if let pattern = arguments.namePattern {
            let parent = targetArg.deletingLastPathComponent()
            let baseStem = CompressionProfile.defaultBaseStem(for: inputs, format: fmt)
            let stem = CompressionProfile.resolveBaseStem(template: pattern, defaultStem: baseStem, format: fmt)
            resolvedOutURL = CompressionProfile.makeOutputURL(
                stem: stem,
                format: fmt,
                splitVolumeSizeBytes: splitBytes,
                in: parent,
                deduplicating: false
            )
        } else {
            resolvedOutURL = targetArg
        }

        let password = try CLIPasswordInput.resolveInitialPassword(arguments: arguments, promptForCreationIfNeeded: true)
        let workers = try arguments.workerCount()

        let defaultAlgo = preset?.algorithm ?? fmt.defaultAlgorithm
        let algorithm = arguments.options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? defaultAlgo
        let level = arguments.options["level"].flatMap(Int.init) ?? (arguments.options["algo"] != nil ? algorithm.defaultLevel : (preset?.level ?? algorithm.defaultLevel))

        var excludes = preset?.excludePatterns ?? []
        excludes.append(contentsOf: arguments.excludePatterns)

        let excludeJunk = arguments.flags.contains("keep-junk") ? false : (preset?.excludeMacJunk ?? true)
        let preserveSymlinks = arguments.flags.contains("no-symlinks") ? false : (preset?.preserveSymlinks ?? true)
        let encryption = arguments.resolvedEncryption(password: password, defaultEncryption: preset?.encryption ?? .none)
        let encryptNames = arguments.flags.contains("encrypt-filenames")
            || ((preset?.encryptFileNames ?? false) && encryption == .aes256 && password != nil)

        let opts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: password,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: excludeJunk,
            excludePatterns: excludes,
            encoding: arguments.options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? preset?.encoding ?? .utf8,
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

    static func convert(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard !arguments.positional.isEmpty else {
            printUsage()
            return 1
        }
        let destPath = arguments.options["to"] ?? "."
        let destURL = URL(fileURLWithPath: destPath)
        let sources = arguments.positional.map { URL(fileURLWithPath: $0) }
        let preset = try resolvePreset(for: arguments)

        let fmt: ArchiveFormat
        if let rawFmt = arguments.options["format"] {
            guard let parsed = parseArchiveFormat(rawFmt) else {
                throw BoltZipError.unsupportedFormat(rawFmt)
            }
            fmt = parsed
        } else {
            fmt = preset?.format ?? .zip
        }

        let initialPassword = try CLIPasswordInput.resolveInitialPassword(arguments: arguments)
        let workers = try arguments.workerCount()
        let splitBytes = try arguments.splitVolumeSizeBytes() ?? preset?.splitVolumeSizeBytes
        let overwrite = try arguments.options["overwrite"].map { _ in try arguments.overwritePolicy() } ?? .rename

        let defaultAlgo = preset?.algorithm ?? fmt.defaultAlgorithm
        let algorithm = arguments.options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? defaultAlgo
        let level = arguments.options["level"].flatMap(Int.init) ?? (arguments.options["algo"] != nil ? algorithm.defaultLevel : (preset?.level ?? algorithm.defaultLevel))
        var excludes = preset?.excludePatterns ?? []
        excludes.append(contentsOf: arguments.excludePatterns)

        let excludeJunk = arguments.flags.contains("keep-junk") ? false : (preset?.excludeMacJunk ?? true)
        let preserveSymlinks = arguments.flags.contains("no-symlinks") ? false : (preset?.preserveSymlinks ?? true)
        let explicitEncryptFlag = arguments.flags.contains("aes256") || arguments.flags.contains("zipcrypto")
        let encryption: EncryptionMethod
        if !fmt.supportsEncryption && !explicitEncryptFlag {
            encryption = .none
        } else {
            encryption = arguments.resolvedEncryption(password: initialPassword, defaultEncryption: preset?.encryption ?? .none)
        }
        let targetPassword = encryption == .none ? nil : initialPassword
        let encryptNames = arguments.flags.contains("encrypt-filenames")
            || ((preset?.encryptFileNames ?? false) && encryption == .aes256 && targetPassword != nil)

        let targetOpts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: targetPassword,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: excludeJunk,
            excludePatterns: excludes,
            encoding: arguments.encoding == .auto ? (preset?.encoding ?? .utf8) : arguments.encoding,
            workerCount: workers,
            preserveSymlinks: preserveSymlinks,
            encryptFileNames: encryptNames
        )

        let allowPrompt = arguments.allowInteractivePasswordPrompt
        let namingTemplate = arguments.namePattern ?? preset?.namingTemplate ?? "{name}"
        let passwordProvider: (@Sendable (URL, Bool) throws -> String?)? = allowPrompt ? { @Sendable archiveURL, wrong in
            let prompt = wrong ? "Incorrect password for \(archiveURL.lastPathComponent). Retry: " : "Enter password for \(archiveURL.lastPathComponent): "
            return CLIPasswordInput.promptTTY(message: prompt)
        } : nil
        let report = try BoltArchiveEngine.convertArchives(
            sources: sources,
            destinationDirectory: destURL,
            options: targetOpts,
            sourcePassword: initialPassword,
            sourcePasswordProvider: passwordProvider,
            overwritePolicy: overwrite,
            encoding: arguments.encoding,
            namingTemplate: namingTemplate,
            progress: progress
        )

        if arguments.useJSON {
            try printJSON([
                "destinationDirectory": destURL.path,
                "succeededCount": report.succeededCount,
                "failedCount": report.failedCount,
                "results": report.results.map { item in
                    [
                        "source": item.sourceURL.path,
                        "destinations": item.destinationURLs.map(\.path),
                        "entryCount": item.entryCount,
                        "succeeded": item.succeeded,
                        "error": item.error?.localizedDescription as Any
                    ]
                }
            ])
            return report.failedCount == 0 ? 0 : 2
        }

        print("Converted \(report.succeededCount)/\(report.results.count) archive(s) in \(String(format: "%.2fs", report.elapsedSeconds))")
        for item in report.results {
            if item.succeeded {
                let outs = item.destinationURLs.map(\.lastPathComponent).joined(separator: ", ")
                print("  [OK] \(item.sourceURL.lastPathComponent) -> \(outs)")
            } else {
                print("  [FAIL] \(item.sourceURL.lastPathComponent): \(item.error?.localizedDescription ?? "Unknown error")")
            }
        }
        return report.failedCount == 0 ? 0 : 2
    }

    static func preset(_ arguments: CLIArguments) throws -> Int32 {
        let store = CompressionProfileStore.shared
        let sub = arguments.positional.first?.lowercased() ?? "list"
        switch sub {
        case "list":
            let all = store.load()
            if arguments.useJSON {
                let items: [[String: Any]] = all.map {
                    [
                        "id": $0.id.uuidString,
                        "name": $0.name,
                        "format": $0.format.rawValue,
                        "algorithm": $0.algorithm.rawValue,
                        "level": $0.level,
                        "splitVolumeSizeBytes": $0.splitVolumeSizeBytes as Any,
                        "excludePatterns": $0.excludePatterns,
                        "namingTemplate": $0.namingTemplate,
                        "isDefaultQuickPreset": $0.isDefaultQuickPreset
                    ]
                }
                try printJSON(items)
                return 0
            }
            if all.isEmpty {
                print("No saved presets.")
                return 0
            }
            for p in all {
                let quick = p.isDefaultQuickPreset ? " [quick]" : ""
                let split = p.splitVolumeSizeBytes.map { " split=\($0 / (1024 * 1024))MB" } ?? ""
                let ex = p.excludePatterns.isEmpty ? "" : " exclude=\(p.excludePatterns.joined(separator: ","))"
                print("• \(p.name)\(quick): \(p.format.rawValue) (\(p.algorithm.rawValue) lvl \(p.level)\(split)) template='\(p.namingTemplate)'\(ex)")
            }
            return 0

        case "save":
            guard arguments.positional.count >= 2 else {
                printUsage()
                return 1
            }
            let name = arguments.positional[1]
            let fmt = try arguments.options["format"].map { raw -> ArchiveFormat in
                guard let parsed = parseArchiveFormat(raw) else { throw BoltZipError.unsupportedFormat(raw) }
                return parsed
            } ?? .zip
            let (algorithm, level) = arguments.compression(default: fmt.defaultAlgorithm)
            let enc: EncryptionMethod = arguments.flags.contains("zipcrypto") ? .zipCrypto : (arguments.flags.contains("aes256") ? .aes256 : .none)
            let split = try arguments.splitVolumeSizeBytes()
            let profile = CompressionProfile(
                name: name,
                format: fmt,
                algorithm: algorithm,
                level: level,
                encryption: enc,
                encryptFileNames: arguments.flags.contains("encrypt-filenames"),
                splitVolumeSizeBytes: split,
                excludeMacJunk: arguments.stripMacJunk,
                excludePatterns: arguments.excludePatterns,
                preserveSymlinks: arguments.restoreSymlinks,
                encoding: arguments.options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .utf8,
                namingTemplate: arguments.namePattern ?? "{name}",
                isDefaultQuickPreset: arguments.flags.contains("quick")
            )
            try store.upsert(profile)
            print("Saved preset '\(profile.name)' (\(profile.format.rawValue), \(profile.algorithm.rawValue) lvl \(profile.level))")
            return 0

        case "rm", "delete":
            guard arguments.positional.count >= 2 else {
                printUsage()
                return 1
            }
            let name = arguments.positional[1]
            let deleted = try store.delete(named: name)
            guard deleted else {
                throw BoltZipError.entryNotFound("Preset '\(name)'")
            }
            print("Removed preset '\(name)'")
            return 0

        default:
            printUsage()
            return 1
        }
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
