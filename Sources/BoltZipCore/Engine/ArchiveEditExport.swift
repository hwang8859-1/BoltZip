import Foundation

extension BoltArchiveEngine {
    public static func exportSelectedEntriesAsZip(
        at source: URL, to destination: URL, entryPaths: Set<String>,
        password: String? = nil, encoding: FilenameEncodingOption = .auto, stripMacJunk: Bool = true
    ) throws {
        guard !entryPaths.isEmpty else { throw BoltZipError.entryNotFound(source.lastPathComponent) }

        let protected = Set(try extractionSourceURLs(archiveURL: source, password: password)
            .map(ArchiveExtractionDestination.pathKey))
        guard !protected.contains(ArchiveExtractionDestination.pathKey(destination)) else {
            throw ArchiveOperationError.outputIsInput
        }

        let stage = try ArchiveOutputTransaction.makeStage(for: destination)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: stage) }
        let contents = stage.appendingPathComponent("contents", isDirectory: true)
        try extract(archiveURL: source, options: ExtractOptions(
            destinationURL: contents, mode: .selected(entryPaths), password: password,
            encoding: encoding, stripMacJunk: stripMacJunk
        ))
        let inputs = try fm.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil)
        let zip = stage.appendingPathComponent("export.zip")
        try createArchive(from: inputs, to: zip, options: CreateArchiveOptions(excludeMacJunk: stripMacJunk))

        guard !protected.contains(ArchiveExtractionDestination.pathKey(destination)) else {
            throw ArchiveOperationError.outputIsInput
        }
        try ArchiveOutputTransaction.publish([zip], to: [destination])
    }

    /// Explicit fallback: decode into private staging and produce a real ZIP at a new path.
    public static func exportEditedArchiveAsZip(at source: URL, to destination: URL,
        operations: [ZipEditOperation], password: String? = nil,
        encoding: FilenameEncodingOption = .auto) throws {
        guard destination.pathExtension.lowercased() == "zip",
              destination.resolvingSymlinksInPath() != source.resolvingSymlinksInPath() else {
            throw ArchiveOperationError.outputIsInput
        }
        let stage = try ArchiveOutputTransaction.makeStage(for: destination)
        defer { try? FileManager.default.removeItem(at: stage) }
        let contents = stage.appendingPathComponent("contents", isDirectory: true)
        let listing = try inspect(archiveURL: source, encoding: encoding, password: password)
        var seen: Set<String> = []
        for entry in listing.entries where !seen.insert(entry.path).inserted {
            throw ArchiveEditCompatibilityError.ambiguousEntry(entry.path)
        }
        try extract(archiveURL: source, options: ExtractOptions(destinationURL: contents, mode: .here,
            overwritePolicy: .overwrite, password: password, encoding: encoding, stripMacJunk: false))
        var comment = listing.comment
        let fm = FileManager.default
        func destinationFor(_ path: String) throws -> URL {
            let url = try ArchiveExtractionDestination.safeDestinationURL(for: path, under: contents)
            try ArchiveExtractionDestination.assertNoSymlinkTraversal(at: url, under: contents)
            return url
        }
        func copy(_ input: URL, to path: String) throws {
            let target = try destinationFor(path)
            let inputType = try fm.attributesOfItem(atPath: input.path)[.type] as? FileAttributeType
            if inputType == .typeDirectory,
               (try? fm.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType) == .typeDirectory {
                for child in try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil) {
                    try copy(child, to: path + (path.hasSuffix("/") ? "" : "/") + child.lastPathComponent)
                }
                return
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.attributesOfItem(atPath: target.path)) != nil { try fm.removeItem(at: target) }
            try fm.copyItem(at: input, to: target)
        }
        for operation in operations {
            switch operation {
            case .deletePaths(let paths):
                for path in paths {
                    let url = try destinationFor(path)
                    if (try? fm.attributesOfItem(atPath: url.path)) != nil { try fm.removeItem(at: url) }
                }
            case .renamePath(let old, let new):
                let from = try destinationFor(old), to = try destinationFor(new)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
            case .createFolder(let path):
                try fm.createDirectory(at: destinationFor(path), withIntermediateDirectories: true)
            case .addItems(let urls, let folder):
                for url in urls { try copy(url, to: folder + (folder.isEmpty || folder.hasSuffix("/") ? "" : "/") + url.lastPathComponent) }
            case .replaceEntry(let path, let file): try copy(file, to: path)
            case .setComment(let value): comment = value
            }
        }
        let staged = stage.appendingPathComponent("export.zip")
        let inputs = try fm.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil)
        try createArchive(from: inputs, to: staged,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate,
                encryption: (password ?? "").isEmpty ? .none : .aes256, password: password,
                excludeMacJunk: false, archiveComment: comment))
        guard try ZipReader(url: staged).testIntegrity(password: password, encoding: .auto).isHealthy else {
            throw BoltZipError.invalidArchive(staged.lastPathComponent)
        }
        try ArchiveOutputTransaction.publish([staged], to: [destination])
    }
}
