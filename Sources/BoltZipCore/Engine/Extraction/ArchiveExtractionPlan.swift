import Foundation

extension BoltArchiveEngine {
    public static func detectExtractConflicts(
        archiveURL: URL,
        options: ExtractOptions
    ) throws -> ExtractConflictSummary {
        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        let targetRoot = resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL {
            if fm.fileExists(atPath: targetRoot.path) {
                return ExtractConflictSummary(
                    destinationRoot: options.destinationURL,
                    conflictingNames: [targetRoot.lastPathComponent]
                )
            }
            return ExtractConflictSummary(destinationRoot: options.destinationURL, conflictingNames: [])
        }

        let entriesToExtract = ArchiveExtractionPlan.filteredEntries(listing.entries, options: options)
        var seen: Set<String> = []
        var conflicts: [String] = []

        switch options.mode {
        case .selected(let chosen):
            var targetRootsToCheck: [String] = []
            for raw in chosen {
                let clean = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
                targetRootsToCheck.append(clean)
            }
            if targetRootsToCheck.isEmpty {
                for entry in entriesToExtract {
                    let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                    guard let top = clean.split(separator: "/").first.map(String.init),
                          seen.insert(top).inserted else { continue }
                    targetRootsToCheck.append(top)
                }
            }
            for rel in targetRootsToCheck {
                if let url = try? ArchiveExtractionDestination.safeDestinationURL(for: rel, under: targetRoot),
                   fm.fileExists(atPath: url.path) {
                    conflicts.append(url.lastPathComponent)
                }
            }
        case .smart, .here, .subfolder:
            for entry in entriesToExtract {
                let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                guard let top = clean.split(separator: "/").first.map(String.init),
                      seen.insert(top).inserted else { continue }
                if let url = try? ArchiveExtractionDestination.safeDestinationURL(for: top, under: targetRoot),
                   fm.fileExists(atPath: url.path) {
                    conflicts.append(top)
                }
            }
        }

        return ExtractConflictSummary(destinationRoot: targetRoot, conflictingNames: conflicts)
    }

    /// Bandizip/Windows-Zip style smart destination folder detection
    public static func resolveExtractDestination(listing: ArchiveListing, options: ExtractOptions) -> URL {
        switch options.mode {
        case .here, .selected:
            return options.destinationURL
        case .subfolder:
            return options.destinationURL.appendingPathComponent(archiveBaseStem(listing.archiveURL), isDirectory: true)
        case .smart:
            let cleanEntries = listing.entries.filter { !MacJunkFilter.isJunk(path: $0.path) }
            let roots = Set(cleanEntries.compactMap { entry -> String? in
                let parts = entry.path.split(separator: "/")
                return parts.first.map(String.init)
            })
            if roots.count <= 1 {
                return options.destinationURL
            }
            return options.destinationURL.appendingPathComponent(archiveBaseStem(listing.archiveURL), isDirectory: true)
        }
    }

    public static func archiveBaseStem(_ url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.zst", ".tar.xz", ".tar.bz2", ".tar.lz4"] where lower.hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

struct ArchiveExtractionPlan {
    let targetRoot: URL
    let entries: [ArchiveEntry]
    let topLevelDirRenameMap: [String: String]
    let totalBytes: UInt64

    static func prepare(
        listing: ArchiveListing,
        options: ExtractOptions
    ) throws -> ArchiveExtractionPlan {
        var targetRoot = BoltArchiveEngine.resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL,
           fm.fileExists(atPath: targetRoot.path) {
            targetRoot = ArchiveExtractionDestination.uniqueNonCollidingURL(for: targetRoot, isDirectoryHint: true)
        }
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        let entriesToExtract = filteredEntries(listing.entries, options: options)

        var topLevelDirRenameMap: [String: String] = [:]
        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL == options.destinationURL.standardizedFileURL {
            var checkedTops: Set<String> = []
            for entry in entriesToExtract {
                let parts = entry.path.split(separator: "/").map(String.init)
                guard let top = parts.first else { continue }
                let isFolderTop = parts.count > 1 || entry.isDirectory
                guard isFolderTop, checkedTops.insert(top).inserted else { continue }
                let existing = targetRoot.appendingPathComponent(top)
                var isDirObjC: ObjCBool = false
                if fm.fileExists(atPath: existing.path, isDirectory: &isDirObjC) {
                    let renamed = ArchiveExtractionDestination.uniqueNonCollidingURL(for: existing, isDirectoryHint: true)
                    topLevelDirRenameMap[top] = renamed.lastPathComponent
                }
            }
        }

        let totalBytes = try entriesToExtract.reduce(UInt64(0)) {
            try ArchiveByteCount.checkedSum($0, $1.isDirectory ? 0 : $1.uncompressedSize)
        }
        return ArchiveExtractionPlan(
            targetRoot: targetRoot,
            entries: entriesToExtract,
            topLevelDirRenameMap: topLevelDirRenameMap,
            totalBytes: totalBytes
        )
    }

    fileprivate static func filteredEntries(_ entries: [ArchiveEntry], options: ExtractOptions) -> [ArchiveEntry] {
        entries.filter { entry in
            if options.stripMacJunk && MacJunkFilter.isJunk(path: entry.path) {
                return false
            }
            switch options.mode {
            case .smart, .here, .subfolder:
                return true
            case .selected(let chosen):
                return ArchiveExtractionDestination.pathMatchesSelection(entry.path, selectedPaths: chosen)
            }
        }
    }
}
