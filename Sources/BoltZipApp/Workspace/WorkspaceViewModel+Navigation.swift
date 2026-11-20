import BoltZipCore
import Foundation

extension WorkspaceViewModel {
    var canNavigateUp: Bool { !currentFolder.isEmpty }
    var canNavigateDown: Bool { !folderForwardStack.isEmpty }
    var isSearchingActive: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var selectedEntries: [ArchiveEntry] { selectedEntriesCache }

    func selectAllVisibleEntries() {
        selectedEntryIDs = Set(visibleEntries.map(\.id))
    }

    func copySelectedEntryNames() {
        let picked = selectedEntries
        guard !picked.isEmpty else { return }
        let names = picked.map(\.name).joined(separator: "\n")
        copyToPasteboard(names)
    }

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
            let index = prebuiltIndex ?? ArchiveNavigationIndex.build(from: newListing)
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
            let built = ArchiveNavigationIndex.build(from: listing)
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
