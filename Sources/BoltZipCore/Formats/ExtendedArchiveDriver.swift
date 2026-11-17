import Foundation

public enum ExtendedArchiveDriver {
    public static func listEntries(
        at url: URL,
        format: ArchiveFormat,
        encoding: FilenameEncodingOption = .auto
    ) throws -> [ArchiveEntry] {
        let pathsOutput = try runTar(arguments: ["-tf", url.path])
        let verboseOutput = try runTar(arguments: ["-tvf", url.path])

        let rawPaths = pathsOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let verboseLines = verboseOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        var entries: [ArchiveEntry] = []
        entries.reserveCapacity(rawPaths.count)

        for (idx, rawPath) in rawPaths.enumerated() {
            let vLine = idx < verboseLines.count ? verboseLines[idx] : ""
            var isDir = rawPath.hasSuffix("/")
            var size: UInt64 = 0
            if !vLine.isEmpty {
                if vLine.hasPrefix("d") { isDir = true }
                // Strip the known path suffix to isolate permission/owner/size/date columns safely
                let prefixPart: String
                if vLine.hasSuffix(rawPath) {
                    prefixPart = String(vLine.dropLast(rawPath.count))
                } else {
                    prefixPart = vLine
                }
                let tokens = prefixPart.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                // bsdtar -tvf columns: perms links owner group size month day time_or_year
                if tokens.count >= 5, let parsedSize = UInt64(tokens[4]) {
                    size = parsedSize
                }
            }

            let decodedPath = unescapeBsdtarPath(rawPath, encoding: encoding)
            entries.append(
                ArchiveEntry(
                    path: decodedPath,
                    isDirectory: isDir,
                    uncompressedSize: isDir ? 0 : size,
                    compressedSize: 0,
                    compressionMethodName: format == .sevenZip ? "LZMA (libarchive)" : format.fileExtension.uppercased(),
                    crc32: 0,
                    modifiedDate: Date()
                )
            )
        }
        return entries
    }

    public static func readEntryData(at url: URL, path: String) throws -> Data {
        let target = ArchiveEntry.normalizePath(path, isDirectory: false)
        return try runTarData(arguments: ["-xOf", url.path, target])
    }

    public static func extract(
        at url: URL,
        to destinationURL: URL,
        selectedPaths: Set<String>? = nil,
        stripMacJunk: Bool = true
    ) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        var args: [String] = []
        if stripMacJunk {
            for pattern in [".DS_Store", "*/.DS_Store", "__MACOSX", "*/__MACOSX", "._*", "*/._*"] {
                args.append(contentsOf: ["--exclude", pattern])
            }
        }
        args.append(contentsOf: ["-xf", url.path, "-C", destinationURL.path])
        if let selectedPaths, !selectedPaths.isEmpty {
            args.append(contentsOf: selectedPaths.sorted())
        }
        _ = try runTar(arguments: args)
    }

    public static func create7z(
        from inputURLs: [URL],
        to outputURL: URL,
        excludeMacJunk: Bool
    ) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("BoltZipStage-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let items = try ZipWriter.collectInputItems(from: inputURLs, excludeMacJunk: excludeMacJunk)
        var topLevelNames: [String] = []
        var seenTop: Set<String> = []

        for item in items {
            let clean = item.archivePath.hasSuffix("/") ? String(item.archivePath.dropLast()) : item.archivePath
            let dest = staging.appendingPathComponent(clean)
            if item.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if let src = item.fileURL {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dest)
            }
            if let first = clean.split(separator: "/").first.map(String.init), !seenTop.contains(first) {
                seenTop.insert(first)
                topLevelNames.append(first)
            }
        }

        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        var args = ["--format=7zip", "-cf", outputURL.path, "-C", staging.path]
        args.append(contentsOf: topLevelNames.isEmpty ? ["."] : topLevelNames)
        _ = try runTar(arguments: args)
    }

    /// Decodes `bsdtar` `safe_fprintf` octal escapes (`\350\213\217`) back into UTF-8/CJK paths.
    static func unescapeBsdtarPath(_ raw: String, encoding: FilenameEncodingOption = .auto) -> String {
        guard raw.contains("\\") else { return raw }

        let bytes = Array(raw.utf8)
        let isOctalDigit: (UInt8) -> Bool = { $0 >= 0x30 && $0 <= 0x37 } // '0'...'7'

        // Only treat backslash sequences as bsdtar escapes if at least one \OOO octal byte sequence appears.
        var hasOctalEscape = false
        var scanIdx = 0
        while scanIdx + 3 < bytes.count {
            if bytes[scanIdx] == 0x5C,
               isOctalDigit(bytes[scanIdx + 1]),
               isOctalDigit(bytes[scanIdx + 2]),
               isOctalDigit(bytes[scanIdx + 3]) {
                let value = (Int(bytes[scanIdx + 1] - 0x30) << 6)
                    | (Int(bytes[scanIdx + 2] - 0x30) << 3)
                    | Int(bytes[scanIdx + 3] - 0x30)
                if value <= 255 {
                    hasOctalEscape = true
                    break
                }
            }
            scanIdx += 1
        }
        guard hasOctalEscape else { return raw }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x5C {
                if i + 3 < bytes.count,
                   isOctalDigit(bytes[i + 1]),
                   isOctalDigit(bytes[i + 2]),
                   isOctalDigit(bytes[i + 3]) {
                    let value = (Int(bytes[i + 1] - 0x30) << 6)
                        | (Int(bytes[i + 2] - 0x30) << 3)
                        | Int(bytes[i + 3] - 0x30)
                    if value <= 255 {
                        decoded.append(UInt8(value))
                        i += 4
                        continue
                    }
                }
                if i + 1 < bytes.count {
                    switch bytes[i + 1] {
                    case 0x5C: decoded.append(0x5C); i += 2; continue // '\\'
                    case 0x61: decoded.append(0x07); i += 2; continue // '\a'
                    case 0x62: decoded.append(0x08); i += 2; continue // '\b'
                    case 0x66: decoded.append(0x0C); i += 2; continue // '\f'
                    case 0x6E: decoded.append(0x0A); i += 2; continue // '\n'
                    case 0x72: decoded.append(0x0D); i += 2; continue // '\r'
                    case 0x74: decoded.append(0x09); i += 2; continue // '\t'
                    case 0x76: decoded.append(0x0B); i += 2; continue // '\v'
                    default: break
                    }
                }
            }
            decoded.append(bytes[i])
            i += 1
        }

        if let utf8 = String(bytes: decoded, encoding: .utf8) {
            return utf8
        }
        return FilenameEncoding.decode(Data(decoded), hasUTF8Flag: false, preferred: encoding)
    }

    private static func runTar(arguments: [String]) throws -> String {
        let data = try runTarData(arguments: arguments)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func runTarData(arguments: [String]) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = arguments
        // GUI macOS apps launch without LANG/LC_CTYPE, causing bsdtar to octal-escape UTF-8 paths as \350\213\217...
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_CTYPE"] = "UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tar failed"
            throw BoltZipError.externalToolFailed(errMsg.isEmpty ? "归档处理失败 (code \(proc.terminationStatus))" : errMsg)
        }
        return outData
    }
}
