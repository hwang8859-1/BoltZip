import BoltZipCore
import Foundation

enum ArchiveCommands {
    static func create(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let outURL = URL(fileURLWithPath: arguments.positional[0])
        let inputs = arguments.positional.dropFirst().map { URL(fileURLWithPath: $0) }
        let fmt = ArchiveFormat.detect(from: outURL) ?? .zip
        let (algorithm, level) = arguments.compression(default: fmt.defaultAlgorithm)
        let splitBytes = arguments.options["split"].flatMap(UInt64.init).map { $0 * 1024 * 1024 }
        let workers = try arguments.workerCount()
        let opts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: arguments.encryption,
            password: arguments.password,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: arguments.stripMacJunk,
            archiveComment: arguments.options["comment"] ?? "",
            workerCount: workers,
            preserveSymlinks: arguments.restoreSymlinks,
            encryptFileNames: arguments.flags.contains("encrypt-filenames")
        )
        let created = try BoltArchiveEngine.createArchive(from: inputs, to: outURL, options: opts, progress: progress)
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
        let opts = ExtractOptions(
            destinationURL: destURL,
            mode: mode,
            overwritePolicy: overwrite,
            password: arguments.password,
            encoding: enc,
            stripMacJunk: arguments.stripMacJunk,
            workerCount: workers,
            restoreSymlinks: arguments.restoreSymlinks
        )
        let out = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: progress)
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
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        let staging = fm.temporaryDirectory.appendingPathComponent("boltzip-flat-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let opts = ExtractOptions(
            destinationURL: staging,
            mode: .here,
            overwritePolicy: .overwrite,
            password: arguments.password,
            encoding: enc,
            stripMacJunk: arguments.stripMacJunk,
            workerCount: workers,
            restoreSymlinks: false
        )
        _ = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts, progress: progress)
        let flatCount = try publishFlatFiles(from: staging, to: destURL, policy: overwrite)
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
        let (algorithm, level) = arguments.compression(default: .deflate)
        let workers = try arguments.workerCount()
        var ops: [ZipEditOperation] = [.addItems(urls: inputs, targetFolder: targetFolder)]
        if let comment = arguments.options["comment"] {
            ops.append(.setComment(comment))
        }
        let editOpts = CreateArchiveOptions(
            format: .zip,
            algorithm: algorithm,
            level: level,
            encryption: arguments.encryption,
            password: arguments.password,
            excludeMacJunk: arguments.stripMacJunk,
            workerCount: workers,
            preserveSymlinks: arguments.restoreSymlinks
        )
        try BoltArchiveEngine.editZip(at: archiveURL, operations: ops, options: editOpts, progress: progress)
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
        try BoltArchiveEngine.editZip(at: archiveURL, operations: [.deletePaths(paths)], progress: progress)
        print("Removed \(paths.count) target(s) from: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func makeDirectory(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 2 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        try BoltArchiveEngine.editZip(at: archiveURL, operations: [.createFolder(path: arguments.positional[1])], progress: progress)
        print("Created folder '\(arguments.positional[1])' in: \(archiveURL.lastPathComponent)")
        return 0
    }

    static func move(_ arguments: CLIArguments, progress: CLIProgress?) throws -> Int32 {
        guard arguments.positional.count >= 3 else {
            printUsage()
            return 1
        }
        let archiveURL = URL(fileURLWithPath: arguments.positional[0])
        try BoltArchiveEngine.editZip(at: archiveURL, operations: [.renamePath(oldPath: arguments.positional[1], newPath: arguments.positional[2])], progress: progress)
        print("Renamed '\(arguments.positional[1])' -> '\(arguments.positional[2])' in: \(archiveURL.lastPathComponent)")
        return 0
    }

    private static func publishFlatFiles(from staging: URL, to destURL: URL, policy: OverwritePolicy) throws -> Int {
        let fm = FileManager.default
        var flatCount = 0
        if let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            for case let fileURL as URL in enumerator {
                let rv = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if rv.isDirectory == true || rv.isSymbolicLink == true { continue }
                try BoltArchiveEngine.publishExtractedFile(from: fileURL,
                                                          to: destURL.appendingPathComponent(fileURL.lastPathComponent),
                                                          under: destURL, policy: policy)
                flatCount += 1
            }
        }
        return flatCount
    }
}
