import Darwin
import Foundation

enum SevenZipArchiveWriter {
    @discardableResult
    static func create(
        from inputs: [URL],
        to output: URL,
        options: CreateArchiveOptions,
        controller: ArchiveTaskController?,
        progress: (@Sendable (OperationProgress) -> Void)?
    ) throws -> [URL] {
        let password: String?
        if options.encryption == .aes256 {
            guard let supplied = options.password else { throw ArchiveOperationError.invalidSevenZipPassword }
            try SevenZipCommand.validatePassword(supplied)
            password = supplied
        } else {
            password = nil
        }
        try controller?.checkpoint()
        let splitSize = (options.splitVolumeSizeBytes ?? 0) >= 65536 ? options.splitVolumeSizeBytes : nil
        let baseOutput = splitSize != nil ? SevenZipVolumeDiscovery.stripSplitSuffix(from: output) : output
        try ArchiveOutputTransaction.validate(output)
        try ArchiveOutputTransaction.validate(baseOutput)
        let canonicalOutput = output.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(output.lastPathComponent)
        let canonicalBase = baseOutput.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(baseOutput.lastPathComponent)
        let items = try ArchiveInputCollector.collect(from: inputs, excludeMacJunk: options.excludeMacJunk,
                                                      preserveSymlinks: options.preserveSymlinks,
                                                      excludePatterns: options.excludePatterns,
                                                      excluding: [output, canonicalOutput, baseOutput, canonicalBase],
                                                      controller: controller)
        try validatePaths(items)
        let total = try items.reduce(UInt64(0)) { try ArchiveByteCount.checkedSum($0, $1.fileSize) }
        let command = try createArguments(options)
        let stage = try ArchiveOutputTransaction.makeStage(for: baseOutput)
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

        let needsTwoPassSymlinks = followStagedLinks && !symbolicLinks.isEmpty
        var pass1Command = command
        if let splitSize, !needsTwoPassSymlinks {
            pass1Command.append("-v\(splitSize)b")
        }

        progress?(OperationProgress(fractionCompleted: 0.05, currentItem: output.lastPathComponent, totalBytes: total))
        var progressParser = SevenZipWriteProgress()
        let result = try SevenZipCommand.run(
            pass1Command + [followStagedLinks ? "-snl-" : "-snl", "--", archive.path],
            password: password, directory: inputStage, controller: controller, observeOutput: { chunk in
                for percent in progressParser.receive(chunk) {
                    progress?(OperationProgress(
                        fractionCompleted: 0.05 + 0.9 * Double(percent) / 100,
                        currentItem: output.lastPathComponent,
                        processedBytes: UInt64((Double(total) * Double(percent) / 100).rounded(.down)),
                        totalBytes: total
                    ))
                }
            }
        )
        try SevenZipArchiveListing.check(result, archive: output, password: password)
        for (file, item, followsSymbolicLink) in files {
            try controller?.checkpoint()
            try validateSize(of: file, for: item, followsSymbolicLink: followsSymbolicLink)
        }

        if needsTwoPassSymlinks {
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
            try SevenZipArchiveListing.check(result, archive: output, password: password)
            if let splitSize {
                try splitFile(archive, in: stage, baseName: archive.lastPathComponent, partSize: splitSize, controller: controller)
                try? fm.removeItem(at: archive)
            }
        }

        try controller?.checkpoint()
        let published: [URL]
        if splitSize != nil {
            var stagedVolumes: [URL] = []
            var volumeIndex = 1
            while true {
                let part = stage.appendingPathComponent("archive.7z.\(SevenZipVolumeDiscovery.formatVolumeExtension(volumeIndex))")
                guard fm.fileExists(atPath: part.path) else { break }
                stagedVolumes.append(part)
                volumeIndex += 1
            }
            guard !stagedVolumes.isEmpty else {
                throw BoltZipError.compressionFailed("Missing generated split 7z volume")
            }
            let destinations = (1...stagedVolumes.count).map {
                baseOutput.appendingPathExtension(SevenZipVolumeDiscovery.formatVolumeExtension($0))
            }
            let inputKeys = Set(inputs.map(ArchiveExtractionDestination.pathKey))
            for destination in destinations {
                try ArchiveOutputTransaction.validate(destination)
                if inputKeys.contains(ArchiveExtractionDestination.pathKey(destination)) {
                    throw ArchiveOperationError.outputIsInput
                }
            }
            try ArchiveOutputTransaction.publish(stagedVolumes, to: destinations)
            published = destinations
        } else {
            try ArchiveOutputTransaction.publish([archive], to: [output])
            published = [output]
        }
        progress?(OperationProgress(fractionCompleted: 1, currentItem: published.first?.lastPathComponent ?? output.lastPathComponent,
                                    processedBytes: total, totalBytes: total))
        return published
    }

    static func splitFile(
        _ sourceFile: URL,
        in directory: URL,
        baseName: String,
        partSize: UInt64,
        controller: ArchiveTaskController? = nil
    ) throws {
        precondition(partSize > 0)
        let reader = try FileHandle(forReadingFrom: sourceFile)
        defer { try? reader.close() }
        let fm = FileManager.default
        var index = 1
        var currentHandle: FileHandle?
        var writtenInPart: UInt64 = 0
        defer { try? currentHandle?.close() }

        func openNextPart() throws -> FileHandle {
            try currentHandle?.close()
            let partURL = directory.appendingPathComponent("\(baseName).\(SevenZipVolumeDiscovery.formatVolumeExtension(index))")
            guard fm.createFile(atPath: partURL.path, contents: nil, attributes: [.posixPermissions: 0o644]) else {
                throw BoltZipError.ioError("Unable to create split volume \(partURL.lastPathComponent)")
            }
            let handle = try FileHandle(forWritingTo: partURL)
            currentHandle = handle
            writtenInPart = 0
            index += 1
            return handle
        }

        while true {
            try controller?.checkpoint()
            let chunk = try reader.read(upToCount: BoltConcurrency.streamChunkSize) ?? Data()
            if chunk.isEmpty { break }
            var offset = 0
            while offset < chunk.count {
                if currentHandle == nil || writtenInPart >= partSize {
                    _ = try openNextPart()
                }
                let room = Int(min(UInt64(chunk.count - offset), partSize - writtenInPart))
                let slice = chunk.subdata(in: offset..<(offset + room))
                try currentHandle?.write(contentsOf: slice)
                writtenInPart += UInt64(room)
                offset += room
            }
        }
        if index == 1 {
            _ = try openNextPart()
        }
        try currentHandle?.close()
        currentHandle = nil
    }

    static func validatePaths(_ items: [ArchiveInputItem]) throws {
        var layout: [String: Bool] = [:]
        for item in items {
            let path = ArchiveEntry.normalizePath(item.archivePath, isDirectory: false)
            guard layout.updateValue(item.isDirectory, forKey: path) == nil else {
                throw BoltZipError.entryAlreadyExists(path)
            }
        }
        for path in layout.keys {
            var parent = path[...]
            while let slash = parent.lastIndex(of: "/") {
                parent = parent[..<slash]
                if layout[String(parent)] == false { throw BoltZipError.entryAlreadyExists(String(parent)) }
            }
        }
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
        var args = ["a", "-t7z", "-m0=\(codec)", "-mx=\(level)", "-mmt=\(workers)", "-spd", "-ssc",
                    "-scsUTF-8", "-sccUTF-8", "-bso0", "-bse2", "-bsp1"]
        if options.encryption == .aes256 {
            args += ["-p", options.encryptFileNames ? "-mhe=on" : "-mhe=off", "-ms=off"]
        }
        return args
    }

    static func stagedItemURL(_ item: ArchiveInputItem, in stage: URL) throws -> URL {
        let path = item.isDirectory ? String(item.archivePath.dropLast()) : item.archivePath
        guard !path.isEmpty, !SevenZipArchiveListing.hasUnsupportedPathCharacter(path), path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BoltZipError.pathTraversalDetected(item.archivePath)
        }
        return stage.appendingPathComponent(path, isDirectory: item.isDirectory)
    }

    static func stageSymbolicLink(_ item: ArchiveInputItem, in stage: URL, createParent: Bool) throws {
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

    static func validateSize(of url: URL, for item: ArchiveInputItem, followsSymbolicLink: Bool) throws {
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

/// The helper writes each progress frame after a backspace or carriage return.
struct SevenZipWriteProgress {
    private var prefix: [UInt8] = []
    private var atFrameStart = true
    private var lastPercent = 0

    mutating func receive(_ data: Data) -> [Int] {
        var updates: [Int] = []
        for byte in data {
            if byte == 8 || byte == 13 || byte == 10 {
                prefix.removeAll(keepingCapacity: true)
                atFrameStart = true
            } else if atFrameStart {
                if byte == 37 {
                    let number = String(decoding: prefix, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                    if let percent = Int(number), percent > lastPercent, percent <= 100 {
                        updates.append(percent)
                        lastPercent = percent
                    }
                    atFrameStart = false
                } else if prefix.count < 5 && (byte == 32 || (48...57).contains(byte)) {
                    prefix.append(byte)
                } else {
                    atFrameStart = false
                }
            }
        }
        return updates
    }
}
