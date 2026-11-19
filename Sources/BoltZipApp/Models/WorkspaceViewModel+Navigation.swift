import BoltZipCore
import Foundation

struct ArchiveNavigationIndex: Sendable {
    let folderTree: FolderTreeNode
    let entryByID: [String: ArchiveEntry]
    let defaultSortedByFolder: [String: [ArchiveEntry]]
    let folderRecursiveBytes: [String: UInt64]

    static func build(from listing: ArchiveListing, rootTitle: String) -> ArchiveNavigationIndex {
        let entries = listing.entries
        var entryByID: [String: ArchiveEntry] = [:]
        entryByID.reserveCapacity(entries.count + 64)

        var directByFolder: [String: [String: ArchiveEntry]] = ["": [:]]
        var folderChildren: [String: [String]] = [:]
        var seenFolders: Set<String> = [""]
        var directFileCount: [String: Int] = [:]
        var recursiveBytes: [String: UInt64] = [:]
        var pathSegmentBuffer: [Substring] = []
        pathSegmentBuffer.reserveCapacity(16)

        for entry in entries {
            entryByID[entry.id] = entry

            pathSegmentBuffer.removeAll(keepingCapacity: true)
            for part in entry.path.split(separator: "/", omittingEmptySubsequences: true) {
                pathSegmentBuffer.append(part)
            }
            guard !pathSegmentBuffer.isEmpty else { continue }

            let folderDepth = entry.isDirectory ? pathSegmentBuffer.count : (pathSegmentBuffer.count - 1)
            var parent = ""
            for i in 0..<folderDepth {
                let seg = pathSegmentBuffer[i]
                let folderPath = parent + seg + "/"
                if seenFolders.insert(folderPath).inserted {
                    folderChildren[parent, default: []].append(folderPath)
                }

                let isExplicitThisDir = entry.isDirectory && (i == folderDepth - 1)
                if let existing = directByFolder[parent]?[folderPath] {
                    if isExplicitThisDir && existing.compressionMethodName == "Folder" {
                        directByFolder[parent]?[folderPath] = entry
                    }
                } else {
                    let dirEntry = isExplicitThisDir
                        ? entry
                        : syntheticFolderEntry(path: folderPath, name: String(seg), modifiedDate: entry.modifiedDate)
                    directByFolder[parent, default: [:]][folderPath] = dirEntry
                    if entryByID[dirEntry.id] == nil {
                        entryByID[dirEntry.id] = dirEntry
                    }
                }

                if !entry.isDirectory {
                    recursiveBytes[folderPath, default: 0] &+= entry.uncompressedSize
                }
                parent = folderPath
            }

            if !entry.isDirectory {
                directFileCount[parent, default: 0] += 1
                directByFolder[parent, default: [:]][entry.path] = entry
                recursiveBytes["", default: 0] &+= entry.uncompressedSize
            }
        }

        // Pre-sort direct children per folder by default order (folders first, .name ascending) on background thread.
        var defaultSortedByFolder: [String: [ArchiveEntry]] = [:]
        defaultSortedByFolder.reserveCapacity(directByFolder.count)
        for (folder, map) in directByFolder {
            var items = Array(map.values)
            sortEntries(&items, column: .name, ascending: true)
            defaultSortedByFolder[folder] = items
        }

        func buildTreeNode(path: String, name: String) -> FolderTreeNode {
            let rawChildren = folderChildren[path] ?? []
            let sortedChildren = rawChildren.sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            let childNodes = sortedChildren.map { childPath -> FolderTreeNode in
                let trimmed = childPath.hasSuffix("/") ? childPath.dropLast() : Substring(childPath)
                let childName: String
                if let slashIdx = trimmed.lastIndex(of: "/") {
                    childName = String(trimmed[trimmed.index(after: slashIdx)...])
                } else {
                    childName = String(trimmed)
                }
                return buildTreeNode(path: childPath, name: childName)
            }
            return FolderTreeNode(
                id: path,
                name: name,
                path: path,
                children: childNodes,
                fileCount: directFileCount[path, default: 0]
            )
        }

        let tree = buildTreeNode(path: "", name: rootTitle)
        return ArchiveNavigationIndex(
            folderTree: tree,
            entryByID: entryByID,
            defaultSortedByFolder: defaultSortedByFolder,
            folderRecursiveBytes: recursiveBytes
        )
    }

    static func syntheticFolderEntry(path: String, name: String? = nil, modifiedDate: Date) -> ArchiveEntry {
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

    static func sortEntries(_ items: inout [ArchiveEntry], column: SortColumn, ascending: Bool) {
        items.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            let result: ComparisonResult
            switch column {
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
            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }
}

extension WorkspaceViewModel {
    var canNavigateUp: Bool { !currentFolder.isEmpty }
    var canNavigateDown: Bool { !folderForwardStack.isEmpty }
    var isSearchingActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var selectedEntries: [ArchiveEntry] { selectedEntriesCache }

    func applyLoadedListing(
        _ newListing: ArchiveListing?,
        prebuiltIndex: ArchiveNavigationIndex? = nil,
        openedFromHome: Bool? = nil,
        initialFolder: String = "",
        clearForwardStack: Bool = true,
        clearSearch: Bool = true
    ) {
        isBatchUpdatingNavigation = true
        defer {
            isBatchUpdatingNavigation = false
            rebuildNavigationViews()
        }

        self.listing = newListing
        if let newListing {
            let index = prebuiltIndex ?? ArchiveNavigationIndex.build(
                from: newListing,
                rootTitle: newListing.archiveURL.lastPathComponent
            )
            self.navigationIndex = index
            self.folderTree = index.folderTree
        } else {
            self.navigationIndex = nil
            self.folderTree = FolderTreeNode(id: "", name: l10n.rootLabel, path: "", children: [], fileCount: 0)
        }

        if let openedFromHome {
            self.openedArchiveFromHome = openedFromHome
        }
        self.currentFolder = initialFolder
        if clearForwardStack {
            self.folderForwardStack.removeAll()
        }
        if clearSearch {
            self.searchText = ""
        }
        self.selectedEntryIDs.removeAll()
    }

    func returnToArchiveRoot() {
        isBatchUpdatingNavigation = true
        searchText = ""
        isBatchUpdatingNavigation = false
        navigateToFolder("")
        if currentFolder.isEmpty {
            refreshVisibleEntries()
        }
    }

    func toggleSortColumn(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            isBatchUpdatingNavigation = true
            sortColumn = column
            sortAscending = true
            isBatchUpdatingNavigation = false
            refreshVisibleEntries()
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
        isBatchUpdatingNavigation = true
        searchText = ""
        let targetChanged = (parentFolder != currentFolder)
        if targetChanged {
            let isAncestor = parentFolder.isEmpty ? !currentFolder.isEmpty : (currentFolder.hasPrefix(parentFolder) && currentFolder != parentFolder)
            if isAncestor {
                if folderForwardStack.last != currentFolder {
                    folderForwardStack.append(currentFolder)
                }
            } else if folderForwardStack.last == parentFolder {
                _ = folderForwardStack.popLast()
            } else {
                folderForwardStack.removeAll()
            }
            currentFolder = parentFolder
        }
        selectedEntryIDs = [entry.id]
        isBatchUpdatingNavigation = false
        rebuildNavigationViews()
    }

    func navigateToFolder(_ path: String) {
        guard path != currentFolder else {
            if !selectedEntryIDs.isEmpty {
                selectedEntryIDs.removeAll()
            }
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
        isBatchUpdatingNavigation = true
        selectedEntryIDs.removeAll()
        currentFolder = path
        isBatchUpdatingNavigation = false
        rebuildNavigationViews()
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
        isBatchUpdatingNavigation = true
        selectedEntryIDs.removeAll()
        currentFolder = parent
        isBatchUpdatingNavigation = false
        rebuildNavigationViews()
    }

    func navigateDown() {
        guard let next = folderForwardStack.popLast() else { return }
        isBatchUpdatingNavigation = true
        selectedEntryIDs.removeAll()
        currentFolder = next
        isBatchUpdatingNavigation = false
        rebuildNavigationViews()
    }

    func rebuildNavigationViews() {
        var crumbs: [(String, String)] = [(l10n.rootLabel, "")]
        if !currentFolder.isEmpty {
            let parts = currentFolder.split(separator: "/")
            var acc = ""
            for p in parts {
                acc += p + "/"
                crumbs.append((String(p), acc))
            }
        }
        breadcrumbComponents = crumbs
        refreshVisibleEntries()
    }

    func refreshVisibleEntries() {
        guard let listing else {
            visibleEntries = []
            visibleEntryByID = [:]
            refreshSelectionCache()
            return
        }
        let index: ArchiveNavigationIndex
        if let existing = navigationIndex {
            index = existing
        } else {
            let built = ArchiveNavigationIndex.build(from: listing, rootTitle: listing.archiveURL.lastPathComponent)
            navigationIndex = built
            folderTree = built.folderTree
            index = built
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [ArchiveEntry]
        if query.isEmpty {
            items = index.defaultSortedByFolder[currentFolder] ?? []
            if sortColumn != .name || !sortAscending {
                if sortColumn == .name && !sortAscending {
                    let firstFileIdx = items.firstIndex(where: { !$0.isDirectory }) ?? items.count
                    if firstFileIdx > 1 {
                        items[0..<firstFileIdx].reverse()
                    }
                    if items.count - firstFileIdx > 1 {
                        items[firstFileIdx..<items.count].reverse()
                    }
                } else {
                    ArchiveNavigationIndex.sortEntries(&items, column: sortColumn, ascending: sortAscending)
                }
            }
        } else {
            items = searchScopedEntries(of: listing.entries, prefix: currentFolder, query: query)
            ArchiveNavigationIndex.sortEntries(&items, column: sortColumn, ascending: sortAscending)
        }

        visibleEntries = items
        var map: [String: ArchiveEntry] = [:]
        map.reserveCapacity(items.count)
        for item in items {
            map[item.id] = item
        }
        visibleEntryByID = map
        refreshSelectionCache()
    }

    func refreshSelectionCache() {
        guard !selectedEntryIDs.isEmpty else {
            selectedEntriesCache = []
            selectedTotalUncompressedBytes = 0
            return
        }

        var picked: [ArchiveEntry] = []
        picked.reserveCapacity(selectedEntryIDs.count)
        for id in selectedEntryIDs {
            if let hit = visibleEntryByID[id] ?? navigationIndex?.entryByID[id] {
                picked.append(hit)
            }
        }
        selectedEntriesCache = picked

        guard let index = navigationIndex else {
            selectedTotalUncompressedBytes = 0
            return
        }

        if picked.count == 1, let single = picked.first {
            selectedTotalUncompressedBytes = single.isDirectory
                ? (index.folderRecursiveBytes[single.path] ?? 0)
                : single.uncompressedSize
            return
        }

        let selectedDirs = picked.filter(\.isDirectory).sorted { $0.path.count < $1.path.count }
        var topDirs: [ArchiveEntry] = []
        for dir in selectedDirs {
            if !topDirs.contains(where: { dir.path.hasPrefix($0.path) }) {
                topDirs.append(dir)
            }
        }

        var total: UInt64 = 0
        for dir in topDirs {
            total &+= (index.folderRecursiveBytes[dir.path] ?? 0)
        }
        for item in picked where !item.isDirectory {
            if !topDirs.contains(where: { item.path.hasPrefix($0.path) }) {
                total &+= item.uncompressedSize
            }
        }
        selectedTotalUncompressedBytes = total
    }

    // MARK: - Private Fast Scoped Search

    private func searchScopedEntries(of entries: [ArchiveEntry], prefix: String, query: String) -> [ArchiveEntry] {
        let matchRelPath = query.contains("/")
        var resultsByPath: [String: ArchiveEntry] = [:]
        var checkedAncestors: Set<String> = []

        for entry in entries where entry.path.hasPrefix(prefix) && entry.path != prefix {
            let remainderStart = entry.path.index(entry.path.startIndex, offsetBy: prefix.count)
            let remainder = entry.path[remainderStart...]

            if entry.name.localizedCaseInsensitiveContains(query) ||
               (matchRelPath && remainder.localizedCaseInsensitiveContains(query)) {
                resultsByPath[entry.path] = entry
            }

            // Only check intermediate folders not yet evaluated in this search
            if let slashIdx = remainder.firstIndex(of: "/") {
                var acc = prefix
                var cursor = remainder.startIndex
                var idx: String.Index? = slashIdx
                while let slash = idx {
                    let seg = remainder[cursor..<slash]
                    if !seg.isEmpty {
                        acc += seg + "/"
                        if checkedAncestors.insert(acc).inserted {
                            let matchSeg = String(seg).localizedCaseInsensitiveContains(query)
                            let matchAccRel = matchRelPath && acc.dropFirst(prefix.count).localizedCaseInsensitiveContains(query)
                            if (matchSeg || matchAccRel), resultsByPath[acc] == nil {
                                resultsByPath[acc] = navigationIndex?.entryByID[acc]
                                    ?? ArchiveNavigationIndex.syntheticFolderEntry(path: acc, modifiedDate: entry.modifiedDate)
                            }
                        }
                    }
                    cursor = remainder.index(after: slash)
                    idx = remainder[cursor...].firstIndex(of: "/")
                }
            }
        }

        return Array(resultsByPath.values)
    }
}
