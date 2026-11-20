import Darwin
import Foundation

enum ArchiveExtractionDestination {
    static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func protectSources(_ sources: [URL], from target: URL) throws {
        try protectSourcePaths(Set(sources.map(pathKey)), from: target)
    }

    static func protectSourcePaths(_ paths: Set<String>, from target: URL) throws {
        if !paths.isEmpty && paths.contains(pathKey(target)) {
            throw ArchiveOperationError.extractionWouldReplaceSource(target.lastPathComponent)
        }
    }

    static func pathMatchesSelection(_ entryPath: String, selectedPaths: Set<String>) -> Bool {
        let cleanEntry = entryPath.hasSuffix("/") ? String(entryPath.dropLast()) : entryPath
        return selectedPaths.contains { sel in
            let cleanSel = sel.hasSuffix("/") ? String(sel.dropLast()) : sel
            return cleanEntry == cleanSel || cleanEntry.hasPrefix(cleanSel + "/")
        }
    }

    static func safeDestinationURL(for entryPath: String, under rootURL: URL) throws -> URL {
        let components = entryPath.split(separator: "/").map(String.init)
        if components.contains("..") || entryPath.hasPrefix("/") {
            throw BoltZipError.pathTraversalDetected(entryPath)
        }
        let resolvedRoot = rootURL.standardizedFileURL
        let candidate = resolvedRoot.appendingPathComponent(entryPath).standardizedFileURL
        guard contains(candidate, under: resolvedRoot) else {
            throw BoltZipError.pathTraversalDetected(entryPath)
        }
        return candidate
    }

    static func assertNoSymlinkTraversal(at url: URL, under rootURL: URL) throws {
        let fm = FileManager.default
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL

        var probe = url.deletingLastPathComponent()
        while (try? fm.attributesOfItem(atPath: probe.path)) == nil && probe.path != "/" && probe.path != resolvedRoot.path {
            probe = probe.deletingLastPathComponent()
        }
        let resolvedAncestor = probe.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedAncestor, under: resolvedRoot) else {
            throw BoltZipError.pathTraversalDetected(url.lastPathComponent)
        }
    }

    static func prepareExtractTargetURL(
        initialURL: URL,
        under rootURL: URL,
        policy: OverwritePolicy
    ) throws -> URL? {
        try assertNoSymlinkTraversal(at: initialURL, under: rootURL)
        let fm = FileManager.default
        try fm.createDirectory(at: initialURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var targetURL = initialURL
        if let attrs = try? fm.attributesOfItem(atPath: targetURL.path) {
            let isExistingDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
            switch policy {
            case .skip:
                return nil
            case .overwrite:
                if isExistingDirectory {
                    // Never recursively delete an existing directory to overwrite it with a file
                    targetURL = uniqueNonCollidingURL(for: initialURL)
                }
            case .rename:
                targetURL = uniqueNonCollidingURL(for: initialURL)
            }
        }
        return targetURL
    }

    static func makeExtractionStage(near target: URL, under root: URL) throws -> URL {
        try assertNoSymlinkTraversal(at: target, under: root)
        let folder = target.deletingLastPathComponent()
            .appendingPathComponent(".boltzip-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return folder
    }

    static func commitExtractedItem(
        _ staged: URL,
        to target: URL,
        under root: URL,
        policy: OverwritePolicy,
        protectedSourcePaths: Set<String> = [],
        controller: ArchiveTaskController? = nil
    ) throws {
        try controller?.checkpoint()
        try assertNoSymlinkTraversal(at: target, under: root)
        if policy == .overwrite { try protectSourcePaths(protectedSourcePaths, from: target) }
        let result = staged.withUnsafeFileSystemRepresentation { source in
            target.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return EINVAL }
                if policy == .overwrite {
                    return Darwin.rename(source, destination) == 0 ? 0 : errno
                }
                return renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
        if result != 0 {
            if policy == .skip && result == EEXIST { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    static func createSafeSymlink(
        at initialURL: URL,
        target: String,
        under rootURL: URL,
        overwritePolicy: OverwritePolicy,
        protectedSourcePaths: Set<String> = []
    ) throws {
        let cleanTarget = target.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !cleanTarget.isEmpty, !cleanTarget.hasPrefix("/") else {
            throw BoltZipError.pathTraversalDetected("\(initialURL.lastPathComponent) -> \(target)")
        }
        try assertNoSymlinkTraversal(at: initialURL, under: rootURL)

        let fm = FileManager.default
        let parentDir = initialURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedParent = parentDir.resolvingSymlinksInPath().standardizedFileURL
        let resolvedTarget = URL(fileURLWithPath: cleanTarget, relativeTo: resolvedParent).standardizedFileURL
        guard contains(resolvedTarget, under: resolvedRoot) else {
            throw BoltZipError.pathTraversalDetected("\(initialURL.lastPathComponent) -> \(cleanTarget)")
        }

        guard let finalURL = try prepareExtractTargetURL(initialURL: initialURL, under: rootURL, policy: overwritePolicy) else { return }
        let stage = try makeExtractionStage(near: finalURL, under: rootURL)
        defer { try? fm.removeItem(at: stage) }
        let stagedLink = stage.appendingPathComponent("link")
        try fm.createSymbolicLink(atPath: stagedLink.path, withDestinationPath: cleanTarget)
        try commitExtractedItem(stagedLink, to: finalURL, under: rootURL, policy: overwritePolicy,
                                protectedSourcePaths: protectedSourcePaths)
    }

    static func writeExtractedFile(
        _ data: Data,
        to initialURL: URL,
        under root: URL,
        entry: ArchiveEntry,
        policy: OverwritePolicy,
        protectedSourcePaths: Set<String> = [],
        controller: ArchiveTaskController?
    ) throws {
        guard let target = try prepareExtractTargetURL(initialURL: initialURL, under: root, policy: policy) else { return }
        let fm = FileManager.default
        let stage = try makeExtractionStage(near: target, under: root)
        defer { try? fm.removeItem(at: stage) }
        let stagedFile = stage.appendingPathComponent("payload")
        try data.write(to: stagedFile)
        try? fm.setAttributes([
            .modificationDate: entry.modifiedDate,
            .posixPermissions: NSNumber(value: entry.permissions)
        ], ofItemAtPath: stagedFile.path)
        try commitExtractedItem(stagedFile, to: target, under: root, policy: policy,
                                protectedSourcePaths: protectedSourcePaths, controller: controller)
    }

    static func remapTopLevelFolder(in entryPath: String, renameMap: [String: String]) -> String {
        guard !renameMap.isEmpty else { return entryPath }
        let parts = entryPath.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first, let replacement = renameMap[String(first)] else {
            return entryPath
        }
        let suffixStart = entryPath.index(entryPath.startIndex, offsetBy: first.count)
        return replacement + entryPath[suffixStart...]
    }

    static func uniqueNonCollidingURL(for url: URL, isDirectoryHint: Bool = false) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let ext = isDirectoryHint ? "" : url.pathExtension
        let stem = isDirectoryHint ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }

    private static func contains(_ candidate: URL, under root: URL) -> Bool {
        let path = root.path
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return candidate.path == path || candidate.path.hasPrefix(prefix)
    }
}

extension BoltArchiveEngine {
    /// Publish a promised file or directory after staging it on the destination volume.
    public static func publishPromisedItem(from source: URL, to destination: URL, protectedSources: [URL]) throws {
        try ArchiveExtractionDestination.protectSources(protectedSources, from: destination)
        let fm = FileManager.default
        let sourceKind = try fm.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
        func existingKind() throws -> FileAttributeType? {
            let kind = (try? fm.attributesOfItem(atPath: destination.path))?[.type] as? FileAttributeType
            if let kind, (kind == .typeDirectory) != (sourceKind == .typeDirectory) {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
            }
            return kind
        }
        _ = try existingKind()
        let root = destination.deletingLastPathComponent()
        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: destination, under: root)
        defer { try? fm.removeItem(at: stage) }
        let local = stage.appendingPathComponent("payload")
        try fm.moveItem(at: source, to: local)

        // A failed cross-volume copy leaves the destination untouched. Swapping two existing
        // items is atomic and also preserves a nonempty directory until replacement succeeds.
        let oldKind = try existingKind()
        try ArchiveExtractionDestination.protectSources(protectedSources, from: destination)
        let status = local.withUnsafeFileSystemRepresentation { stagedPath in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let stagedPath, let target else { return EINVAL }
                if let oldKind, oldKind != .typeDirectory {
                    return Darwin.rename(stagedPath, target) == 0 ? 0 : errno
                }
                let flags = oldKind == nil ? RENAME_EXCL : RENAME_SWAP
                return renamex_np(stagedPath, target, UInt32(flags)) == 0 ? 0 : errno
            }
        }
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(status), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    /// Publishes a regular file extracted by a caller, using the same collision and atomic replacement rules.
    @discardableResult
    public static func publishExtractedFile(from source: URL, to destination: URL,
                                            under root: URL, policy: OverwritePolicy,
                                            protectedSources: [URL] = []) throws -> URL? {
        guard let target = try ArchiveExtractionDestination.prepareExtractTargetURL(initialURL: destination, under: root, policy: policy) else { return nil }
        if policy == .overwrite { try ArchiveExtractionDestination.protectSources(protectedSources, from: target) }
        let stage = try ArchiveExtractionDestination.makeExtractionStage(near: target, under: root)
        defer { try? FileManager.default.removeItem(at: stage) }
        let staged = stage.appendingPathComponent("payload")
        try FileManager.default.moveItem(at: source, to: staged)
        try ArchiveExtractionDestination.commitExtractedItem(
            staged, to: target, under: root, policy: policy,
            protectedSourcePaths: Set(protectedSources.map(ArchiveExtractionDestination.pathKey))
        )
        return target
    }
}
