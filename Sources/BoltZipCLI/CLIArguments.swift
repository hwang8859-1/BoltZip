import BoltZipCore
import Foundation

struct CLIArguments {
    let positional: [String]
    let options: [String: String]
    let multiOptions: [String: [String]]
    let flags: Set<String>

    var useJSON: Bool { flags.contains("json") }
    var password: String? { options["password"] }
    var allowInteractivePasswordPrompt: Bool {
        guard password == nil && !flags.contains("password-stdin") else { return false }
        if flags.contains("ask-password") { return true }
        return !useJSON && CLIPasswordInput.isInteractiveTTY
    }
    var encoding: FilenameEncodingOption {
        options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
    }
    var stripMacJunk: Bool { !flags.contains("keep-junk") }
    var restoreSymlinks: Bool { !flags.contains("no-symlinks") }
    var excludePatterns: [String] {
        (multiOptions["exclude"] ?? []).flatMap { ArchiveExcludeMatcher.parse($0) }
    }
    var presetName: String? { options["preset"] }
    var namePattern: String? { options["name-pattern"] }

    func resolvedEncryption(password: String?, defaultEncryption: EncryptionMethod = .none) -> EncryptionMethod {
        guard let password, !password.isEmpty else { return .none }
        if flags.contains("zipcrypto") { return .zipCrypto }
        if flags.contains("aes256") { return .aes256 }
        return defaultEncryption == .none ? .aes256 : defaultEncryption
    }

    var extractionPaths: (archive: URL, destination: URL)? {
        guard let path = positional.first else { return nil }
        let archive = URL(fileURLWithPath: path)
        let destination = positional.dropFirst().first.map { URL(fileURLWithPath: $0) }
            ?? archive.deletingLastPathComponent()
        return (archive, destination)
    }

    init(_ args: [String]) {
        let booleanFlags: Set<String> = [
            "aes256", "zipcrypto", "encrypt-filenames", "keep-junk", "no-symlinks",
            "status", "restore", "include-iso", "json", "quiet",
            "password-stdin", "ask-password", "quick"
        ]

        var positional: [String] = []
        var options: [String: String] = [:]
        var multiOptions: [String: [String]] = [:]
        var flags: Set<String> = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if booleanFlags.contains(key) {
                    flags.insert(key)
                    i += 1
                } else if i + 1 < args.count {
                    let val = args[i + 1]
                    options[key] = val
                    multiOptions[key, default: []].append(val)
                    i += 2
                } else {
                    i += 1
                }
            } else {
                positional.append(a)
                i += 1
            }
        }

        self.positional = positional
        self.options = options
        self.multiOptions = multiOptions
        self.flags = flags
    }

    func workerCount() throws -> Int? {
        guard let raw = (options["threads"] ?? options["cores"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if raw.caseInsensitiveCompare("auto") == .orderedSame {
            return 0
        }
        guard let parsed = Int(raw), parsed >= 1 else {
            throw BoltZipError.ioError("Invalid --threads value '\(raw)'. Expected 'auto' or an integer >= 1.")
        }
        return parsed
    }

    func splitVolumeSizeBytes() throws -> UInt64? {
        guard let raw = options["split"] else { return nil }
        let bytesPerMiB: UInt64 = 1024 * 1024
        guard let size = UInt64(raw), size <= UInt64.max / bytesPerMiB else {
            throw BoltZipError.ioError("Invalid --split size. Enter a whole number from 0 to \(UInt64.max / bytesPerMiB) MiB.")
        }
        return size * bytesPerMiB
    }

    func overwritePolicy() throws -> OverwritePolicy {
        let raw = options["overwrite"]
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return .overwrite
        }
        switch raw {
        case "overwrite": return .overwrite
        case "skip": return .skip
        case "rename": return .rename
        default:
            throw BoltZipError.ioError("Invalid --overwrite value '\(raw)'. Expected overwrite, skip, or rename.")
        }
    }

    func compression(default defaultAlgorithm: CompressionAlgorithm) -> (algorithm: CompressionAlgorithm, level: Int) {
        let algorithm = options["algo"].flatMap(CompressionAlgorithm.init(rawValue:)) ?? defaultAlgorithm
        let level = options["level"].flatMap(Int.init) ?? algorithm.defaultLevel
        return (algorithm, level)
    }
}
