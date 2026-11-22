import Foundation

extension BoltArchiveEngine {
    public static func detectExtractConflicts(
        archiveURL: URL,
        options: ExtractOptions
    ) throws -> ExtractConflictSummary {
        let listing = try inspect(archiveURL: archiveURL, encoding: options.encoding, password: options.password)
        let targetRoot = resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        let outputLocations: [URL]
        if targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL {
            outputLocations = [targetRoot]
        } else {
            let paths: [String]
            if case .selected(let chosen) = options.mode, !chosen.isEmpty {
                paths = chosen.sorted()
            } else {
                paths = ArchiveExtractionPlan.filteredEntries(listing.entries, options: options).compactMap {
                    $0.path.split(separator: "/").first.map(String.init)
                }
            }
            var seen: Set<String> = []
            outputLocations = paths.compactMap { path in
                guard let url = try? ArchiveExtractionDestination.safeDestinationURL(for: path, under: targetRoot),
                      url.path != targetRoot.path,
                      seen.insert(ArchiveExtractionDestination.pathKey(url)).inserted else { return nil }
                return url
            }
        }
        return ExtractConflictSummary(destinationRoot: options.destinationURL,
                                      conflictingNames: outputLocations.filter { fm.fileExists(atPath: $0.path) }.map(\.lastPathComponent),
                                      outputLocations: outputLocations)
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
        let target = SevenZipVolumeDiscovery.stripSplitSuffix(from: url)
        let name = target.lastPathComponent
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.zst", ".tar.xz", ".tar.bz2", ".tar.lz4"] where lower.hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return target.deletingPathExtension().lastPathComponent
    }
}

struct ArchiveExtractionPlan {
    let targetRoot: URL
    let entries: [ArchiveEntry]
    let topLevelDirRenameMap: [String: String]
    let totalBytes: UInt64
    let protectedSourcePaths: Set<String>

    static func prepare(
        listing: ArchiveListing,
        options: ExtractOptions,
        sourceURLs: [URL]
    ) throws -> ArchiveExtractionPlan {
        var targetRoot = BoltArchiveEngine.resolveExtractDestination(listing: listing, options: options)
        let fm = FileManager.default

        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL != options.destinationURL.standardizedFileURL,
           fm.fileExists(atPath: targetRoot.path) {
            targetRoot = ArchiveExtractionDestination.uniqueNonCollidingURL(for: targetRoot, isDirectoryHint: true)
        }
        let entriesToExtract = filteredEntries(listing.entries, options: options)
        let protected = Set((sourceURLs + options.protectedArchiveURLs).map(ArchiveExtractionDestination.pathKey))
        if options.overwritePolicy == .overwrite {
            for entry in entriesToExtract where !entry.isDirectory && (!entry.isSymbolicLink || options.restoreSymlinks) {
                let target = try ArchiveExtractionDestination.safeDestinationURL(for: entry.path, under: targetRoot)
                try ArchiveExtractionDestination.protectSourcePaths(protected, from: target)
            }
        }
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        var topLevelDirRenameMap: [String: String] = [:]
        if options.overwritePolicy == .rename,
           targetRoot.standardizedFileURL == options.destinationURL.standardizedFileURL {
            var topLevelNames: Set<String> = []
            var directoryNames: Set<String> = []
            var directories: [String] = []
            for entry in entriesToExtract {
                let parts = entry.path.split(separator: "/")
                guard let component = parts.first else { continue }
                let name = String(component)
                topLevelNames.insert(name)
                if (entry.isDirectory || parts.count > 1) && directoryNames.insert(name).inserted {
                    directories.append(name)
                }
            }
            // Reserve original archive names before allocating any numbered directory names.
            var reserved = Set(topLevelNames.map { ArchiveExtractionDestination.pathKey(targetRoot.appendingPathComponent($0)) })
            var assigned: Set<String> = []
            for name in directories {
                let original = targetRoot.appendingPathComponent(name)
                let key = ArchiveExtractionDestination.pathKey(original)
                if (try? fm.attributesOfItem(atPath: original.path)) != nil || assigned.contains(key) {
                    let renamed = ArchiveExtractionDestination.uniqueNonCollidingURL(for: original, isDirectoryHint: true, reservedPaths: reserved)
                    topLevelDirRenameMap[name] = renamed.lastPathComponent
                    let newKey = ArchiveExtractionDestination.pathKey(renamed)
                    reserved.insert(newKey)
                    assigned.insert(newKey)
                } else {
                    assigned.insert(key)
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
            totalBytes: totalBytes,
            protectedSourcePaths: protected
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
                return chosen.isEmpty || ArchiveExtractionDestination.pathMatchesSelection(entry.path, selectedPaths: chosen)
            }
        }
    }
}
