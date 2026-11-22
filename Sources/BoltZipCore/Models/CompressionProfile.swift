import Foundation

public struct CompressionProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var format: ArchiveFormat
    public var algorithm: CompressionAlgorithm
    public var level: Int
    /// Encryption algorithm only. Passwords are never persisted inside compression profiles.
    public var encryption: EncryptionMethod
    public var encryptFileNames: Bool
    public var splitVolumeSizeBytes: UInt64?
    public var excludeMacJunk: Bool
    public var excludePatterns: [String]
    public var preserveSymlinks: Bool
    public var encoding: FilenameEncodingOption
    public var namingTemplate: String
    public var isDefaultQuickPreset: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        format: ArchiveFormat = .zip,
        algorithm: CompressionAlgorithm = .deflate,
        level: Int? = nil,
        encryption: EncryptionMethod = .none,
        encryptFileNames: Bool = false,
        splitVolumeSizeBytes: UInt64? = nil,
        excludeMacJunk: Bool = true,
        excludePatterns: [String] = [],
        preserveSymlinks: Bool = true,
        encoding: FilenameEncodingOption = .utf8,
        namingTemplate: String = "{name}",
        isDefaultQuickPreset: Bool = false
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.algorithm = algorithm
        self.level = level ?? algorithm.defaultLevel
        self.encryption = encryption
        self.encryptFileNames = encryptFileNames
        self.splitVolumeSizeBytes = splitVolumeSizeBytes
        self.excludeMacJunk = excludeMacJunk
        self.excludePatterns = excludePatterns
        self.preserveSymlinks = preserveSymlinks
        self.encoding = encoding
        self.namingTemplate = namingTemplate
        self.isDefaultQuickPreset = isDefaultQuickPreset
        self.sanitize()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case format
        case algorithm
        case level
        case encryption
        case encryptFileNames
        case splitVolumeSizeBytes
        case excludeMacJunk
        case excludePatterns
        case preserveSymlinks
        case encoding
        case namingTemplate
        case isDefaultQuickPreset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = (try? container.decode(ArchiveFormat.self, forKey: .format)) ?? .zip
        let algorithm = (try? container.decode(CompressionAlgorithm.self, forKey: .algorithm)) ?? format.defaultAlgorithm
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Preset"
        self.format = format
        self.algorithm = algorithm
        self.level = (try? container.decode(Int.self, forKey: .level)) ?? algorithm.defaultLevel
        self.encryption = (try? container.decode(EncryptionMethod.self, forKey: .encryption)) ?? .none
        self.encryptFileNames = (try? container.decode(Bool.self, forKey: .encryptFileNames)) ?? false
        self.splitVolumeSizeBytes = try? container.decodeIfPresent(UInt64.self, forKey: .splitVolumeSizeBytes)
        self.excludeMacJunk = (try? container.decode(Bool.self, forKey: .excludeMacJunk)) ?? true
        self.excludePatterns = (try? container.decode([String].self, forKey: .excludePatterns)) ?? []
        self.preserveSymlinks = (try? container.decode(Bool.self, forKey: .preserveSymlinks)) ?? true
        self.encoding = (try? container.decode(FilenameEncodingOption.self, forKey: .encoding)) ?? .utf8
        self.namingTemplate = (try? container.decode(String.self, forKey: .namingTemplate)) ?? "{name}"
        self.isDefaultQuickPreset = (try? container.decode(Bool.self, forKey: .isDefaultQuickPreset)) ?? false
        self.sanitize()
    }

    public mutating func sanitize() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ArchiveFormat.creatableFormats.contains(format) {
            format = .zip
        }
        if !format.supportedAlgorithms.contains(algorithm) {
            algorithm = format.defaultAlgorithm
        }
        let range = algorithm.levelRange
        level = min(range.upperBound, max(range.lowerBound, level))
        if !format.supportsEncryption {
            encryption = .none
        } else if format == .sevenZip && encryption != .none {
            encryption = .aes256
        }
        if !format.supportsFilenameEncryption || encryption != .aes256 {
            encryptFileNames = false
        }
        if !format.supportsSplitVolumes {
            splitVolumeSizeBytes = nil
        } else if let split = splitVolumeSizeBytes, split < 65536 {
            splitVolumeSizeBytes = nil
        }
        excludePatterns = ArchiveExcludeMatcher.normalize(excludePatterns)
        let sanitizedTemplate = Self.sanitizeFilenameComponent(namingTemplate)
        namingTemplate = sanitizedTemplate.isEmpty ? "{name}" : sanitizedTemplate
    }

    public func sanitized() -> CompressionProfile {
        var copy = self
        copy.sanitize()
        return copy
    }

    public static func defaultBaseStem(for inputs: [URL], format: ArchiveFormat) -> String {
        guard !inputs.isEmpty else { return "Archive" }
        if inputs.count == 1, let single = inputs.first {
            let isDir = (try? single.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if format.isSingleFileStream {
                return single.lastPathComponent
            }
            if isDir {
                return single.lastPathComponent
            }
            let stem = single.deletingPathExtension().lastPathComponent
            return stem.isEmpty ? single.lastPathComponent : stem
        }
        let parent = inputs.first?.deletingLastPathComponent().lastPathComponent ?? ""
        return parent.isEmpty || parent == "/" ? "Archive" : parent
    }

    public static func resolveBaseStem(
        template: String,
        defaultStem: String,
        format: ArchiveFormat,
        date: Date = Date()
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTemplate = trimmed.isEmpty ? "{name}" : trimmed
        let safeDefault = sanitizeFilenameComponent(defaultStem.isEmpty ? "Archive" : defaultStem)

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "HHmmss"
        let dateStr = dateFmt.string(from: date)
        let timeStr = timeFmt.string(from: date)

        var rendered = effectiveTemplate
            .replacingOccurrences(of: "{name}", with: safeDefault)
            .replacingOccurrences(of: "{date}", with: dateStr)
            .replacingOccurrences(of: "{time}", with: timeStr)
            .replacingOccurrences(of: "{datetime}", with: "\(dateStr)_\(timeStr)")
            .replacingOccurrences(of: "{format}", with: format.fileExtension)

        rendered = sanitizeFilenameComponent(rendered)
        return rendered.isEmpty ? safeDefault : rendered
    }

    public func resolveOutputURL(
        for inputs: [URL],
        in directory: URL,
        fallbackStem: String? = nil,
        deduplicating: Bool = true,
        reservedPaths: Set<String> = [],
        date: Date = Date()
    ) -> URL {
        let base = fallbackStem ?? Self.defaultBaseStem(for: inputs, format: format)
        let stem = Self.resolveBaseStem(template: namingTemplate, defaultStem: base, format: format, date: date)
        return Self.makeOutputURL(
            stem: stem,
            format: format,
            splitVolumeSizeBytes: splitVolumeSizeBytes,
            in: directory,
            deduplicating: deduplicating,
            reservedPaths: reservedPaths
        )
    }

    public static func makeOutputURL(
        stem: String,
        format: ArchiveFormat,
        splitVolumeSizeBytes: UInt64?,
        in directory: URL,
        deduplicating: Bool = true,
        reservedPaths: Set<String> = []
    ) -> URL {
        let fm = FileManager.default
        let isSplit = format.supportsSplitVolumes && (splitVolumeSizeBytes ?? 0) >= 65536
        func candidatePaths(index: Int) -> (output: URL, collisionURLs: [URL]) {
            let suffixedStem = index == 0 ? stem : "\(stem) (\(index))"
            let mainURL = directory.appendingPathComponent("\(suffixedStem).\(format.fileExtension)")
            if isSplit && format == .sevenZip {
                let firstVol = directory.appendingPathComponent("\(suffixedStem).7z.001")
                return (firstVol, [mainURL, firstVol])
            }
            if isSplit && format == .zip {
                let firstVol = directory.appendingPathComponent("\(suffixedStem).z01")
                return (mainURL, [mainURL, firstVol])
            }
            return (mainURL, [mainURL])
        }

        if !deduplicating {
            return candidatePaths(index: 0).output
        }

        var idx = 0
        while idx < 10_000 {
            let candidate = candidatePaths(index: idx)
            let collides = candidate.collisionURLs.contains { url in
                fm.fileExists(atPath: url.path)
                    || reservedPaths.contains(ArchiveExtractionDestination.pathKey(url))
            }
            if !collides {
                return candidate.output
            }
            idx += 1
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(6)).\(format.fileExtension)")
    }

    private static func sanitizeFilenameComponent(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if replaced == "." || replaced == ".." {
            return "Archive"
        }
        return replaced
    }

    public static var starterTemplates: [CompressionProfile] {
        [
            CompressionProfile(
                name: "Standard ZIP",
                format: .zip,
                algorithm: .deflate,
                level: 6,
                excludeMacJunk: true,
                namingTemplate: "{name}"
            ),
            CompressionProfile(
                name: "7z Max Compression",
                format: .sevenZip,
                algorithm: .xz,
                level: 9,
                excludeMacJunk: true,
                namingTemplate: "{name}_{date}"
            ),
            CompressionProfile(
                name: "Zstandard Fast TAR",
                format: .tarZst,
                algorithm: .zstd,
                level: 6,
                excludeMacJunk: true,
                excludePatterns: [".git", "node_modules", "*.tmp"],
                namingTemplate: "{name}"
            )
        ]
    }
}

extension CreateArchiveOptions {
    public init(
        profile: CompressionProfile,
        password: String? = nil,
        archiveComment: String = "",
        workerCount: Int? = nil
    ) {
        let clean = profile.sanitized()
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        self.init(
            format: clean.format,
            algorithm: clean.algorithm,
            level: clean.level,
            encryption: effectivePassword != nil && clean.encryption != .none ? clean.encryption : .none,
            password: effectivePassword,
            splitVolumeSizeBytes: clean.splitVolumeSizeBytes,
            excludeMacJunk: clean.excludeMacJunk,
            excludePatterns: clean.excludePatterns,
            encoding: clean.encoding,
            archiveComment: clean.format.supportsArchiveComment ? archiveComment : "",
            workerCount: workerCount,
            preserveSymlinks: clean.preserveSymlinks,
            encryptFileNames: effectivePassword != nil && clean.encryptFileNames
        )
    }
}

public struct CompressionProfileStore: Sendable {
    public let fileURL: URL

    public static var defaultDirectoryURL: URL {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("BoltZip", isDirectory: true)
        }
        return fm.temporaryDirectory.appendingPathComponent("BoltZip", isDirectory: true)
    }

    public static let shared = CompressionProfileStore()

    public init(directoryURL: URL = CompressionProfileStore.defaultDirectoryURL) {
        self.fileURL = directoryURL.appendingPathComponent("compression_profiles.json")
    }

    public func load() -> [CompressionProfile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode([CompressionProfile].self, from: data) else { return [] }
        return decoded.map { $0.sanitized() }
    }

    public func save(_ profiles: [CompressionProfile]) throws {
        var cleaned = profiles.map { $0.sanitized() }
        // Guarantee at most one default quick preset, preferring the latest marked entry
        if let lastQuickIdx = cleaned.lastIndex(where: \.isDefaultQuickPreset) {
            for idx in cleaned.indices where idx != lastQuickIdx {
                cleaned[idx].isDefaultQuickPreset = false
            }
        }
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cleaned)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func upsert(_ profile: CompressionProfile) throws -> CompressionProfile {
        var all = load()
        var clean = profile.sanitized()
        if clean.isDefaultQuickPreset {
            for idx in all.indices { all[idx].isDefaultQuickPreset = false }
        }
        if let idx = all.firstIndex(where: { $0.id == clean.id || $0.name.compare(clean.name, options: .caseInsensitive) == .orderedSame }) {
            clean.id = all[idx].id
            all[idx] = clean
        } else {
            all.append(clean)
        }
        try save(all)
        return clean
    }

    public func delete(id: UUID) throws {
        var all = load()
        all.removeAll { $0.id == id }
        try save(all)
    }

    public func delete(named name: String) throws -> Bool {
        var all = load()
        let before = all.count
        all.removeAll { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        guard all.count != before else { return false }
        try save(all)
        return true
    }

    public func find(namedOrID key: String) -> CompressionProfile? {
        let all = load()
        if let uuid = UUID(uuidString: key), let byID = all.first(where: { $0.id == uuid }) {
            return byID
        }
        return all.first { $0.name.compare(key, options: .caseInsensitive) == .orderedSame }
    }

    public func defaultQuickPreset() -> CompressionProfile? {
        let all = load()
        return all.first(where: \.isDefaultQuickPreset) ?? all.first
    }
}
