import Foundation

public enum ExtendedArchiveDriver {
    public static func listEntries(at url: URL, format: ArchiveFormat) throws -> [ArchiveEntry] {
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

            entries.append(
                ArchiveEntry(
                    path: rawPath,
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
        selectedPaths: Set<String>? = nil
    ) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        var args = ["-xf", url.path, "-C", destinationURL.path]
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

    private static func runTar(arguments: [String]) throws -> String {
        let data = try runTarData(arguments: arguments)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func runTarData(arguments: [String]) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = arguments

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
