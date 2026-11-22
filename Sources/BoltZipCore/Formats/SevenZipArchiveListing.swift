import Foundation

enum SevenZipArchiveListing {
    struct Catalog {
        let entries: [ArchiveEntry]
        let linkTargets: [String: String]
        let hardLinkTargets: [String: String]
    }

    static func typeArguments(for format: ArchiveFormat, allowSplitVolumes: Bool = false) -> [String] {
        (format == .sevenZip && !allowSplitVolumes) ? ["-t7z"] : []
    }

    static func list(archiveURL: URL, password: String?, format: ArchiveFormat = .sevenZip,
                     allowSplitVolumes: Bool = false, matching selectors: [String] = [],
                     controller: ArchiveTaskController? = nil) throws -> [ArchiveEntry] {
        try catalog(archiveURL: archiveURL, password: password, format: format,
                    allowSplitVolumes: allowSplitVolumes, matching: selectors, controller: controller).entries
    }

    static func catalog(archiveURL: URL, password: String?, format: ArchiveFormat,
                        allowSplitVolumes: Bool = false, matching selectors: [String] = [],
                        controller: ArchiveTaskController? = nil) throws -> Catalog {
        let result = try SevenZipCommand.run(
            ["l"] + typeArguments(for: format, allowSplitVolumes: allowSplitVolumes)
                + ["-slt", "-ba", "-sccUTF-8", "-bsp0", "-spd", "-ssc", "--", archiveURL.standardizedFileURL.path] + selectors,
            password: password, controller: controller
        )
        do {
            try check(result, archive: archiveURL, password: password, format: format)
        } catch let error as BoltZipError {
            if format == .rar, case .externalToolFailed = error {
                // Brief listings suppress the volume name. Only retry failed RAR listings in technical mode.
                _ = try rarHasVolumes(archiveURL: archiveURL, password: password, controller: controller)
            }
            throw error
        }
        return try parseEntries(result.stdout, archive: archiveURL, format: format)
    }

    static func rarHasVolumes(archiveURL: URL, password: String?, allowPartialVolumeInfo: Bool = false,
                              controller: ArchiveTaskController? = nil) throws -> Bool {
        let result = try SevenZipCommand.run(
            ["l", "-slt", "-sccUTF-8", "-bsp0", "-spd", "-ssc", "--", archiveURL.standardizedFileURL.path],
            password: password, controller: controller
        )
        let metadata = String(decoding: result.stdout, as: UTF8.self).components(separatedBy: "\n")
            .prefix(while: { $0 != "----------" })
        let hasVolumes = metadata.contains("Multivolume = +")
        if allowPartialVolumeInfo && hasVolumes { return true }
        if result.status != 0, let missing = missingVolume(in: Array(metadata)) {
            throw BoltZipError.missingSplitVolume(missing)
        }
        try check(result, archive: archiveURL, password: password, format: .rar)
        return hasVolumes
    }

    static func check(_ result: SevenZipCommand.Result, archive: URL, password: String?,
                      format: ArchiveFormat = .sevenZip) throws {
        guard result.status != 0 else { return }
        let name = archive.lastPathComponent
        let errors = String(decoding: result.stderr, as: UTF8.self).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let wrongPassword = errors.contains {
            $0 == "Cannot open encrypted archive. Wrong password?"
                || ($0.hasPrefix("ERROR: ") && $0.hasSuffix(" : Cannot open encrypted archive. Wrong password?"))
                || $0.hasPrefix("ERROR: Data Error in encrypted file. Wrong password? : ")
                || $0.hasPrefix("ERROR: CRC Failed in encrypted file. Wrong password? : ")
                || $0.hasPrefix("ERROR: Wrong password : ")
        }
        if format == .rar, let missing = missingVolume(in: errors) {
            throw BoltZipError.missingSplitVolume(missing)
        }
        if password?.isEmpty != false && (wrongPassword ||
            String(decoding: result.stdout, as: UTF8.self).components(separatedBy: "\n").contains("Enter password:")) {
            throw BoltZipError.passwordRequired(name)
        }
        if wrongPassword {
            throw BoltZipError.wrongPassword(name)
        }
        if errors.contains(where: { $0.hasPrefix("ERROR: Unsupported Method : ") }) {
            throw BoltZipError.unsupportedFormat(format.displayName)
        }
        // Child output can include archive-controlled file names. Do not surface it as a diagnostic.
        throw BoltZipError.externalToolFailed("7-Zip (\(result.status)) · \(name)")
    }

    private static func missingVolume(in lines: [String]) -> String? {
        let prefixes = ["Missing volume : ", "ERROR = Missing volume : ", "ERROR: Missing volume : "]
        for line in lines {
            if let prefix = prefixes.first(where: { line.hasPrefix($0) }) {
                let path = String(line.dropFirst(prefix.count))
                let name = URL(fileURLWithPath: path).lastPathComponent
                if !path.isEmpty && hasUnsupportedPathCharacter(path) == false { return name }
            }
        }
        return nil
    }

    private static func parseEntries(_ data: Data, archive: URL, format: ArchiveFormat) throws -> Catalog {
        let name = archive.lastPathComponent
        guard let content = String(data: data, encoding: .utf8) else {
            throw BoltZipError.invalidArchive(name)
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var entries: [ArchiveEntry] = []
        var linkTargets: [String: String] = [:]
        var hardLinkTargets: [String: String] = [:]
        var seen: Set<String> = []
        var fields: [String: String] = [:]
        var allowsPrompt = true

        func endRecord() throws {
            guard !fields.isEmpty else { return }
            let entry = try parseEntry(fields, archive: name, format: format, dateFormatter: dateFormatter)
            let entryKey = entry.isDirectory ? String(entry.path.dropLast()) : entry.path
            guard seen.insert(entryKey).inserted else {
                throw BoltZipError.entryAlreadyExists(entry.path)
            }
            entries.append(entry)
            if let target = fields["Symbolic Link"], !target.isEmpty, entry.isSymbolicLink {
                guard !hasUnsupportedPathCharacter(target) else { throw BoltZipError.invalidArchive(name) }
                linkTargets[entry.path] = target
            }
            if let target = fields["Hard Link"], !target.isEmpty {
                guard !hasUnsupportedPathCharacter(target) else { throw BoltZipError.invalidArchive(name) }
                hardLinkTargets[entry.path] = ArchiveEntry.normalizePath(target, isDirectory: false)
            }
            fields.removeAll(keepingCapacity: true)
        }

        for line in content.components(separatedBy: "\n") {
            if line.isEmpty {
                try endRecord()
                continue
            }
            if allowsPrompt && line == "Enter password:" {
                allowsPrompt = false
                continue
            }
            allowsPrompt = false
            guard let delimiter = line.range(of: " = ") else { throw BoltZipError.invalidArchive(name) }
            let field = String(line[..<delimiter.lowerBound])
            guard fields.isEmpty == (field == "Path"), fields[field] == nil else {
                throw BoltZipError.invalidArchive(name)
            }
            fields[field] = String(line[delimiter.upperBound...])
        }
        try endRecord()
        return Catalog(entries: entries, linkTargets: linkTargets, hardLinkTargets: hardLinkTargets)
    }

    private static func parseEntry(_ fields: [String: String], archive: String, format: ArchiveFormat,
                                   dateFormatter: DateFormatter) throws -> ArchiveEntry {
        guard let path = fields["Path"], !path.isEmpty, !hasUnsupportedPathCharacter(path),
              let size = fields["Size"].flatMap(UInt64.init), let packed = fields["Packed Size"],
              let encrypted = fields["Encrypted"], encrypted == "+" || encrypted == "-",
              let method = fields["Method"] else {
            throw BoltZipError.invalidArchive(archive)
        }
        if format == .rar && (fields["Split Before"] == "+" || fields["Split After"] == "+") {
            // For a complete set 7zz joins an entry's parts before listing it.
            throw BoltZipError.invalidArchive(archive)
        }
        let attributes = fields["Attributes", default: ""].split(separator: " ")
        let mode = attributes.last.flatMap(posixMode)
        let isSymlink = mode?.kind == "l" || fields["Symbolic Link"]?.isEmpty == false
        let isDirectory = !isSymlink && (fields["Folder"] == "+" || mode?.kind == "d"
            || attributes.first.map { !$0.hasPrefix("-") && $0.contains("D") } == true)
        let packedSize = packed.isEmpty ? 0 : UInt64(packed)
        let crc = fields["CRC", default: ""]
        let crc32 = crc.isEmpty ? 0 : UInt32(crc, radix: 16)
        guard let packedSize, let crc32 else {
            throw BoltZipError.invalidArchive(archive)
        }
        let normalizedPath = ArchiveEntry.normalizePath(path, isDirectory: isDirectory)
        guard !normalizedPath.isEmpty else { throw BoltZipError.invalidArchive(archive) }
        let modified = fields["Modified"].flatMap { dateFormatter.date(from: String($0.prefix(19))) }
        let codecs = method.split(separator: " ").filter { !$0.hasPrefix("7zAES") }.joined(separator: " ")
        return ArchiveEntry(
            path: normalizedPath,
            isDirectory: isDirectory,
            isSymbolicLink: isSymlink,
            uncompressedSize: isDirectory ? 0 : size,
            compressedSize: packedSize,
            compressionMethodName: isDirectory ? "" : (codecs.isEmpty || codecs == "Copy" ? CompressionAlgorithm.store.shortName : codecs),
            crc32: crc32,
            modifiedDate: modified ?? Date(timeIntervalSince1970: 0),
            permissions: mode?.permissions ?? (isDirectory ? 0o755 : 0o644),
            isEncrypted: encrypted == "+",
            encryptionLabel: encrypted == "+" ? (format == .rar ? "RAR AES" : "AES-256") : "",
            rawPathBytes: Data(path.utf8)
        )
    }

    private static func posixMode(_ mode: Substring) -> (kind: Character, permissions: UInt16)? {
        guard mode.count == 10, let kind = mode.first, "-dl".contains(kind) else { return nil }
        var permissions: UInt16 = 0
        for (index, character) in mode.dropFirst().enumerated() {
            if "rwxst".contains(character) {
                permissions |= 1 << (8 - index)
            }
        }
        return (kind, permissions)
    }

    static func hasUnsupportedPathCharacter(_ path: String) -> Bool {
        path.utf8.contains { $0 == 0 || $0 == 10 || $0 == 13 }
    }

}
