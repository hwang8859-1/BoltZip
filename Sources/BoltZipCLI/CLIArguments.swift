import BoltZipCore
import Foundation

struct CLIArguments {
    let positional: [String]
    let options: [String: String]
    let flags: Set<String>

    var useJSON: Bool { flags.contains("json") }
    var password: String? { options["password"] }
    var encoding: FilenameEncodingOption {
        options["encoding"].flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto
    }
    var stripMacJunk: Bool { !flags.contains("keep-junk") }
    var restoreSymlinks: Bool { !flags.contains("no-symlinks") }
    var encryption: EncryptionMethod {
        password == nil ? .none : (flags.contains("zipcrypto") ? .zipCrypto : .aes256)
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
            "aes256", "zipcrypto", "keep-junk", "no-symlinks",
            "status", "restore", "include-iso", "json", "quiet"
        ]

        var positional: [String] = []
        var options: [String: String] = [:]
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
                    options[key] = args[i + 1]
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
