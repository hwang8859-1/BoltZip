import BoltZipCore
import Foundation

struct ArchiveNavigationIndex: Sendable {
    let folderTree: FolderTreeNode
    let entryByID: [String: ArchiveEntry]
    let defaultSortedByFolder: [String: [ArchiveEntry]]
    let folderRecursiveBytes: [String: UInt64]

    static func build(from listing: ArchiveListing) -> ArchiveNavigationIndex {
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

        let tree = buildTreeNode(path: "", name: listing.archiveURL.lastPathComponent)
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
