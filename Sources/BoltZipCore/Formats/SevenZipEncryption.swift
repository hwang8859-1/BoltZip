import Darwin
import Foundation

enum SevenZipEncryption {
    static func create(
        from inputs: [URL],
        to output: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws {
        guard let password = options.password, !password.isEmpty else {
            throw ArchiveOperationError.invalidSevenZipPassword
        }
        try SevenZipCommand.validatePassword(password)
        try controller?.checkpoint()
        try ArchiveOutputTransaction.validate(output)
        let canonicalOutput = output.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(output.lastPathComponent)
        let items = try ArchiveInputCollector.collect(from: inputs, excludeMacJunk: options.excludeMacJunk,
                                                      preserveSymlinks: options.preserveSymlinks, excluding: [output, canonicalOutput],
                                                      controller: controller)
        let total = try items.reduce(UInt64(0)) { try ArchiveByteCount.checkedSum($0, $1.fileSize) }
        let command = try createArguments(options)
        let stage = try ArchiveOutputTransaction.makeStage(for: output)
        let fm = FileManager.default
        var directories: [(URL, ArchiveInputItem)] = []
        defer {
            for (directory, _) in directories {
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
            try? fm.removeItem(at: stage)
        }
        let archive = stage.appendingPathComponent("archive.7z")
        let inputStage = stage.appendingPathComponent("inputs", isDirectory: true)
        try fm.createDirectory(at: inputStage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

        var files: [(url: URL, item: ArchiveInputItem, followsSymbolicLink: Bool)] = []
        var symbolicLinks: [ArchiveInputItem] = []
        var followStagedLinks = false
        for item in items {
            try controller?.checkpoint()
            let target = try stagedItemURL(item, in: inputStage)
            if item.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                directories.append((target, item))
            } else if item.isSymbolicLink {
                symbolicLinks.append(item)
            } else {
                guard let source = item.fileURL else { throw ArchiveOperationError.inputChanged(item.archivePath) }
                try validateSize(of: source, for: item, followsSymbolicLink: false)
                do {
                    try fm.linkItem(at: source, to: target)
                    files.append((target, item, false))
                } catch {
                    // Hard links may be unavailable across volumes. A temporary link references the original bytes.
                    try fm.createSymbolicLink(at: target, withDestinationURL: source.standardizedFileURL)
                    files.append((target, item, true))
                    followStagedLinks = true
                }
            }
        }

        if !followStagedLinks {
            for item in symbolicLinks {
                try controller?.checkpoint()
                try stageSymbolicLink(item, in: inputStage, createParent: false)
            }
        }
        for (directory, item) in directories.reversed() {
            try controller?.checkpoint()
            try fm.setAttributes([.posixPermissions: NSNumber(value: item.permissions), .modificationDate: item.modifiedDate],
                                 ofItemAtPath: directory.path)
        }
        for (file, item, followsSymbolicLink) in files {
            try controller?.checkpoint()
            try validateSize(of: file, for: item, followsSymbolicLink: followsSymbolicLink)
        }

        progress?(OperationProgress(fractionCompleted: 0.05, currentItem: output.lastPathComponent, totalBytes: total))
        let result = try SevenZipCommand.run(
            command + [followStagedLinks ? "-snl-" : "-snl", "--", archive.path],
            password: password, directory: inputStage, controller: controller
        )
        try check(result, archive: output, password: password)
        for (file, item, followsSymbolicLink) in files {
            try controller?.checkpoint()
            try validateSize(of: file, for: item, followsSymbolicLink: followsSymbolicLink)
        }

        if followStagedLinks && !symbolicLinks.isEmpty {
            // When staging spans volumes, preserve original symlinks in a separate pass so they are never followed.
            let linkStage = stage.appendingPathComponent("links", isDirectory: true)
            var names: [String] = []
            for item in symbolicLinks {
                try controller?.checkpoint()
                try stageSymbolicLink(item, in: linkStage, createParent: true)
                // The list reader trims unquoted whitespace.
                names.append("\"" + item.archivePath + "\"")
            }
            let listFile = stage.appendingPathComponent("links.txt")
            try Data((names.joined(separator: "\n") + "\n").utf8).write(to: listFile)
            let result = try SevenZipCommand.run(
                // Paths in this list are validated relative paths. Keep their directory prefixes.
                command + ["-snl", "-spf", archive.path, "@" + listFile.path],
                password: password, passwordPromptCount: 2, directory: linkStage, controller: controller
            )
            try check(result, archive: output, password: password)
        }

        try controller?.checkpoint()
        try ArchiveOutputTransaction.publish([archive], to: [output])
        progress?(OperationProgress(fractionCompleted: 1, currentItem: output.lastPathComponent,
                                    processedBytes: total, totalBytes: total))
    }

    static func list(archiveURL: URL, password: String?, matching selectors: [String] = [],
                     controller: ArchiveTaskController? = nil) throws -> [ArchiveEntry] {
        let result = try SevenZipCommand.run(
            ["l", "-t7z", "-slt", "-ba", "-sccUTF-8", "-bsp0", "-spd", "-ssc", "--", archiveURL.standardizedFileURL.path] + selectors,
            password: password, controller: controller
        )
        try check(result, archive: archiveURL, password: password)
        return try parseEntries(result.stdout, archive: archiveURL)
    }

    static func check(_ result: SevenZipCommand.Result, archive: URL, password: String?) throws {
        guard result.status != 0 else { return }
        let name = archive.lastPathComponent
        let errors = String(decoding: result.stderr, as: UTF8.self).components(separatedBy: "\n")
        let wrongPassword = errors.contains {
            ($0.hasPrefix("ERROR: ") && $0.hasSuffix(" : Cannot open encrypted archive. Wrong password?"))
                || $0.hasPrefix("ERROR: Data Error in encrypted file. Wrong password? : ")
                || $0.hasPrefix("ERROR: CRC Failed in encrypted file. Wrong password? : ")
        }
        if password?.isEmpty != false && (wrongPassword ||
            String(decoding: result.stdout, as: UTF8.self).components(separatedBy: "\n").contains("Enter password:")) {
            throw BoltZipError.passwordRequired(name)
        }
        if wrongPassword {
            throw BoltZipError.wrongPassword(name)
        }
        if errors.contains(where: { $0.hasPrefix("ERROR: Unsupported Method : ") }) {
            throw BoltZipError.unsupportedFormat(ArchiveFormat.sevenZip.displayName)
        }
        // Child output can include archive-controlled file names. Do not surface it as a diagnostic.
        throw BoltZipError.externalToolFailed("7-Zip (\(result.status)) · \(name)")
    }

    private static func parseEntries(_ data: Data, archive: URL) throws -> [ArchiveEntry] {
        let name = archive.lastPathComponent
        guard let content = String(data: data, encoding: .utf8) else {
            throw BoltZipError.invalidArchive(name)
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var entries: [ArchiveEntry] = []
        var seen: Set<String> = []
        var fields: [String: String] = [:]
        var allowsPrompt = true

        func endRecord() throws {
            guard !fields.isEmpty else { return }
            let entry = try parseEntry(fields, archive: name, dateFormatter: dateFormatter)
            let entryKey = entry.isDirectory ? String(entry.path.dropLast()) : entry.path
            guard seen.insert(entryKey).inserted else {
                throw BoltZipError.entryAlreadyExists(entry.path)
            }
            entries.append(entry)
            fields.removeAll(keepingCapacity: true)
        }

        for line in content.components(separatedBy: "\n") {
            if line.isEmpty {
                try endRecord()
                continue
            }
            if allowsPrompt && line == "Enter password:" {
                allowsPrompt = false
                continue
            }
            allowsPrompt = false
            guard let delimiter = line.range(of: " = ") else { throw BoltZipError.invalidArchive(name) }
            let field = String(line[..<delimiter.lowerBound])
            guard fields.isEmpty == (field == "Path"), fields[field] == nil else {
                throw BoltZipError.invalidArchive(name)
            }
            fields[field] = String(line[delimiter.upperBound...])
        }
        try endRecord()
        return entries
    }

    private static func parseEntry(_ fields: [String: String], archive: String, dateFormatter: DateFormatter) throws -> ArchiveEntry {
        guard let path = fields["Path"], !path.isEmpty, !hasUnsupportedPathCharacter(path),
              let size = fields["Size"].flatMap(UInt64.init), let packed = fields["Packed Size"],
              let encrypted = fields["Encrypted"], encrypted == "+" || encrypted == "-",
              let method = fields["Method"] else {
            throw BoltZipError.invalidArchive(archive)
        }
        let attributes = fields["Attributes", default: ""].split(separator: " ")
        let mode = attributes.last.flatMap(posixMode)
        let isDirectory = fields["Folder"] == "+" || mode?.kind == "d"
            || attributes.first.map { !$0.hasPrefix("-") && $0.contains("D") } == true
        let isSymlink = mode?.kind == "l"
        let packedSize = packed.isEmpty ? 0 : UInt64(packed)
        let crc = fields["CRC", default: ""]
        let crc32 = crc.isEmpty ? 0 : UInt32(crc, radix: 16)
        guard let packedSize, let crc32, !isDirectory || !isSymlink else {
            throw BoltZipError.invalidArchive(archive)
        }
        let normalizedPath = ArchiveEntry.normalizePath(path, isDirectory: isDirectory)
        guard !normalizedPath.isEmpty else { throw BoltZipError.invalidArchive(archive) }
        let modified = fields["Modified"].flatMap { dateFormatter.date(from: String($0.prefix(19))) }
        let codecs = method.split(separator: " ").filter { !$0.hasPrefix("7zAES") }.joined(separator: " ")
        return ArchiveEntry(
            path: normalizedPath,
            isDirectory: isDirectory,
            isSymbolicLink: isSymlink,
            uncompressedSize: isDirectory ? 0 : size,
            compressedSize: packedSize,
            compressionMethodName: isDirectory ? "" : (codecs.isEmpty || codecs == "Copy" ? CompressionAlgorithm.store.shortName : codecs),
            crc32: crc32,
            modifiedDate: modified ?? Date(timeIntervalSince1970: 0),
            permissions: mode?.permissions ?? (isDirectory ? 0o755 : 0o644),
            isEncrypted: encrypted == "+",
            encryptionLabel: encrypted == "+" ? "AES-256" : "",
            rawPathBytes: Data(path.utf8)
        )
    }

    private static func posixMode(_ mode: Substring) -> (kind: Character, permissions: UInt16)? {
        guard mode.count == 10, let kind = mode.first, "-dl".contains(kind) else { return nil }
        var permissions: UInt16 = 0
        for (index, character) in mode.dropFirst().enumerated() {
            if "rwxst".contains(character) {
                permissions |= 1 << (8 - index)
            }
        }
        return (kind, permissions)
    }

    private static func hasUnsupportedPathCharacter(_ path: String) -> Bool {
        path.utf8.contains { $0 == 0 || $0 == 10 || $0 == 13 }
    }

    private static func createArguments(_ options: CreateArchiveOptions) throws -> [String] {
        let codec: String
        switch options.algorithm {
        case .xz: codec = "LZMA2"
        case .bzip2: codec = "BZip2"
        case .deflate: codec = "Deflate"
        case .store: codec = "Copy"
        default: throw BoltZipError.unsupportedFormat(options.algorithm.shortName)
        }
        let minimum = options.algorithm == .xz ? 0 : 1
        let level = options.algorithm == .store ? 0 : min(9, max(minimum, options.level))
        let workers = BoltConcurrency.resolvedWorkerCount(override: options.workerCount)
        return ["a", "-t7z", "-p", options.encryptFileNames ? "-mhe=on" : "-mhe=off",
                "-m0=\(codec)", "-mx=\(level)", "-mmt=\(workers)", "-ms=off", "-spd", "-ssc",
                "-scsUTF-8", "-sccUTF-8", "-bsp0"]
    }

    private static func stagedItemURL(_ item: ArchiveInputItem, in stage: URL) throws -> URL {
        let path = item.isDirectory ? String(item.archivePath.dropLast()) : item.archivePath
        guard !path.isEmpty, !hasUnsupportedPathCharacter(path), path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BoltZipError.pathTraversalDetected(item.archivePath)
        }
        return stage.appendingPathComponent(path, isDirectory: item.isDirectory)
    }

    private static func stageSymbolicLink(_ item: ArchiveInputItem, in stage: URL, createParent: Bool) throws {
        let target = try stagedItemURL(item, in: stage)
        guard let link = item.symlinkTarget else { throw ArchiveOperationError.inputChanged(item.archivePath) }
        if createParent {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: link)
        let date = item.modifiedDate.timeIntervalSince1970
        let seconds = floor(date)
        let stamp = timeval(tv_sec: Int(seconds), tv_usec: Int32((date - seconds) * 1_000_000))
        let stampPair = [stamp, stamp]
        let status = target.withUnsafeFileSystemRepresentation { path in
            stampPair.withUnsafeBufferPointer { stamps in
                path.map { lutimes($0, stamps.baseAddress) } ?? -1
            }
        }
        guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private static func validateSize(of url: URL, for item: ArchiveInputItem, followsSymbolicLink: Bool) throws {
        var info = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return fstatat(AT_FDCWD, path, &info, followsSymbolicLink ? 0 : AT_SYMLINK_NOFOLLOW)
        }
        guard status == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0,
              UInt64(info.st_size) == item.fileSize else {
            throw ArchiveOperationError.inputChanged(item.archivePath)
        }
    }
}
