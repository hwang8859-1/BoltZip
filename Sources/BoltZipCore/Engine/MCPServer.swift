import Foundation

public enum MCPServer {
    public static let serverName = "boltzip-mcp"
    public static let protocolVersion = "2024-11-05"

    public static func run() async -> Int32 {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let response = await handleMessage(rawJSON: trimmed) {
                print(response)
                fflush(stdout)
            }
        }
        return 0
    }

    public static func handleMessage(rawJSON: String) async -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return formatErrorResponse(id: nil, code: -32700, message: "Parse error: Invalid JSON")
        }

        let id = json["id"]
        guard let method = json["method"] as? String else {
            return formatErrorResponse(id: id, code: -32600, message: "Invalid Request: Missing method")
        }

        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return formatInitializeResponse(id: id)
        case "notifications/initialized":
            return nil
        case "ping":
            return formatResultResponse(id: id, result: [String: Any]())
        case "tools/list":
            return formatResultResponse(id: id, result: ["tools": makeToolsList()])
        case "tools/call":
            return await handleToolCall(id: id, params: params)
        default:
            if id != nil {
                return formatErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
            }
            return nil
        }
    }

    private static func formatInitializeResponse(id: Any?) -> String? {
        let result: [String: Any] = [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": [String: Any]()
            ],
            "serverInfo": [
                "name": serverName,
                "version": BoltZipVersion.current
            ]
        ]
        return formatResultResponse(id: id, result: result)
    }

    private static func handleToolCall(id: Any?, params: [String: Any]) async -> String? {
        guard let name = params["name"] as? String else {
            return formatErrorResponse(id: id, code: -32602, message: "Missing tool name in tools/call")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        do {
            let toolResult: [String: Any]
            switch name {
            case "boltzip_compress":
                toolResult = try executeCompress(args)
            case "boltzip_extract":
                toolResult = try executeExtract(args)
            case "boltzip_list":
                toolResult = try executeList(args)
            case "boltzip_test":
                toolResult = try executeTest(args)
            case "boltzip_batch_compress":
                toolResult = try executeBatchCompress(args)
            case "boltzip_batch_extract":
                toolResult = try executeBatchExtract(args)
            case "boltzip_recover_zip":
                toolResult = try executeRecoverZip(args)
            default:
                return formatErrorResponse(id: id, code: -32601, message: "Unknown tool: \(name)")
            }

            let jsonText = try formatJSON(toolResult)
            let result: [String: Any] = [
                "content": [
                    [
                        "type": "text",
                        "text": jsonText
                    ]
                ],
                "isError": false
            ]
            return formatResultResponse(id: id, result: result)
        } catch {
            let errorResult: [String: Any] = [
                "content": [
                    [
                        "type": "text",
                        "text": "Error: \(error.localizedDescription)"
                    ]
                ],
                "isError": true
            ]
            return formatResultResponse(id: id, result: errorResult)
        }
    }

    // MARK: - Tool Implementations

    private static func executeCompress(_ args: [String: Any]) throws -> [String: Any] {
        guard let inputPaths = args["inputs"] as? [String], !inputPaths.isEmpty else {
            throw BoltZipError.ioError("Missing or empty 'inputs' array")
        }
        guard let outputPath = args["output"] as? String, !outputPath.isEmpty else {
            throw BoltZipError.ioError("Missing 'output' path")
        }

        let inputURLs = inputPaths.map { URL(fileURLWithPath: $0) }
        let targetArg = URL(fileURLWithPath: outputPath)

        let fmt: ArchiveFormat
        if let explicitFmt = (args["format"] as? String).flatMap(ArchiveFormat.parse) {
            fmt = explicitFmt
        } else if let detected = ArchiveFormat.detect(from: targetArg) {
            fmt = detected
        } else {
            fmt = .zip
        }

        let targetIsDir = (try? targetArg.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let resolvedOutURL: URL
        if targetIsDir {
            let baseStem = BoltArchiveEngine.defaultBaseStem(for: inputURLs, format: fmt)
            resolvedOutURL = BoltArchiveEngine.makeOutputURL(stem: baseStem, format: fmt, in: targetArg, deduplicating: true)
        } else {
            resolvedOutURL = targetArg
        }

        let algoName = args["algorithm"] as? String
        let algorithm = algoName.flatMap(CompressionAlgorithm.init(rawValue:)) ?? fmt.defaultAlgorithm
        let level = (args["level"] as? Int) ?? algorithm.defaultLevel
        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        let encryptNames = (args["encrypt_filenames"] as? Bool) ?? false
        let excludeMacJunk = (args["exclude_mac_junk"] as? Bool) ?? true
        let preserveSymlinks = (args["preserve_symlinks"] as? Bool) ?? true
        let splitMB = args["split_mb"] as? Int
        let splitBytes = splitMB.flatMap { $0 > 0 ? UInt64($0) * 1024 * 1024 : nil }
        let excludes = (args["exclude"] as? [String]) ?? []

        let encryption: EncryptionMethod
        if effectivePassword != nil {
            encryption = .aes256
        } else {
            encryption = .none
        }

        let opts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: effectivePassword,
            splitVolumeSizeBytes: splitBytes,
            excludeMacJunk: excludeMacJunk,
            excludePatterns: excludes,
            preserveSymlinks: preserveSymlinks,
            encryptFileNames: encryptNames
        )

        let createdURLs = try BoltArchiveEngine.createArchive(from: inputURLs, to: resolvedOutURL, options: opts)
        var totalBytes: UInt64 = 0
        for url in createdURLs {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                totalBytes += size
            }
        }

        return [
            "success": true,
            "createdArchives": createdURLs.map(\.path),
            "format": fmt.rawValue,
            "algorithm": algorithm.rawValue,
            "level": level,
            "totalSizeBytes": totalBytes,
            "inputCount": inputURLs.count
        ]
    }

    private static func executeExtract(_ args: [String: Any]) throws -> [String: Any] {
        guard let archivePath = args["archive"] as? String, !archivePath.isEmpty else {
            throw BoltZipError.ioError("Missing 'archive' path")
        }
        let archiveURL = URL(fileURLWithPath: archivePath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw BoltZipError.ioError("File not found at path: \(archiveURL.path)")
        }

        let destinationURL: URL
        if let destStr = args["destination"] as? String, !destStr.isEmpty {
            destinationURL = URL(fileURLWithPath: destStr)
        } else {
            destinationURL = archiveURL.deletingLastPathComponent()
        }

        let modeStr = (args["mode"] as? String)?.lowercased()
        let mode: ExtractMode
        switch modeStr {
        case "here": mode = .here
        case "subfolder": mode = .subfolder
        default: mode = .smart
        }

        let overwriteStr = (args["overwrite"] as? String)?.lowercased()
        let overwrite: OverwritePolicy
        switch overwriteStr {
        case "skip": overwrite = .skip
        case "rename": overwrite = .rename
        default: overwrite = .overwrite
        }

        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        let stripMacJunk = (args["strip_mac_junk"] as? Bool) ?? true
        let encodingStr = (args["encoding"] as? String)
        let encoding = encodingStr.flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto

        let opts = ExtractOptions(
            destinationURL: destinationURL,
            mode: mode,
            overwritePolicy: overwrite,
            password: effectivePassword,
            encoding: encoding,
            stripMacJunk: stripMacJunk
        )

        let outURL = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts)
        return [
            "success": true,
            "archive": archiveURL.path,
            "extractedTo": outURL.path,
            "mode": modeStr ?? "smart"
        ]
    }

    private static func executeList(_ args: [String: Any]) throws -> [String: Any] {
        guard let archivePath = args["archive"] as? String, !archivePath.isEmpty else {
            throw BoltZipError.ioError("Missing 'archive' path")
        }
        let archiveURL = URL(fileURLWithPath: archivePath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw BoltZipError.ioError("File not found at path: \(archiveURL.path)")
        }

        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        let encoding = (args["encoding"] as? String).flatMap(FilenameEncodingOption.init(rawValue:)) ?? .auto

        let listing = try BoltArchiveEngine.inspect(archiveURL: archiveURL, encoding: encoding, password: effectivePassword)

        let isoDateFormatter = ISO8601DateFormatter()
        let entryItems = listing.entries.map { entry -> [String: Any] in
            [
                "path": entry.path,
                "isDirectory": entry.isDirectory,
                "uncompressedSize": entry.uncompressedSize,
                "compressedSize": entry.compressedSize,
                "compressionMethod": entry.compressionMethodName,
                "isEncrypted": entry.isEncrypted,
                "modifiedDate": isoDateFormatter.string(from: entry.modifiedDate)
            ]
        }

        return [
            "archive": archiveURL.path,
            "format": listing.format.rawValue,
            "totalEntries": listing.entries.count,
            "totalUncompressedBytes": listing.totalUncompressedBytes,
            "totalCompressedBytes": listing.totalCompressedBytes,
            "archiveFileSize": listing.archiveFileSize,
            "isSplitVolume": listing.isSplitVolume,
            "comment": listing.comment,
            "entries": entryItems
        ]
    }

    private static func executeTest(_ args: [String: Any]) throws -> [String: Any] {
        guard let archivePath = args["archive"] as? String, !archivePath.isEmpty else {
            throw BoltZipError.ioError("Missing 'archive' path")
        }
        let archiveURL = URL(fileURLWithPath: archivePath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw BoltZipError.ioError("File not found at path: \(archiveURL.path)")
        }

        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: archiveURL, password: effectivePassword)

        let failedEntries = report.results.filter { $0.status != .passed }.map { entry -> [String: Any] in
            [
                "path": entry.path,
                "status": entry.status.rawValue,
                "detail": entry.detail
            ]
        }

        return [
            "archive": archiveURL.path,
            "isHealthy": report.isHealthy,
            "totalEntries": report.totalEntries,
            "passedCount": report.passedCount,
            "failedCount": report.failedCount,
            "skippedEncryptedCount": report.skippedEncryptedCount,
            "elapsedSeconds": report.elapsedSeconds,
            "failedEntries": failedEntries
        ]
    }

    private static func executeBatchCompress(_ args: [String: Any]) throws -> [String: Any] {
        guard let itemPaths = args["items"] as? [String], !itemPaths.isEmpty else {
            throw BoltZipError.ioError("Missing or empty 'items' array")
        }
        guard let outDirStr = args["output_directory"] as? String, !outDirStr.isEmpty else {
            throw BoltZipError.ioError("Missing 'output_directory' path")
        }

        let outDir = URL(fileURLWithPath: outDirStr)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let fmt: ArchiveFormat
        if let explicitFmt = (args["format"] as? String).flatMap(ArchiveFormat.parse) {
            fmt = explicitFmt
        } else {
            fmt = .zip
        }

        let algoName = args["algorithm"] as? String
        let algorithm = algoName.flatMap(CompressionAlgorithm.init(rawValue:)) ?? fmt.defaultAlgorithm
        let level = (args["level"] as? Int) ?? algorithm.defaultLevel
        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        let excludeMacJunk = (args["exclude_mac_junk"] as? Bool) ?? true

        let encryption: EncryptionMethod = (effectivePassword != nil) ? .aes256 : .none
        let opts = CreateArchiveOptions(
            format: fmt,
            algorithm: algorithm,
            level: level,
            encryption: encryption,
            password: effectivePassword,
            excludeMacJunk: excludeMacJunk
        )

        var createdList: [[String: Any]] = []
        var failedList: [[String: Any]] = []

        for itemPath in itemPaths {
            let itemURL = URL(fileURLWithPath: itemPath)
            guard FileManager.default.fileExists(atPath: itemURL.path) else {
                failedList.append(["source": itemPath, "error": "File or directory not found"])
                continue
            }

            let stem = BoltArchiveEngine.defaultBaseStem(for: [itemURL], format: fmt)
            let targetURL = BoltArchiveEngine.makeOutputURL(stem: stem, format: fmt, in: outDir, deduplicating: true)

            do {
                let createdURLs = try BoltArchiveEngine.createArchive(from: [itemURL], to: targetURL, options: opts)
                var totalBytes: UInt64 = 0
                for u in createdURLs {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
                       let size = attrs[.size] as? UInt64 {
                        totalBytes += size
                    }
                }
                createdList.append([
                    "source": itemPath,
                    "archives": createdURLs.map(\.path),
                    "totalSizeBytes": totalBytes
                ])
            } catch {
                failedList.append(["source": itemPath, "error": error.localizedDescription])
            }
        }

        return [
            "totalItems": itemPaths.count,
            "succeededCount": createdList.count,
            "failedCount": failedList.count,
            "created": createdList,
            "failed": failedList
        ]
    }

    private static func executeBatchExtract(_ args: [String: Any]) throws -> [String: Any] {
        guard let archivePaths = args["archives"] as? [String], !archivePaths.isEmpty else {
            throw BoltZipError.ioError("Missing or empty 'archives' array")
        }
        guard let destDirStr = args["destination_directory"] as? String, !destDirStr.isEmpty else {
            throw BoltZipError.ioError("Missing 'destination_directory' path")
        }

        let destDir = URL(fileURLWithPath: destDirStr)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let modeStr = (args["mode"] as? String)?.lowercased()
        let mode: ExtractMode
        switch modeStr {
        case "here": mode = .here
        case "subfolder": mode = .subfolder
        default: mode = .smart
        }

        let overwriteStr = (args["overwrite"] as? String)?.lowercased()
        let overwrite: OverwritePolicy
        switch overwriteStr {
        case "skip": overwrite = .skip
        case "rename": overwrite = .rename
        default: overwrite = .overwrite
        }

        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil
        let stripMacJunk = (args["strip_mac_junk"] as? Bool) ?? true

        let opts = ExtractOptions(
            destinationURL: destDir,
            mode: mode,
            overwritePolicy: overwrite,
            password: effectivePassword,
            stripMacJunk: stripMacJunk
        )

        var extractedList: [[String: Any]] = []
        var failedList: [[String: Any]] = []

        for archivePath in archivePaths {
            let archiveURL = URL(fileURLWithPath: archivePath)
            guard FileManager.default.fileExists(atPath: archiveURL.path) else {
                failedList.append(["archive": archivePath, "error": "Archive file not found"])
                continue
            }

            do {
                let outURL = try BoltArchiveEngine.extract(archiveURL: archiveURL, options: opts)
                extractedList.append([
                    "archive": archivePath,
                    "extractedTo": outURL.path
                ])
            } catch {
                failedList.append(["archive": archivePath, "error": error.localizedDescription])
            }
        }

        return [
            "totalArchives": archivePaths.count,
            "succeededCount": extractedList.count,
            "failedCount": failedList.count,
            "extracted": extractedList,
            "failed": failedList
        ]
    }

    private static func executeRecoverZip(_ args: [String: Any]) throws -> [String: Any] {
        guard let damagedPath = args["damaged_archive"] as? String, !damagedPath.isEmpty else {
            throw BoltZipError.ioError("Missing 'damaged_archive' path")
        }
        guard let outputPath = args["output"] as? String, !outputPath.isEmpty else {
            throw BoltZipError.ioError("Missing 'output' path")
        }

        let damagedURL = URL(fileURLWithPath: damagedPath)
        guard FileManager.default.fileExists(atPath: damagedURL.path) else {
            throw BoltZipError.ioError("File not found at path: \(damagedURL.path)")
        }
        let outputURL = URL(fileURLWithPath: outputPath)

        let password = (args["password"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (password?.isEmpty == false) ? password : nil

        let report = try BoltArchiveEngine.recoverZip(
            at: damagedURL,
            to: outputURL,
            password: effectivePassword,
            encoding: .auto
        )

        return [
            "source": report.sourceURL.lastPathComponent,
            "recoveredArchive": report.recoveredArchiveURL?.path as Any,
            "totalScanned": report.totalScannedCount,
            "recoveredCount": report.recoveredCount,
            "unrecoverableCount": report.unrecoverableCount,
            "usedLocalHeaderFallbackScan": report.usedLocalHeaderFallbackScan,
            "recoveredEntries": report.recoveredEntries.map(\.path),
            "unrecoverableEntries": report.unrecoverableEntries.map {
                ["entry": $0.entryPath, "reason": $0.reason]
            }
        ]
    }

    // MARK: - Tool Definitions Schema

    public static func makeToolsList() -> [[String: Any]] {
        [
            [
                "name": "boltzip_compress",
                "description": "Compress files or directories into an archive format (zip, 7z, tar, tar.gz, tar.zst, tar.xz, tar.bz2, tar.lz4, gz, xz) with optional compression level, password encryption, and split volume support.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "inputs": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of file and directory paths to compress."
                        ],
                        "output": [
                            "type": "string",
                            "description": "Destination path for the created archive file or directory."
                        ],
                        "format": [
                            "type": "string",
                            "description": "Target archive format: 'zip', '7z', 'tar', 'tar.gz', 'tar.zst', 'tar.xz', 'tar.bz2', 'tar.lz4', 'gz', 'xz'. Default is inferred from output filename."
                        ],
                        "algorithm": [
                            "type": "string",
                            "description": "Compression algorithm: 'deflate', 'zstd', 'xz', 'bzip2', 'lz4', 'store'."
                        ],
                        "level": [
                            "type": "integer",
                            "description": "Compression level (e.g. 1-9, or 1-22 for zstd)."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Optional password to encrypt the archive."
                        ],
                        "encrypt_filenames": [
                            "type": "boolean",
                            "description": "Encrypt archive file names (7z format only, default false)."
                        ],
                        "split_mb": [
                            "type": "integer",
                            "description": "Split volume size in MiB (e.g. 100 for 100MB volumes; ZIP or 7z only)."
                        ],
                        "exclude_mac_junk": [
                            "type": "boolean",
                            "description": "Exclude macOS metadata files (.DS_Store, __MACOSX; default true)."
                        ],
                        "exclude": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Exclude glob patterns (e.g. ['*.log', '.git/*'])."
                        ]
                    ],
                    "required": ["inputs", "output"]
                ]
            ],
            [
                "name": "boltzip_extract",
                "description": "Extract an archive file to a destination directory with support for passwords, overwrite policy, encoding, and junk stripping.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "archive": [
                            "type": "string",
                            "description": "Path to the archive file to extract."
                        ],
                        "destination": [
                            "type": "string",
                            "description": "Destination directory path. If omitted, extracts next to the archive."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Password if the archive is encrypted."
                        ],
                        "mode": [
                            "type": "string",
                            "enum": ["smart", "here", "subfolder"],
                            "description": "Extraction folder layout: 'smart' (auto subfolder if multi-root, default), 'here' (extract directly into destination), 'subfolder' (always create a dedicated folder)."
                        ],
                        "overwrite": [
                            "type": "string",
                            "enum": ["overwrite", "skip", "rename"],
                            "description": "File collision policy: 'overwrite' (default), 'skip', or 'rename'."
                        ],
                        "strip_mac_junk": [
                            "type": "boolean",
                            "description": "Strip macOS metadata files like .DS_Store and __MACOSX (default true)."
                        ],
                        "encoding": [
                            "type": "string",
                            "description": "Filename character encoding: 'auto' (default), 'utf8', 'gb18030', 'big5', 'shiftjis', 'euckr', 'cp437'."
                        ]
                    ],
                    "required": ["archive"]
                ]
            ],
            [
                "name": "boltzip_list",
                "description": "Inspect and list entries in an archive, showing paths, uncompressed/compressed sizes, directory flags, encryption status, and archive format.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "archive": [
                            "type": "string",
                            "description": "Path to the archive file to inspect."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Password for password-protected headers or encrypted archives."
                        ],
                        "encoding": [
                            "type": "string",
                            "description": "Filename character encoding: 'auto' (default), 'utf8', 'gb18030', etc."
                        ]
                    ],
                    "required": ["archive"]
                ]
            ],
            [
                "name": "boltzip_test",
                "description": "Verify the integrity of an archive without writing extracted files to disk.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "archive": [
                            "type": "string",
                            "description": "Path to the archive file to test."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Password if archive payload is encrypted."
                        ]
                    ],
                    "required": ["archive"]
                ]
            ],
            [
                "name": "boltzip_batch_compress",
                "description": "Batch compress multiple files or directories into individual archives in an output directory.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "items": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of file or folder paths to each be compressed into an individual archive."
                        ],
                        "output_directory": [
                            "type": "string",
                            "description": "Destination directory where generated archives will be placed."
                        ],
                        "format": [
                            "type": "string",
                            "description": "Format for created archives: 'zip' (default), '7z', 'tar.gz', 'tar.zst', 'tar.xz', etc."
                        ],
                        "algorithm": [
                            "type": "string",
                            "description": "Compression algorithm: 'deflate', 'zstd', 'xz', 'bzip2', 'lz4', 'store'."
                        ],
                        "level": [
                            "type": "integer",
                            "description": "Compression level."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Optional password for all created archives."
                        ],
                        "exclude_mac_junk": [
                            "type": "boolean",
                            "description": "Exclude macOS metadata files (default true)."
                        ]
                    ],
                    "required": ["items", "output_directory"]
                ]
            ],
            [
                "name": "boltzip_batch_extract",
                "description": "Batch extract multiple archive files into a destination directory.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "archives": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of archive file paths to extract."
                        ],
                        "destination_directory": [
                            "type": "string",
                            "description": "Destination directory where extracted items will be placed."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Optional password for encrypted archives."
                        ],
                        "mode": [
                            "type": "string",
                            "enum": ["smart", "subfolder", "here"],
                            "description": "Extraction folder mode for each archive ('smart' default)."
                        ],
                        "overwrite": [
                            "type": "string",
                            "enum": ["overwrite", "skip", "rename"],
                            "description": "File collision policy ('overwrite' default)."
                        ],
                        "strip_mac_junk": [
                            "type": "boolean",
                            "description": "Strip macOS junk files (default true)."
                        ]
                    ],
                    "required": ["archives", "destination_directory"]
                ]
            ],
            [
                "name": "boltzip_recover_zip",
                "description": "Salvage files from damaged or corrupted ZIP files via raw Local File Header scanning.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "damaged_archive": [
                            "type": "string",
                            "description": "Path to the damaged ZIP file."
                        ],
                        "output": [
                            "type": "string",
                            "description": "Path to write the recovered ZIP file."
                        ],
                        "password": [
                            "type": "string",
                            "description": "Password if encrypted."
                        ]
                    ],
                    "required": ["damaged_archive", "output"]
                ]
            ]
        ]
    }

    // MARK: - JSON-RPC Transport Helpers

    private static func formatResultResponse(id: Any?, result: Any) -> String? {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id {
            response["id"] = id
        } else {
            response["id"] = NSNull()
        }
        response["result"] = result
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func formatErrorResponse(id: Any?, code: Int, message: String) -> String? {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id {
            response["id"] = id
        } else {
            response["id"] = NSNull()
        }
        response["error"] = [
            "code": code,
            "message": message
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func formatJSON(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
