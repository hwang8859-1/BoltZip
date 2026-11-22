import Darwin
import Foundation

enum SevenZipEditor {
    static func editArchive(
        at archiveURL: URL,
        operations: [ArchiveEditOperation],
        options: CreateArchiveOptions = CreateArchiveOptions(),
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        for operation in operations {
            if case .setComment = operation {
                throw BoltZipError.unsupportedFormat(BoltCoreLocalization.t(
                    "仅 ZIP 格式支持归档注释",
                    "僅 ZIP 格式支援封存檔註解",
                    "Only ZIP archives support archive comments",
                    "書庫コメントは ZIP 形式のみ対応しています"
                ))
            }
        }

        try ArchiveOutputTransaction.validate(archiveURL)
        let discovery = try SevenZipVolumeDiscovery.resolve(archiveURL)
        if discovery.isSplitVolume {
            throw ArchiveOperationError.sevenZipSplitArchiveReadOnly
        }

        // Detect whether existing headers themselves require a password (-mhe=on)
        var hasEncryptedHeaders = false
        do {
            _ = try SevenZipArchiveListing.list(archiveURL: archiveURL, password: nil, format: .sevenZip)
        } catch BoltZipError.passwordRequired, BoltZipError.wrongPassword {
            hasEncryptedHeaders = true
        } catch {
            // Re-run cleanly below with caller options/password
        }

        let catalog = try SevenZipArchiveListing.catalog(archiveURL: archiveURL, password: options.password, format: .sevenZip)
        let hasEncryptedEntries = catalog.entries.contains(where: \.isEncrypted)
        if hasEncryptedEntries || hasEncryptedHeaders {
            guard let supplied = options.password, !supplied.isEmpty else {
                throw BoltZipError.passwordRequired(archiveURL.lastPathComponent)
            }
            try SevenZipCommand.validatePassword(supplied)
            if !hasEncryptedHeaders && hasEncryptedEntries {
                let verifyRes = try SevenZipCommand.run(
                    ["t", "-t7z", "-bd", "-bb0", "--", archiveURL.standardizedFileURL.path],
                    password: supplied
                )
                try SevenZipArchiveListing.check(verifyRes, archive: archiveURL, password: supplied, format: .sevenZip)
            }
        }

        guard !operations.isEmpty else {
            progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent))
            return
        }

        let fm = FileManager.default
        let stage = try ArchiveOutputTransaction.makeStage(for: archiveURL)
        defer { try? fm.removeItem(at: stage) }

        let stagedArchive = stage.appendingPathComponent("archive.7z")
        try fm.copyItem(at: archiveURL, to: stagedArchive)

        var entryIsDir: [String: Bool] = [:]
        for entry in catalog.entries {
            let clean = ArchiveEntry.normalizePath(entry.path, isDirectory: false)
            if !clean.isEmpty {
                entryIsDir[clean] = entry.isDirectory
            }
        }

        let activePassword: String?
        if hasEncryptedEntries || hasEncryptedHeaders || (options.encryption == .aes256 && !(options.password ?? "").isEmpty) {
            guard let pw = options.password, !pw.isEmpty else {
                throw ArchiveOperationError.invalidSevenZipPassword
            }
            try SevenZipCommand.validatePassword(pw)
            activePassword = pw
        } else {
            activePassword = nil
        }
        let encryptFileNames = hasEncryptedHeaders || (activePassword != nil && options.encryptFileNames)

        let totalOps = max(1, operations.count)
        for (opIdx, operation) in operations.enumerated() {
            progress?(OperationProgress(
                fractionCompleted: 0.1 + 0.8 * Double(opIdx) / Double(totalOps),
                currentItem: archiveURL.lastPathComponent
            ))

            switch operation {
            case .deletePaths(let paths):
                let targets = collectMatchingPaths(targets: paths, in: entryIsDir)
                guard !targets.isEmpty else { continue }
                try deleteEntries(targets, from: stagedArchive, password: activePassword, archiveDisplayURL: archiveURL, stage: stage, step: opIdx)
                for target in targets {
                    entryIsDir.removeValue(forKey: target)
                }

            case .renamePath(let oldPath, let newPath):
                let oldNorm = ArchiveEntry.normalizePath(oldPath, isDirectory: false)
                let newNorm = ArchiveEntry.normalizePath(newPath, isDirectory: false)
                guard !oldNorm.isEmpty, !newNorm.isEmpty else {
                    throw BoltZipError.entryNotFound(oldPath)
                }
                guard oldNorm != newNorm else { continue }
                guard !newNorm.hasPrefix(oldNorm + "/"),
                      !SevenZipArchiveListing.hasUnsupportedPathCharacter(newNorm),
                      newNorm.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                    throw BoltZipError.pathTraversalDetected(newPath)
                }

                let directIsDir = entryIsDir[oldNorm]
                let childKeys = entryIsDir.keys.filter { $0.hasPrefix(oldNorm + "/") }.sorted()
                guard directIsDir != nil || !childKeys.isEmpty else {
                    throw BoltZipError.entryNotFound(oldPath)
                }

                if let collidingAncestor = ancestorFileCollision(for: newNorm, in: entryIsDir) {
                    throw BoltZipError.entryAlreadyExists(collidingAncestor)
                }
                if entryIsDir[newNorm] != nil || entryIsDir.keys.contains(where: { $0.hasPrefix(newNorm + "/") }) {
                    throw BoltZipError.entryAlreadyExists(newPath)
                }

                var renameArgs: [String] = []
                if directIsDir != nil {
                    renameArgs.append(oldNorm)
                    renameArgs.append(newNorm)
                    if let isDir = directIsDir {
                        entryIsDir.removeValue(forKey: oldNorm)
                        entryIsDir[newNorm] = isDir
                    }
                    for child in childKeys {
                        let suffix = String(child.dropFirst(oldNorm.count))
                        if let childDir = entryIsDir.removeValue(forKey: child) {
                            entryIsDir[newNorm + suffix] = childDir
                        }
                    }
                } else {
                    for child in childKeys {
                        let suffix = String(child.dropFirst(oldNorm.count))
                        let dest = newNorm + suffix
                        renameArgs.append(child)
                        renameArgs.append(dest)
                        if let childDir = entryIsDir.removeValue(forKey: child) {
                            entryIsDir[dest] = childDir
                        }
                    }
                }

                let result = try SevenZipCommand.run(
                    ["rn", "-t7z", "-spd", "-ssc", "-scsUTF-8", "-sccUTF-8", "-bso0", "-bse2", "-bsp0", "--", stagedArchive.path] + renameArgs,
                    password: activePassword
                )
                try SevenZipArchiveListing.check(result, archive: archiveURL, password: activePassword, format: .sevenZip)

            case .createFolder(let path):
                let norm = ArchiveEntry.normalizePath(path, isDirectory: false)
                guard !norm.isEmpty else { continue }
                guard !SevenZipArchiveListing.hasUnsupportedPathCharacter(norm),
                      norm.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                    throw BoltZipError.pathTraversalDetected(path)
                }
                if let collidingAncestor = ancestorFileCollision(for: norm, in: entryIsDir) {
                    throw BoltZipError.entryAlreadyExists(collidingAncestor)
                }
                if entryIsDir[norm] == false {
                    throw BoltZipError.entryAlreadyExists(path)
                }
                if entryIsDir[norm] == true {
                    continue
                }
                let synthetic = ArchiveInputItem(
                    archivePath: norm + "/",
                    fileURL: nil,
                    isDirectory: true,
                    isSymbolicLink: false,
                    symlinkTarget: nil,
                    modifiedDate: Date(),
                    permissions: 0o755,
                    fileSize: 0
                )
                try addItems(
                    [synthetic],
                    to: stagedArchive,
                    options: options,
                    password: activePassword,
                    encryptFileNames: encryptFileNames,
                    archiveDisplayURL: archiveURL,
                    stage: stage,
                    step: opIdx,
                    entryIsDir: &entryIsDir
                )

            case .replaceEntry(let path, let fileURL):
                let norm = ArchiveEntry.normalizePath(path, isDirectory: false)
                guard entryIsDir[norm] == false else {
                    throw BoltZipError.entryNotFound(path)
                }
                let attrs = try fm.attributesOfItem(atPath: fileURL.path)
                guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
                    throw BoltZipError.entryNotFound(fileURL.lastPathComponent)
                }
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                let perms = UInt16((attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644)
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                let item = ArchiveInputItem(
                    archivePath: norm,
                    fileURL: fileURL,
                    isDirectory: false,
                    isSymbolicLink: false,
                    symlinkTarget: nil,
                    modifiedDate: modDate,
                    permissions: perms,
                    fileSize: size
                )
                try deleteEntries([norm], from: stagedArchive, password: activePassword, archiveDisplayURL: archiveURL, stage: stage, step: opIdx)
                entryIsDir.removeValue(forKey: norm)
                try addItems(
                    [item],
                    to: stagedArchive,
                    options: options,
                    password: activePassword,
                    encryptFileNames: encryptFileNames,
                    archiveDisplayURL: archiveURL,
                    stage: stage,
                    step: opIdx,
                    entryIsDir: &entryIsDir
                )

            case .addItems(let urls, let targetFolder):
                let prefix = ArchiveEntry.normalizePath(targetFolder, isDirectory: true)
                let collected = try ArchiveInputCollector.collect(
                    from: urls,
                    excludeMacJunk: options.excludeMacJunk,
                    preserveSymlinks: options.preserveSymlinks,
                    excludePatterns: options.excludePatterns,
                    excluding: [archiveURL]
                )
                let prefixed = collected.map { item -> ArchiveInputItem in
                    let fullPath = prefix.isEmpty ? item.archivePath : (prefix + item.archivePath)
                    return ArchiveInputItem(
                        archivePath: fullPath,
                        fileURL: item.fileURL,
                        isDirectory: item.isDirectory,
                        isSymbolicLink: item.isSymbolicLink,
                        symlinkTarget: item.symlinkTarget,
                        modifiedDate: item.modifiedDate,
                        permissions: item.permissions,
                        fileSize: item.fileSize
                    )
                }
                try SevenZipArchiveWriter.validatePaths(prefixed)

                // Delete exact-path type mismatches or existing items being replaced cleanly
                var deleteBeforeAdd: [String] = []
                for item in prefixed {
                    let clean = ArchiveEntry.normalizePath(item.archivePath, isDirectory: false)
                    if let existingDir = entryIsDir[clean] {
                        if existingDir != item.isDirectory {
                            let children = collectMatchingPaths(targets: [existingDir ? clean + "/" : clean], in: entryIsDir)
                            deleteBeforeAdd.append(contentsOf: children)
                        } else if !item.isDirectory {
                            deleteBeforeAdd.append(clean)
                        }
                    }
                }
                if !deleteBeforeAdd.isEmpty {
                    let uniqueDel = Array(Set(deleteBeforeAdd)).sorted()
                    try deleteEntries(uniqueDel, from: stagedArchive, password: activePassword, archiveDisplayURL: archiveURL, stage: stage, step: opIdx)
                    for target in uniqueDel {
                        entryIsDir.removeValue(forKey: target)
                    }
                }

                for item in prefixed {
                    let clean = ArchiveEntry.normalizePath(item.archivePath, isDirectory: false)
                    if let collidingAncestor = ancestorFileCollision(for: clean, in: entryIsDir) {
                        throw BoltZipError.entryAlreadyExists(collidingAncestor)
                    }
                }

                try addItems(
                    prefixed,
                    to: stagedArchive,
                    options: options,
                    password: activePassword,
                    encryptFileNames: encryptFileNames,
                    archiveDisplayURL: archiveURL,
                    stage: stage,
                    step: opIdx,
                    entryIsDir: &entryIsDir
                )

            case .setComment:
                break
            }
        }

        let testResult = try SevenZipCommand.run(
            ["t", "-t7z", "-bd", "-bb0", "--", stagedArchive.path],
            password: activePassword
        )
        try SevenZipArchiveListing.check(testResult, archive: archiveURL, password: activePassword, format: .sevenZip)
        try ArchiveOutputTransaction.publish([stagedArchive], to: [archiveURL])
        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: archiveURL.lastPathComponent))
    }

    private static func ancestorFileCollision(for normalizedPath: String, in entryIsDir: [String: Bool]) -> String? {
        var cursor = normalizedPath[...]
        while let slash = cursor.lastIndex(of: "/") {
            cursor = cursor[..<slash]
            let parent = String(cursor)
            if entryIsDir[parent] == false {
                return parent
            }
        }
        return nil
    }

    private static func collectMatchingPaths(targets: Set<String>, in entryIsDir: [String: Bool]) -> [String] {
        var matched: Set<String> = []
        for raw in targets {
            let clean = ArchiveEntry.normalizePath(raw, isDirectory: false)
            guard !clean.isEmpty else { continue }
            for key in entryIsDir.keys {
                if key == clean || key.hasPrefix(clean + "/") {
                    matched.insert(key)
                }
            }
        }
        return matched.sorted()
    }

    private static func deleteEntries(
        _ paths: [String],
        from archive: URL,
        password: String?,
        archiveDisplayURL: URL,
        stage: URL,
        step: Int
    ) throws {
        guard !paths.isEmpty else { return }
        let listURL = stage.appendingPathComponent("del-\(step)-\(UUID().uuidString.prefix(6)).txt")
        let body = paths.joined(separator: "\n") + "\n"
        try Data(body.utf8).write(to: listURL)
        defer { try? FileManager.default.removeItem(at: listURL) }

        let result = try SevenZipCommand.run(
            ["d", "-t7z", "-spd", "-ssc", "-scsUTF-8", "-sccUTF-8", "-bso0", "-bse2", "-bsp0", "-i@\(listURL.path)", "--", archive.path],
            password: password
        )
        try SevenZipArchiveListing.check(result, archive: archiveDisplayURL, password: password, format: .sevenZip)
    }

    private static func addItems(
        _ items: [ArchiveInputItem],
        to archive: URL,
        options: CreateArchiveOptions,
        password: String?,
        encryptFileNames: Bool,
        archiveDisplayURL: URL,
        stage: URL,
        step: Int,
        entryIsDir: inout [String: Bool]
    ) throws {
        guard !items.isEmpty else { return }
        let fm = FileManager.default
        let inputStage = stage.appendingPathComponent("add-\(step)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try fm.createDirectory(at: inputStage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var directories: [(URL, ArchiveInputItem)] = []
        defer {
            for (dir, _) in directories {
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            }
            try? fm.removeItem(at: inputStage)
        }

        var files: [(url: URL, item: ArchiveInputItem, followsSymbolicLink: Bool)] = []
        var symbolicLinks: [ArchiveInputItem] = []
        var followStagedLinks = false

        for item in items {
            let target = try SevenZipArchiveWriter.stagedItemURL(item, in: inputStage)
            let parentDir = target.deletingLastPathComponent()
            if parentDir.path != inputStage.path {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            if item.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                directories.append((target, item))
            } else if item.isSymbolicLink {
                symbolicLinks.append(item)
            } else {
                guard let source = item.fileURL else { throw ArchiveOperationError.inputChanged(item.archivePath) }
                try SevenZipArchiveWriter.validateSize(of: source, for: item, followsSymbolicLink: false)
                do {
                    try fm.linkItem(at: source, to: target)
                    files.append((target, item, false))
                } catch {
                    try fm.createSymbolicLink(at: target, withDestinationURL: source.standardizedFileURL)
                    files.append((target, item, true))
                    followStagedLinks = true
                }
            }
        }

        if !followStagedLinks {
            for item in symbolicLinks {
                try SevenZipArchiveWriter.stageSymbolicLink(item, in: inputStage, createParent: true)
            }
        }
        for (dir, item) in directories.reversed() {
            try fm.setAttributes(
                [.posixPermissions: NSNumber(value: item.permissions), .modificationDate: item.modifiedDate],
                ofItemAtPath: dir.path
            )
        }
        for (file, item, followsLink) in files {
            try SevenZipArchiveWriter.validateSize(of: file, for: item, followsSymbolicLink: followsLink)
        }

        let effectiveAlgo = ArchiveFormat.sevenZip.supportedAlgorithms.contains(options.algorithm) ? options.algorithm : .xz
        let codec: String
        switch effectiveAlgo {
        case .xz: codec = "LZMA2"
        case .bzip2: codec = "BZip2"
        case .deflate: codec = "Deflate"
        case .store: codec = "Copy"
        default: codec = "LZMA2"
        }
        let minLvl = effectiveAlgo == .xz ? 0 : 1
        let level = effectiveAlgo == .store ? 0 : min(9, max(minLvl, options.level))
        let workers = BoltConcurrency.resolvedWorkerCount(override: options.workerCount)

        var cmd = ["a", "-t7z", "-m0=\(codec)", "-mx=\(level)", "-mmt=\(workers)", "-spd", "-ssc", "-scsUTF-8", "-sccUTF-8", "-bso0", "-bse2", "-bsp0"]
        if password != nil {
            cmd += ["-p", encryptFileNames ? "-mhe=on" : "-mhe=off"]
        }

        let needsTwoPassSymlinks = followStagedLinks && !symbolicLinks.isEmpty
        let result = try SevenZipCommand.run(
            cmd + [followStagedLinks ? "-snl-" : "-snl", "--", archive.path],
            password: password,
            passwordPromptCount: password != nil ? 2 : 1,
            directory: inputStage
        )
        try SevenZipArchiveListing.check(result, archive: archiveDisplayURL, password: password, format: .sevenZip)

        if needsTwoPassSymlinks {
            let linkStage = stage.appendingPathComponent("addlinks-\(step)-\(UUID().uuidString.prefix(6))", isDirectory: true)
            try fm.createDirectory(at: linkStage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: linkStage) }
            var names: [String] = []
            for item in symbolicLinks {
                try SevenZipArchiveWriter.stageSymbolicLink(item, in: linkStage, createParent: true)
                names.append("\"" + item.archivePath + "\"")
            }
            let listFile = stage.appendingPathComponent("addlinks-\(step).txt")
            try Data((names.joined(separator: "\n") + "\n").utf8).write(to: listFile)
            defer { try? fm.removeItem(at: listFile) }

            let symResult = try SevenZipCommand.run(
                cmd + ["-snl", "-spf", "--", archive.path, "@\(listFile.path)"],
                password: password,
                passwordPromptCount: password != nil ? 2 : 1,
                directory: linkStage
            )
            try SevenZipArchiveListing.check(symResult, archive: archiveDisplayURL, password: password, format: .sevenZip)
        }

        for item in items {
            let clean = ArchiveEntry.normalizePath(item.archivePath, isDirectory: false)
            if !clean.isEmpty {
                entryIsDir[clean] = item.isDirectory
            }
        }
    }
}
