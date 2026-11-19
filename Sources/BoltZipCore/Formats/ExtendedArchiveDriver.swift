import CBoltCompression
import Foundation

public enum ExtendedArchiveDriver {
    public static func resolveVolumePaths(for url: URL, format: ArchiveFormat) -> [String] {
        guard format == .rar else { return [url.path] }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        let lower = fileName.lowercased()

        // Modern multi-volume RAR: archive.part1.rar, archive.part2.rar, ...
        if lower.hasSuffix(".rar"),
           let range = fileName.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            let stemPrefix = String(fileName[..<range.lowerBound])
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let matched: [(Int, String)] = contents.compactMap { candidate in
                    let cname = candidate.lastPathComponent
                    guard let cr = cname.range(of: #"\.part(\d+)\.rar$"#, options: [.regularExpression, .caseInsensitive]) else {
                        return nil
                    }
                    guard String(cname[..<cr.lowerBound]).caseInsensitiveCompare(stemPrefix) == .orderedSame else {
                        return nil
                    }
                    let tail = cname[cr]
                    let digits = tail.dropFirst(5).dropLast(4)
                    guard let num = Int(digits) else { return nil }
                    return (num, candidate.path)
                }.sorted { $0.0 < $1.0 }
                if !matched.isEmpty {
                    return matched.map(\.1)
                }
            }
        }

        // Legacy multi-volume RAR: archive.rar, archive.r00, archive.r01, ...
        let ext = url.pathExtension.lowercased()
        let isLegacySplitPart = (ext.count == 3 && ext.hasPrefix("r") && Int(ext.dropFirst()) != nil)
        if ext == "rar" || isLegacySplitPart {
            let stemURL = url.deletingPathExtension()
            let primaryURL = stemURL.appendingPathExtension("rar")
            if fm.fileExists(atPath: primaryURL.path) {
                var volumes = [primaryURL.path]
                for idx in 0...99 {
                    let partExt = String(format: "r%02d", idx)
                    let partURL = stemURL.appendingPathExtension(partExt)
                    guard fm.fileExists(atPath: partURL.path) else { break }
                    volumes.append(partURL.path)
                }
                if volumes.count > 1 {
                    return volumes
                }
            }
        }

        return [url.path]
    }

    public static func listEntries(
        at url: URL,
        format: ArchiveFormat,
        encoding: FilenameEncodingOption = .auto,
        password: String? = nil
    ) throws -> [ArchiveEntry] {
        final class ListState {
            let format: ArchiveFormat
            let encoding: FilenameEncodingOption
            var entries: [ArchiveEntry] = []

            init(format: ArchiveFormat, encoding: FilenameEncodingOption) {
                self.format = format
                self.encoding = encoding
            }
        }

        let state = ListState(format: format, encoding: encoding)
        let volumePaths = resolveVolumePaths(for: url, format: format)
        var errBuf = [CChar](repeating: 0, count: 512)

        let rc: Int32 = withCStringArray(volumePaths) { cPaths, count in
            withExtendedLifetime(state) {
                let rawCtx = Unmanaged.passUnretained(state).toOpaque()
                return withOptionalCString(password) { cPw in
                    bolt_la_list(
                        cPaths,
                        count,
                        cPw,
                        { infoPtr, rawCtx in
                            guard let infoPtr, let rawCtx else { return 0 }
                            let st = Unmanaged<ListState>.fromOpaque(rawCtx).takeUnretainedValue()
                            let info = infoPtr.pointee
                            let rawBytes: Data
                            if let ptr = info.raw_path_bytes, info.raw_path_len > 0 {
                                rawBytes = Data(bytes: ptr, count: info.raw_path_len)
                            } else if let p = info.path {
                                rawBytes = Data(String(cString: p).utf8)
                            } else {
                                return 0
                            }
                            let isUTF8 = info.path_is_utf8 != 0
                            let decodedPath = FilenameEncoding.decode(rawBytes, hasUTF8Flag: isUTF8, preferred: st.encoding)
                            let isDir = info.is_directory != 0
                            let normalized = ArchiveEntry.normalizePath(decodedPath, isDirectory: isDir)
                            guard !normalized.isEmpty else { return 0 }

                            let isSymlink = info.is_symlink != 0
                            let isEnc = info.is_encrypted != 0
                            let modDate = info.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(info.mtime)) : Date()
                            let fmtName: String
                            if st.format == .rar {
                                fmtName = info.format_name.map { String(cString: $0) } ?? "RAR"
                            } else if st.format == .sevenZip {
                                fmtName = "LZMA (libarchive)"
                            } else {
                                fmtName = st.format.fileExtension.uppercased()
                            }

                            st.entries.append(
                                ArchiveEntry(
                                    path: normalized,
                                    isDirectory: isDir,
                                    isSymbolicLink: isSymlink,
                                    uncompressedSize: isDir ? 0 : info.size,
                                    compressedSize: 0,
                                    compressionMethodName: fmtName,
                                    crc32: 0,
                                    modifiedDate: modDate,
                                    permissions: info.permissions,
                                    isEncrypted: isEnc,
                                    encryptionLabel: isEnc ? (st.format == .rar ? "RAR AES" : "AES-256") : "",
                                    rawPathBytes: rawBytes,
                                    hasUTF8Flag: isUTF8
                                )
                            )
                            return 0
                        },
                        rawCtx,
                        &errBuf,
                        errBuf.count
                    )
                }
            }
        }

        try throwIfLibarchiveError(rc, errBuf: errBuf, contextName: url.lastPathComponent)
        return state.entries
    }

    public static func readEntryData(
        at url: URL,
        format: ArchiveFormat? = nil,
        path: String,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto
    ) throws -> Data {
        final class ReadState {
            let targetPath: String
            let encoding: FilenameEncodingOption
            var matched = false
            var data = Data()

            init(targetPath: String, encoding: FilenameEncodingOption) {
                self.targetPath = ArchiveEntry.normalizePath(targetPath, isDirectory: false)
                self.encoding = encoding
            }
        }

        let resolvedFormat = format ?? ArchiveFormat.detect(from: url) ?? .sevenZip
        let state = ReadState(targetPath: path, encoding: encoding)
        let volumePaths = resolveVolumePaths(for: url, format: resolvedFormat)
        var errBuf = [CChar](repeating: 0, count: 512)

        let rc: Int32 = withCStringArray(volumePaths) { cPaths, count in
            withExtendedLifetime(state) {
                let rawCtx = Unmanaged.passUnretained(state).toOpaque()
                return withOptionalCString(password) { cPw in
                    bolt_la_extract_stream(
                        cPaths,
                        count,
                        cPw,
                        { infoPtr, rawCtx in
                            guard let infoPtr, let rawCtx else { return 0 }
                            let st = Unmanaged<ReadState>.fromOpaque(rawCtx).takeUnretainedValue()
                            let info = infoPtr.pointee
                            let rawBytes = Self.extractRawPathData(from: info)
                            let decoded = FilenameEncoding.decode(rawBytes, hasUTF8Flag: info.path_is_utf8 != 0, preferred: st.encoding)
                            let normalized = ArchiveEntry.normalizePath(decoded, isDirectory: info.is_directory != 0)
                            if normalized == st.targetPath {
                                st.matched = true
                                if info.size > 0 && info.size < 32 * 1024 * 1024 {
                                    st.data.reserveCapacity(Int(info.size))
                                }
                                return 1
                            }
                            return 0
                        },
                        { chunkPtr, chunkLen, rawCtx in
                            guard let rawCtx else { return -1 }
                            let st = Unmanaged<ReadState>.fromOpaque(rawCtx).takeUnretainedValue()
                            if let chunkPtr, chunkLen > 0 {
                                st.data.append(chunkPtr, count: chunkLen)
                                return 0
                            }
                            return 1 // End of matched entry: stop scanning archive early
                        },
                        rawCtx,
                        &errBuf,
                        errBuf.count
                    )
                }
            }
        }

        try throwIfLibarchiveError(rc, errBuf: errBuf, contextName: path)
        guard state.matched else {
            throw BoltZipError.entryNotFound(path)
        }
        return state.data
    }

    public static func extract(
        at url: URL,
        format: ArchiveFormat? = nil,
        to destinationURL: URL,
        selectedPaths: Set<String>? = nil,
        overwritePolicy: OverwritePolicy = .overwrite,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        stripMacJunk: Bool = true,
        restoreSymlinks: Bool = true,
        expectedTotalBytes: UInt64 = 0,
        topLevelDirRenameMap: [String: String] = [:],
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let fm = FileManager.default
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        final class ExtractState {
            let destinationURL: URL
            let selectedPaths: Set<String>?
            let overwritePolicy: OverwritePolicy
            let encoding: FilenameEncodingOption
            let stripMacJunk: Bool
            let restoreSymlinks: Bool
            let expectedTotalBytes: UInt64
            let renameMap: [String: String]
            let controller: ArchiveTaskController?
            let progress: (@Sendable (OperationProgress) -> Void)?

            var activeTargetURL: URL?
            var activeFileHandle: FileHandle?
            var activeModDate: Date = Date()
            var activePermissions: UInt16 = 0o644
            var activeEntryCreated = false
            var activePathName: String = ""
            var processedBytes: UInt64 = 0
            var lastProgressEmitTime: CFAbsoluteTime = 0
            var thrownError: Error?

            init(
                destinationURL: URL,
                selectedPaths: Set<String>?,
                overwritePolicy: OverwritePolicy,
                encoding: FilenameEncodingOption,
                stripMacJunk: Bool,
                restoreSymlinks: Bool,
                expectedTotalBytes: UInt64,
                renameMap: [String: String],
                controller: ArchiveTaskController?,
                progress: (@Sendable (OperationProgress) -> Void)?
            ) {
                self.destinationURL = destinationURL
                self.selectedPaths = selectedPaths
                self.overwritePolicy = overwritePolicy
                self.encoding = encoding
                self.stripMacJunk = stripMacJunk
                self.restoreSymlinks = restoreSymlinks
                self.expectedTotalBytes = expectedTotalBytes
                self.renameMap = renameMap
                self.controller = controller
                self.progress = progress
            }

            func cleanupActivePartialFile() {
                try? activeFileHandle?.close()
                activeFileHandle = nil
                if activeEntryCreated, let url = activeTargetURL {
                    try? FileManager.default.removeItem(at: url)
                }
                activeTargetURL = nil
                activeEntryCreated = false
            }
        }

        let resolvedFormat = format ?? ArchiveFormat.detect(from: url) ?? .sevenZip
        let state = ExtractState(
            destinationURL: destinationURL,
            selectedPaths: selectedPaths,
            overwritePolicy: overwritePolicy,
            encoding: encoding,
            stripMacJunk: stripMacJunk,
            restoreSymlinks: restoreSymlinks,
            expectedTotalBytes: expectedTotalBytes,
            renameMap: topLevelDirRenameMap,
            controller: controller,
            progress: progress
        )
        let volumePaths = resolveVolumePaths(for: url, format: resolvedFormat)
        var errBuf = [CChar](repeating: 0, count: 512)

        defer {
            state.cleanupActivePartialFile()
        }

        let rc: Int32 = withCStringArray(volumePaths) { cPaths, count in
            withExtendedLifetime(state) {
                let rawCtx = Unmanaged.passUnretained(state).toOpaque()
                return withOptionalCString(password) { cPw in
                    bolt_la_extract_stream(
                        cPaths,
                        count,
                        cPw,
                        { infoPtr, rawCtx in
                            guard let infoPtr, let rawCtx else { return -1 }
                            let st = Unmanaged<ExtractState>.fromOpaque(rawCtx).takeUnretainedValue()
                            do {
                                try st.controller?.checkpoint()
                                let info = infoPtr.pointee
                                let rawBytes = Self.extractRawPathData(from: info)
                                let decoded = FilenameEncoding.decode(rawBytes, hasUTF8Flag: info.path_is_utf8 != 0, preferred: st.encoding)
                                let isDir = info.is_directory != 0
                                let normalized = ArchiveEntry.normalizePath(decoded, isDirectory: isDir)
                                guard !normalized.isEmpty else { return 0 }

                                if st.stripMacJunk && MacJunkFilter.isJunk(path: normalized) {
                                    return 0
                                }
                                if let sel = st.selectedPaths, !sel.isEmpty,
                                   !BoltArchiveEngine.pathMatchesSelection(normalized, selectedPaths: sel) {
                                    return 0
                                }

                                let outputPath = BoltArchiveEngine.remapTopLevelFolder(in: normalized, renameMap: st.renameMap)
                                let initialDest = try BoltArchiveEngine.safeDestinationURL(for: outputPath, under: st.destinationURL)
                                let fm = FileManager.default

                                if isDir {
                                    try BoltArchiveEngine.assertNoSymlinkTraversal(at: initialDest, under: st.destinationURL)
                                    try fm.createDirectory(at: initialDest, withIntermediateDirectories: true)
                                    return 0
                                }
                                if info.is_symlink != 0 {
                                    if st.restoreSymlinks, let symPtr = info.symlink_target {
                                        let target = String(cString: symPtr)
                                        try BoltArchiveEngine.createSafeSymlink(
                                            at: initialDest,
                                            target: target,
                                            under: st.destinationURL,
                                            overwritePolicy: st.overwritePolicy
                                        )
                                    }
                                    return 0
                                }

                                guard let finalDest = try BoltArchiveEngine.prepareExtractTargetURL(
                                    initialURL: initialDest,
                                    under: st.destinationURL,
                                    policy: st.overwritePolicy
                                ) else {
                                    return 0
                                }
                                st.activeTargetURL = finalDest
                                st.activeFileHandle = nil
                                st.activeEntryCreated = false
                                st.activeModDate = info.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(info.mtime)) : Date()
                                st.activePermissions = info.permissions
                                st.activePathName = normalized

                                let now = CFAbsoluteTimeGetCurrent()
                                if now - st.lastProgressEmitTime >= 0.05 {
                                    st.lastProgressEmitTime = now
                                    let frac = st.expectedTotalBytes > 0
                                        ? min(0.99, Double(st.processedBytes) / Double(st.expectedTotalBytes))
                                        : 0.1
                                    st.progress?(OperationProgress(
                                        fractionCompleted: frac,
                                        currentItem: normalized,
                                        processedBytes: st.processedBytes,
                                        totalBytes: st.expectedTotalBytes
                                    ))
                                }
                                return 1
                            } catch {
                                st.thrownError = error
                                return -1
                            }
                        },
                        { chunkPtr, chunkLen, rawCtx in
                            guard let rawCtx else { return -1 }
                            let st = Unmanaged<ExtractState>.fromOpaque(rawCtx).takeUnretainedValue()
                            do {
                                try st.controller?.checkpoint()
                                guard let targetURL = st.activeTargetURL else { return -1 }
                                let fm = FileManager.default

                                if let chunkPtr, chunkLen > 0 {
                                    if st.activeFileHandle == nil {
                                        guard fm.createFile(atPath: targetURL.path, contents: nil) else {
                                            throw BoltZipError.ioError(BoltCoreLocalization.t(
                                                "无法创建解压目标文件：\(targetURL.lastPathComponent)",
                                                "無法建立解壓縮目標檔案：\(targetURL.lastPathComponent)",
                                                "Unable to create extracted file: \(targetURL.lastPathComponent)",
                                                "展開先ファイルを作成できません: \(targetURL.lastPathComponent)"
                                            ))
                                        }
                                        st.activeEntryCreated = true
                                        st.activeFileHandle = try FileHandle(forWritingTo: targetURL)
                                    }
                                    let buffer = UnsafeBufferPointer(start: chunkPtr, count: chunkLen)
                                    try st.activeFileHandle?.write(contentsOf: buffer)
                                    st.processedBytes += UInt64(chunkLen)

                                    let now = CFAbsoluteTimeGetCurrent()
                                    if now - st.lastProgressEmitTime >= 0.08 {
                                        st.lastProgressEmitTime = now
                                        let frac = st.expectedTotalBytes > 0
                                            ? min(0.99, Double(st.processedBytes) / Double(st.expectedTotalBytes))
                                            : 0.5
                                        st.progress?(OperationProgress(
                                            fractionCompleted: frac,
                                            currentItem: st.activePathName,
                                            processedBytes: st.processedBytes,
                                            totalBytes: st.expectedTotalBytes
                                        ))
                                    }
                                    return 0
                                } else {
                                    // End of entry: ensure zero-byte regular files are created, then close & set metadata
                                    if !st.activeEntryCreated {
                                        guard fm.createFile(atPath: targetURL.path, contents: nil) else {
                                            throw BoltZipError.ioError(BoltCoreLocalization.t(
                                                "无法创建解压目标文件：\(targetURL.lastPathComponent)",
                                                "無法建立解壓縮目標檔案：\(targetURL.lastPathComponent)",
                                                "Unable to create extracted file: \(targetURL.lastPathComponent)",
                                                "展開先ファイルを作成できません: \(targetURL.lastPathComponent)"
                                            ))
                                        }
                                        st.activeEntryCreated = true
                                    }
                                    try st.activeFileHandle?.close()
                                    st.activeFileHandle = nil

                                    let attrs: [FileAttributeKey: Any] = [
                                        .modificationDate: st.activeModDate,
                                        .posixPermissions: NSNumber(value: st.activePermissions)
                                    ]
                                    try? fm.setAttributes(attrs, ofItemAtPath: targetURL.path)

                                    st.activeTargetURL = nil
                                    st.activeEntryCreated = false
                                    return 0
                                }
                            } catch {
                                st.thrownError = error
                                return -1
                            }
                        },
                        rawCtx,
                        &errBuf,
                        errBuf.count
                    )
                }
            }
        }

        if let err = state.thrownError {
            throw err
        }
        try throwIfLibarchiveError(rc, errBuf: errBuf, contextName: state.activePathName.isEmpty ? url.lastPathComponent : state.activePathName)

        let doneBytes = expectedTotalBytes > 0 ? expectedTotalBytes : state.processedBytes
        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: url.lastPathComponent,
            processedBytes: doneBytes,
            totalBytes: doneBytes
        ))
    }

    public static func testIntegrity(
        at url: URL,
        format: ArchiveFormat,
        password: String? = nil
    ) throws -> IntegrityReport {
        final class TestState {
            var results: [IntegrityEntryResult] = []
            var passed = 0
            var failed = 0
            var missingPw = 0
        }

        let start = CFAbsoluteTimeGetCurrent()
        let state = TestState()
        let volumePaths = resolveVolumePaths(for: url, format: format)
        var errBuf = [CChar](repeating: 0, count: 512)

        let rc: Int32 = withCStringArray(volumePaths) { cPaths, count in
            withExtendedLifetime(state) {
                let rawCtx = Unmanaged.passUnretained(state).toOpaque()
                return withOptionalCString(password) { cPw in
                    bolt_la_test_integrity(
                        cPaths,
                        count,
                        cPw,
                        { cPath, statusCode, cDetail, rawCtx in
                            guard let rawCtx else { return }
                            let st = Unmanaged<TestState>.fromOpaque(rawCtx).takeUnretainedValue()
                            let pathStr = cPath.map { String(cString: $0) } ?? ""
                            let detailStr = cDetail.map { String(cString: $0) } ?? ""
                            if statusCode == 0 {
                                st.passed += 1
                                st.results.append(IntegrityEntryResult(
                                    path: pathStr,
                                    status: .passed,
                                    detail: BoltCoreLocalization.t("流解码与校验通过", "串流解碼與驗證通過", "Stream decode & verification passed", "ストリームデコード・検証に合格")
                                ))
                            } else if statusCode == BOLT_LA_ERR_PASSWORD_REQUIRED {
                                st.missingPw += 1
                                st.results.append(IntegrityEntryResult(
                                    path: pathStr,
                                    status: .missingPassword,
                                    detail: BoltCoreLocalization.t("需要密码", "需要密碼", "Password required", "パスワードが必要です")
                                ))
                            } else if statusCode == BOLT_LA_ERR_WRONG_PASSWORD {
                                st.failed += 1
                                st.results.append(IntegrityEntryResult(
                                    path: pathStr,
                                    status: .failed,
                                    detail: BoltCoreLocalization.t("密码错误，无法解密", "密碼錯誤，無法解密", "Incorrect password", "パスワードが正しくありません")
                                ))
                            } else {
                                st.failed += 1
                                st.results.append(IntegrityEntryResult(path: pathStr, status: .failed, detail: detailStr))
                            }
                        },
                        rawCtx,
                        &errBuf,
                        errBuf.count
                    )
                }
            }
        }

        if rc == BOLT_LA_ERR_PASSWORD_REQUIRED && state.results.isEmpty {
            return IntegrityReport(
                archiveName: url.lastPathComponent,
                totalEntries: 1,
                passedCount: 0,
                failedCount: 0,
                skippedEncryptedCount: 1,
                elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
                results: [IntegrityEntryResult(
                    path: url.lastPathComponent,
                    status: .missingPassword,
                    detail: BoltCoreLocalization.t("归档文件头已加密，需要密码", "封存檔標頭已加密，需要密碼", "Archive header is encrypted; password required", "書庫ヘッダが暗号化されています（パスワードが必要）")
                )]
            )
        }
        if rc != 0 && state.failed > 0 {
            return IntegrityReport(
                archiveName: url.lastPathComponent,
                totalEntries: state.results.count,
                passedCount: state.passed,
                failedCount: state.failed,
                skippedEncryptedCount: state.missingPw,
                elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
                results: state.results
            )
        }
        if rc != 0 {
            let errDetail = errBuf.withUnsafeBufferPointer { buf -> String in
                guard let base = buf.baseAddress else { return "" }
                return String(cString: base).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if rc == BOLT_LA_ERR_WRONG_PASSWORD {
                throw BoltZipError.wrongPassword(url.lastPathComponent)
            }
            let fallbackDetail = BoltCoreLocalization.t(
                "归档流读取或校验失败 (code \(rc))",
                "封存檔串流讀取或驗證失敗 (code \(rc))",
                "Archive stream read or verification failed (code \(rc))",
                "書庫ストリームの読み込みまたは検証に失敗しました (code \(rc))"
            )
            let detail = errDetail.isEmpty ? fallbackDetail : errDetail
            state.failed += 1
            state.results.append(IntegrityEntryResult(path: url.lastPathComponent, status: .failed, detail: detail))
            return IntegrityReport(
                archiveName: url.lastPathComponent,
                totalEntries: state.results.count,
                passedCount: state.passed,
                failedCount: state.failed,
                skippedEncryptedCount: state.missingPw,
                elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
                results: state.results
            )
        }

        return IntegrityReport(
            archiveName: url.lastPathComponent,
            totalEntries: state.results.count,
            passedCount: state.passed,
            failedCount: state.failed,
            skippedEncryptedCount: state.missingPw,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
            results: state.results
        )
    }

    public static func create7z(
        from inputURLs: [URL],
        to outputURL: URL,
        algorithm: CompressionAlgorithm = .xz,
        level: Int? = nil,
        excludeMacJunk: Bool,
        preserveSymlinks: Bool = true,
        controller: ArchiveTaskController? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws {
        try controller?.checkpoint()
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("BoltZipStage-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let items = try ZipWriter.collectInputItems(
            from: inputURLs,
            excludeMacJunk: excludeMacJunk,
            preserveSymlinks: preserveSymlinks
        )
        let totalBytes = items.reduce(UInt64(0)) { $0 + $1.fileSize }
        var stagedBytes: UInt64 = 0
        var topLevelNames: [String] = []
        var seenTop: Set<String> = []

        for item in items {
            try controller?.checkpoint()
            let stageFrac = totalBytes > 0 ? Double(stagedBytes) / Double(totalBytes) : 0
            progress?(OperationProgress(
                fractionCompleted: stageFrac * 0.08,
                currentItem: item.archivePath,
                processedBytes: UInt64(Double(totalBytes) * stageFrac * 0.08),
                totalBytes: totalBytes
            ))

            let clean = item.archivePath.hasSuffix("/") ? String(item.archivePath.dropLast()) : item.archivePath
            let dest = staging.appendingPathComponent(clean)
            if item.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else if item.isSymbolicLink, let target = item.symlinkTarget {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
            } else if let src = item.fileURL {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Prefer APFS/HFS+ hardlink to eliminate duplicate disk I/O; fallback to copy only across volumes.
                do {
                    try fm.linkItem(at: src, to: dest)
                } catch {
                    try fm.copyItem(at: src, to: dest)
                }
            }
            stagedBytes += item.fileSize
            if let first = clean.split(separator: "/").first.map(String.init), !seenTop.contains(first) {
                seenTop.insert(first)
                topLevelNames.append(first)
            }
        }

        try controller?.checkpoint()
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let tarOptions = sevenZipTarOptions(algorithm: algorithm, level: level)
        var args = ["--format=7zip"]
        if let tarOptions {
            args.append(contentsOf: ["--options", tarOptions])
        }
        args.append(contentsOf: ["-cf", outputURL.path, "-C", staging.path])
        args.append(contentsOf: topLevelNames.isEmpty ? ["."] : topLevelNames)
        let outName = outputURL.lastPathComponent
        let compressStart = CFAbsoluteTimeGetCurrent()
        let estCompressedTarget = algorithm == .store ? max(1, totalBytes) : max(1, totalBytes / 3)
        do {
            _ = try runTar(arguments: args, controller: controller) {
                let writtenBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
                let elapsed = CFAbsoluteTimeGetCurrent() - compressStart
                let sizeFrac = totalBytes > 0
                    ? min(0.96, 0.08 + 0.88 * min(1.0, Double(writtenBytes) / Double(estCompressedTarget)))
                    : 0.5
                let timeFrac = 0.08 + 0.86 * (1.0 - exp(-elapsed * 0.45))
                let frac = min(0.96, max(sizeFrac, timeFrac))
                let estProcessed = totalBytes > 0 ? UInt64(Double(totalBytes) * frac) : writtenBytes
                progress?(OperationProgress(
                    fractionCompleted: frac,
                    currentItem: outName,
                    processedBytes: estProcessed,
                    totalBytes: totalBytes
                ))
            }
        } catch {
            try? fm.removeItem(at: outputURL)
            throw error
        }
        progress?(OperationProgress(fractionCompleted: 1.0, currentItem: outName, processedBytes: totalBytes, totalBytes: totalBytes))
    }

    private static func sevenZipTarOptions(algorithm: CompressionAlgorithm, level: Int?) -> String? {
        switch algorithm {
        case .store:
            return "7zip:compression=store"
        case .xz:
            let lvl = min(max(level ?? algorithm.defaultLevel, 0), 9)
            return "7zip:compression=lzma2,7zip:compression-level=\(lvl)"
        case .bzip2:
            let lvl = min(max(level ?? algorithm.defaultLevel, 1), 9)
            return "7zip:compression=bzip2,7zip:compression-level=\(lvl)"
        case .deflate:
            let lvl = min(max(level ?? algorithm.defaultLevel, 1), 9)
            return "7zip:compression=deflate,7zip:compression-level=\(lvl)"
        case .zstd, .lz4:
            let lvl = min(max(level ?? CompressionAlgorithm.xz.defaultLevel, 0), 9)
            return "7zip:compression=lzma2,7zip:compression-level=\(lvl)"
        }
    }

    /// Decodes `bsdtar` `safe_fprintf` octal escapes (`\350\213\217`) back into UTF-8/CJK paths.
    static func unescapeBsdtarPath(_ raw: String, encoding: FilenameEncodingOption = .auto) -> String {
        guard raw.contains("\\") else { return raw }

        let bytes = Array(raw.utf8)
        let isOctalDigit: (UInt8) -> Bool = { $0 >= 0x30 && $0 <= 0x37 } // '0'...'7'

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
                    case 0x5C: decoded.append(0x5C); i += 2; continue
                    case 0x61: decoded.append(0x07); i += 2; continue
                    case 0x62: decoded.append(0x08); i += 2; continue
                    case 0x66: decoded.append(0x0C); i += 2; continue
                    case 0x6E: decoded.append(0x0A); i += 2; continue
                    case 0x72: decoded.append(0x0D); i += 2; continue
                    case 0x74: decoded.append(0x09); i += 2; continue
                    case 0x76: decoded.append(0x0B); i += 2; continue
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

    // MARK: - Private C / Subprocess Helpers

    private static func extractRawPathData(from info: bolt_la_entry_info_t) -> Data {
        if let ptr = info.raw_path_bytes, info.raw_path_len > 0 {
            return Data(bytes: ptr, count: info.raw_path_len)
        }
        if let p = info.path {
            return Data(String(cString: p).utf8)
        }
        return Data()
    }

    private static func withCStringArray<T>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>, Int) -> T) -> T {
        let duped: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        defer {
            for ptr in duped {
                if let ptr { free(ptr) }
            }
        }
        var constPtrs: [UnsafePointer<CChar>?] = duped.map { $0.map { UnsafePointer($0) } }
        return constPtrs.withUnsafeMutableBufferPointer { buf in
            body(buf.baseAddress!, buf.count)
        }
    }

    private static func withOptionalCString<T>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let string, !string.isEmpty else {
            return body(nil)
        }
        return string.withCString { body($0) }
    }

    private static func throwIfLibarchiveError(_ code: Int32, errBuf: [CChar], contextName: String) throws {
        guard code != 0 else { return }
        switch code {
        case BOLT_LA_ERR_CANCELLED:
            throw BoltZipError.cancelled
        case BOLT_LA_ERR_PASSWORD_REQUIRED:
            throw BoltZipError.passwordRequired(contextName)
        case BOLT_LA_ERR_WRONG_PASSWORD:
            throw BoltZipError.wrongPassword(contextName)
        default:
            let msg = errBuf.withUnsafeBufferPointer { buf -> String in
                guard let base = buf.baseAddress else { return "" }
                return String(cString: base).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let fallback = BoltCoreLocalization.t(
                "归档处理失败 (code \(code))",
                "封存檔處理失敗 (code \(code))",
                "Archive processing failed (code \(code))",
                "書庫処理に失敗しました (code \(code))"
            )
            throw BoltZipError.externalToolFailed(msg.isEmpty ? fallback : msg)
        }
    }

    private static func runTar(
        arguments: [String],
        controller: ArchiveTaskController? = nil,
        onTick: (@Sendable () -> Void)? = nil
    ) throws -> String {
        let data = try runTarData(arguments: arguments, controller: controller, onTick: onTick)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func runTarData(
        arguments: [String],
        controller: ArchiveTaskController? = nil,
        onTick: (@Sendable () -> Void)? = nil
    ) throws -> Data {
        try controller?.checkpoint()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = arguments
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
        let pid = proc.processIdentifier
        controller?.setHooks(
            onPause: { paused in
                if pid > 0 {
                    _ = Darwin.kill(pid, paused ? SIGSTOP : SIGCONT)
                }
            },
            onCancel: {
                if pid > 0 {
                    _ = Darwin.kill(pid, SIGCONT)
                }
                proc.terminate()
            }
        )
        defer { controller?.clearHooks() }

        let ticker: DispatchSourceTimer?
        if let onTick {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
            timer.setEventHandler { [weak controller] in
                if controller?.isPaused == true || controller?.isCancelled == true { return }
                onTick()
            }
            timer.resume()
            ticker = timer
        } else {
            ticker = nil
        }
        defer { ticker?.cancel() }

        final class PipeBuffer: @unchecked Sendable {
            var data = Data()
        }
        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        let drainGroup = DispatchGroup()

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outBuffer.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errBuffer.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        drainGroup.wait()
        proc.waitUntilExit()

        let outData = outBuffer.data
        let errData = errBuffer.data

        if controller?.isCancelled == true {
            throw BoltZipError.cancelled
        }

        if proc.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tar failed"
            let fallback = BoltCoreLocalization.t(
                "归档处理失败 (code \(proc.terminationStatus))",
                "封存檔處理失敗 (code \(proc.terminationStatus))",
                "Archive processing failed (code \(proc.terminationStatus))",
                "書庫処理に失敗しました (code \(proc.terminationStatus))"
            )
            throw BoltZipError.externalToolFailed(errMsg.isEmpty ? fallback : errMsg)
        }
        return outData
    }
}
