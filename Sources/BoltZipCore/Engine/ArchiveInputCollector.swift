import Darwin
import Foundation

public struct ArchiveExcludeMatcher: Sendable {
    private let patterns: [String]

    public init(patterns: [String]) {
        self.patterns = Self.normalize(patterns)
    }

    public var isEmpty: Bool { patterns.isEmpty }

    public static func parse(_ rawText: String) -> [String] {
        rawText
            .components(separatedBy: CharacterSet(charactersIn: ",;\r\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func normalize(_ rawPatterns: [String]) -> [String] {
        rawPatterns.compactMap { raw in
            var p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while p.hasPrefix("./") { p.removeFirst(2) }
            while p.hasPrefix("/") { p.removeFirst() }
            while p.hasSuffix("/") { p.removeLast() }
            return p.isEmpty ? nil : p
        }
    }

    public func matches(archivePath: String, relativeWithinRoot: String? = nil, itemName: String) -> Bool {
        guard !patterns.isEmpty else { return false }
        let cleanArchive = Self.stripSlashes(archivePath)
        let cleanRel = relativeWithinRoot.map(Self.stripSlashes)
        for pattern in patterns {
            if pattern.contains("/") {
                if Self.globMatches(pattern: pattern, candidate: cleanArchive, pathname: true) {
                    return true
                }
                if let cleanRel, !cleanRel.isEmpty,
                   Self.globMatches(pattern: pattern, candidate: cleanRel, pathname: true) {
                    return true
                }
            } else {
                if Self.globMatches(pattern: pattern, candidate: itemName, pathname: false) {
                    return true
                }
            }
        }
        return false
    }

    private static func stripSlashes(_ path: String) -> String {
        var out = path
        while out.hasPrefix("/") { out.removeFirst() }
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }

    private static func globMatches(pattern: String, candidate: String, pathname: Bool) -> Bool {
        let flags = FNM_CASEFOLD | (pathname ? FNM_PATHNAME : 0)
        return pattern.withCString { patPtr in
            candidate.withCString { candPtr in
                fnmatch(patPtr, candPtr, flags) == 0
            }
        }
    }
}

struct ArchiveInputItem: Sendable {
    let archivePath: String
    let fileURL: URL? // nil if synthetic directory or symlink
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let symlinkTarget: String?
    let modifiedDate: Date
    let permissions: UInt16
    let fileSize: UInt64
}

enum ArchiveInputCollector {
    static func collect(
        from inputURLs: [URL],
        excludeMacJunk: Bool,
        preserveSymlinks: Bool = true,
        excludePatterns: [String] = [],
        excluding excludedURLs: [URL] = [],
        controller: ArchiveTaskController? = nil
    ) throws -> [ArchiveInputItem] {
        let fm = FileManager.default
        let matcher = ArchiveExcludeMatcher(patterns: excludePatterns)
        var items: [ArchiveInputItem] = []
        let excluded = Set(excludedURLs.map { $0.standardizedFileURL.path })
        var seenInputs: Set<String> = []
        var rootNames: Set<String> = []

        for rootURL in inputURLs {
            try controller?.checkpoint()
            guard seenInputs.insert(rootURL.standardizedFileURL.path).inserted else { continue }
            guard !excluded.contains(rootURL.standardizedFileURL.path) else {
                throw ArchiveOperationError.outputIsInput
            }
            let rootAttrs: [FileAttributeKey: Any]
            do {
                rootAttrs = try fm.attributesOfItem(atPath: rootURL.path)
            } catch {
                throw BoltZipError.ioError(BoltCoreLocalization.t(
                    "找不到文件或文件夹：\(rootURL.path)",
                    "找不到檔案或資料夾：\(rootURL.path)",
                    "File or folder not found: \(rootURL.path)",
                    "ファイルまたはフォルダが見つかりません: \(rootURL.path)"
                ))
            }

            let originalName = rootURL.lastPathComponent
            var rootName = originalName
            var suffix = 1
            while !rootNames.insert(rootName.precomposedStringWithCanonicalMapping.lowercased()).inserted {
                let isDirectory = rootAttrs[.type] as? FileAttributeType == .typeDirectory
                let nameURL = URL(fileURLWithPath: originalName)
                let ext = isDirectory ? "" : nameURL.pathExtension
                let stem = ext.isEmpty ? originalName : nameURL.deletingPathExtension().lastPathComponent
                rootName = ext.isEmpty ? "\(stem) (\(suffix))" : "\(stem) (\(suffix)).\(ext)"
                suffix += 1
            }
            if excludeMacJunk && MacJunkFilter.isJunk(path: originalName) {
                continue
            }
            if matcher.matches(archivePath: originalName, relativeWithinRoot: originalName, itemName: originalName) {
                continue
            }

            let fileType = rootAttrs[.type] as? FileAttributeType
            let rootMod = (rootAttrs[.modificationDate] as? Date) ?? Date()

            if fileType == .typeSymbolicLink {
                guard preserveSymlinks else { continue }
                let target = try fm.destinationOfSymbolicLink(atPath: rootURL.path)
                let rootPerms = UInt16((rootAttrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777)
                items.append(ArchiveInputItem(
                    archivePath: rootName,
                    fileURL: nil,
                    isDirectory: false,
                    isSymbolicLink: true,
                    symlinkTarget: target,
                    modifiedDate: rootMod,
                    permissions: rootPerms,
                    fileSize: UInt64(target.utf8.count)
                ))
                continue
            }

            let isRootDir = (fileType == .typeDirectory)
            let rootPerms = UInt16((rootAttrs[.posixPermissions] as? NSNumber)?.uint16Value ?? (isRootDir ? 0o755 : 0o644))

            if !isRootDir {
                let sz = (rootAttrs[.size] as? NSNumber)?.uint64Value ?? 0
                items.append(ArchiveInputItem(
                    archivePath: rootName,
                    fileURL: rootURL,
                    isDirectory: false,
                    isSymbolicLink: false,
                    symlinkTarget: nil,
                    modifiedDate: rootMod,
                    permissions: rootPerms,
                    fileSize: sz
                ))
                continue
            }

            // Directory entry itself
            items.append(ArchiveInputItem(
                archivePath: rootName + "/",
                fileURL: nil,
                isDirectory: true,
                isSymbolicLink: false,
                symlinkTarget: nil,
                modifiedDate: rootMod,
                permissions: rootPerms,
                fileSize: 0
            ))

            let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
            guard let enumerator = fm.enumerator(
                at: canonicalRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            let basePrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : (canonicalRoot.path + "/")
            for case let childURL as URL in enumerator {
                try controller?.checkpoint()
                if excluded.contains(childURL.standardizedFileURL.path) {
                    if (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { enumerator.skipDescendants() }
                    continue
                }
                let childParent = childURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
                let childParentPrefix = childParent.hasSuffix("/") ? childParent : (childParent + "/")
                let canonicalChildPath = childParentPrefix + childURL.lastPathComponent
                let rel: String
                if canonicalChildPath.hasPrefix(basePrefix) {
                    rel = String(canonicalChildPath.dropFirst(basePrefix.count))
                } else {
                    let fallbackPath = childURL.standardizedFileURL.path
                    rel = fallbackPath.hasPrefix(basePrefix)
                        ? String(fallbackPath.dropFirst(basePrefix.count))
                        : childURL.lastPathComponent
                }
                let archiveRel = "\(rootName)/\(rel)"

                if excludeMacJunk && MacJunkFilter.isJunk(path: archiveRel) {
                    if (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if matcher.matches(archivePath: archiveRel, relativeWithinRoot: rel, itemName: childURL.lastPathComponent) {
                    if (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                let rv = try childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                let attrs = try? fm.attributesOfItem(atPath: childURL.path)
                let mod = rv.contentModificationDate ?? Date()

                if rv.isSymbolicLink == true {
                    guard preserveSymlinks else { continue }
                    let target = try fm.destinationOfSymbolicLink(atPath: childURL.path)
                    let perms = UInt16((attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777)
                    items.append(ArchiveInputItem(
                        archivePath: archiveRel,
                        fileURL: nil,
                        isDirectory: false,
                        isSymbolicLink: true,
                        symlinkTarget: target,
                        modifiedDate: mod,
                        permissions: perms,
                        fileSize: UInt64(target.utf8.count)
                    ))
                    continue
                }

                let isSubDir = rv.isDirectory == true
                let perms = UInt16((attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? (isSubDir ? 0o755 : 0o644))
                let sz = isSubDir ? 0 : UInt64(rv.fileSize ?? 0)

                items.append(ArchiveInputItem(
                    archivePath: isSubDir ? (archiveRel + "/") : archiveRel,
                    fileURL: isSubDir ? nil : childURL,
                    isDirectory: isSubDir,
                    isSymbolicLink: false,
                    symlinkTarget: nil,
                    modifiedDate: mod,
                    permissions: perms,
                    fileSize: sz
                ))
            }
        }
        return items
    }
}
