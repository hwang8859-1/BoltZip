import BoltZipCore
import Foundation

extension WorkspaceViewModel {
    var breadcrumbComponents: [(title: String, path: String)] {
        var crumbs: [(String, String)] = [(l10n.rootLabel, "")]
        let parts = currentFolder.split(separator: "/").map(String.init)
        var acc = ""
        for p in parts {
            acc += p + "/"
            crumbs.append((p, acc))
        }
        return crumbs
    }

    var canNavigateUp: Bool { !currentFolder.isEmpty }
    var canNavigateDown: Bool { !folderForwardStack.isEmpty }
    var isSearchingActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func returnToArchiveRoot() {
        searchText = ""
        navigateToFolder("")
    }

    func toggleSortColumn(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    func jumpToEntryLocation(_ entry: ArchiveEntry) {
        let trimmed = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        let parentFolder: String
        if let idx = trimmed.lastIndex(of: "/") {
            parentFolder = String(trimmed[..<idx]) + "/"
        } else {
            parentFolder = ""
        }
        searchText = ""
        navigateToFolder(parentFolder)
        selectedEntryIDs = [entry.id]
    }

    func navigateToFolder(_ path: String) {
        guard path != currentFolder else {
            selectedEntryIDs.removeAll()
            return
        }
        let isAncestor = path.isEmpty ? !currentFolder.isEmpty : (currentFolder.hasPrefix(path) && currentFolder != path)
        if isAncestor {
            if folderForwardStack.last != currentFolder {
                folderForwardStack.append(currentFolder)
            }
        } else if folderForwardStack.last == path {
            _ = folderForwardStack.popLast()
        } else {
            folderForwardStack.removeAll()
        }
        currentFolder = path
        selectedEntryIDs.removeAll()
    }

    func navigateUp() {
        guard canNavigateUp else { return }
        let trimmed = currentFolder.hasSuffix("/") ? String(currentFolder.dropLast()) : currentFolder
        let parent: String
        if let idx = trimmed.lastIndex(of: "/") {
            parent = String(trimmed[..<idx]) + "/"
        } else {
            parent = ""
        }
        if folderForwardStack.last != currentFolder {
            folderForwardStack.append(currentFolder)
        }
        currentFolder = parent
        selectedEntryIDs.removeAll()
    }

    func navigateDown() {
        guard let next = folderForwardStack.popLast() else { return }
        currentFolder = next
        selectedEntryIDs.removeAll()
    }

    var folderTree: FolderTreeNode {
        guard let entries = listing?.entries else {
            return FolderTreeNode(id: "", name: l10n.rootLabel, path: "", children: [], fileCount: 0)
        }

        var allFolders: Set<String> = [""]
        var directFileCount: [String: Int] = [:]

        for entry in entries {
            let clean = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = clean.split(separator: "/").map(String.init)
            if entry.isDirectory {
                var acc = ""
                for p in parts {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
            } else {
                var acc = ""
                for p in parts.dropLast() {
                    acc += p + "/"
                    allFolders.insert(acc)
                }
                directFileCount[acc, default: 0] += 1
            }
        }

        func buildNode(path: String, name: String) -> FolderTreeNode {
            let directChildren = allFolders
                .filter { candidate in
                    guard candidate != path, candidate.hasPrefix(path) else { return false }
                    let rem = String(candidate.dropFirst(path.count))
                    return rem.split(separator: "/").count == 1
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { childPath -> FolderTreeNode in
                    let trimmed = childPath.hasSuffix("/") ? String(childPath.dropLast()) : childPath
                    let childName = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
                    return buildNode(path: childPath, name: childName)
                }
            return FolderTreeNode(
                id: path,
                name: name,
                path: path,
                children: directChildren,
                fileCount: directFileCount[path, default: 0]
            )
        }

        return buildNode(path: "", name: listing?.archiveURL.lastPathComponent ?? l10n.rootLabel)
    }

    var visibleEntries: [ArchiveEntry] {
        guard let entries = listing?.entries else { return [] }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = currentFolder
        var items: [ArchiveEntry] = query.isEmpty
            ? directChildren(of: entries, prefix: prefix)
            : searchScopedEntries(of: entries, prefix: prefix, query: query)

        sortEntries(&items)
        return items
    }

    var selectedEntries: [ArchiveEntry] {
        visibleEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    var selectedTotalUncompressedBytes: UInt64 {
        let picked = selectedEntries
        guard !picked.isEmpty, let allEntries = listing?.entries else { return 0 }
        var total: UInt64 = 0
        var countedPaths: Set<String> = []
        for item in picked {
            if item.isDirectory {
                for entry in allEntries where !entry.isDirectory && entry.path.hasPrefix(item.path) {
                    if countedPaths.insert(entry.path).inserted {
                        total += entry.uncompressedSize
                    }
                }
            } else if countedPaths.insert(item.path).inserted {
                total += item.uncompressedSize
            }
        }
        return total
    }

    // MARK: - Private Query & Sort Helpers

    private func searchScopedEntries(of entries: [ArchiveEntry], prefix: String, query: String) -> [ArchiveEntry] {
        var scopedByPath: [String: ArchiveEntry] = [:]
        for entry in entries where entry.path.hasPrefix(prefix) && entry.path != prefix {
            let remainder = String(entry.path.dropFirst(prefix.count))
            let parts = remainder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { continue }

            // Synthesize intermediate folders within `currentFolder` so archives without
            // explicit directory records still surface matching folders during search.
            var acc = prefix
            let folderParts = entry.isDirectory ? parts : Array(parts.dropLast())
            for folderName in folderParts {
                acc += folderName + "/"
                if scopedByPath[acc] == nil {
                    scopedByPath[acc] = syntheticFolderEntry(path: acc, modifiedDate: entry.modifiedDate)
                }
            }
            scopedByPath[entry.path] = entry
        }

        let matchRelPath = query.contains("/")
        return scopedByPath.values.filter { entry in
            if entry.name.localizedCaseInsensitiveContains(query) {
                return true
            }
            if matchRelPath {
                let remainder = String(entry.path.dropFirst(prefix.count))
                return remainder.localizedCaseInsensitiveContains(query)
            }
            return false
        }
    }

    private func directChildren(of entries: [ArchiveEntry], prefix: String) -> [ArchiveEntry] {
        var directByPath: [String: ArchiveEntry] = [:]
        for entry in entries where entry.path.hasPrefix(prefix) && entry.path != prefix {
            let remainder = String(entry.path.dropFirst(prefix.count))
            let parts = remainder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let first = parts.first else { continue }
            if parts.count == 1 && !entry.isDirectory {
                directByPath[entry.path] = entry
            } else {
                let folderPath = prefix + first + "/"
                if directByPath[folderPath] == nil {
                    directByPath[folderPath] = syntheticFolderEntry(path: folderPath, modifiedDate: entry.modifiedDate)
                }
            }
        }
        return Array(directByPath.values)
    }

    private func syntheticFolderEntry(path: String, modifiedDate: Date) -> ArchiveEntry {
        ArchiveEntry(
            path: path,
            isDirectory: true,
            uncompressedSize: 0,
            compressedSize: 0,
            compressionMethodName: "Folder",
            crc32: 0,
            modifiedDate: modifiedDate,
            permissions: 0o755
        )
    }

    private func sortEntries(_ items: inout [ArchiveEntry]) {
        items.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            let result: ComparisonResult
            switch sortColumn {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .uncompressedSize:
                result = lhs.uncompressedSize == rhs.uncompressedSize
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.uncompressedSize < rhs.uncompressedSize ? .orderedAscending : .orderedDescending)
            case .compressedSize:
                result = lhs.compressedSize == rhs.compressedSize
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.compressedSize < rhs.compressedSize ? .orderedAscending : .orderedDescending)
            case .ratio:
                result = lhs.compressionRatioPercent == rhs.compressionRatioPercent
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.compressionRatioPercent < rhs.compressionRatioPercent ? .orderedAscending : .orderedDescending)
            case .method:
                let m = lhs.compressionMethodName.localizedStandardCompare(rhs.compressionMethodName)
                result = m == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : m
            case .modifiedDate:
                result = lhs.modifiedDate == rhs.modifiedDate
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.modifiedDate < rhs.modifiedDate ? .orderedAscending : .orderedDescending)
            }
            return sortAscending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }
}
