import Foundation

extension BoltArchiveEngine {
    public static func testIntegrity(
        archiveURL: URL,
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        workerCount: Int? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) throws -> IntegrityReport {
        let format = try ArchiveFormat.requireForReading(from: archiveURL)
        switch format {
        case .zip:
            return try ZipReader(url: archiveURL).testIntegrity(password: password, encoding: encoding, workerCount: workerCount, progress: progress)
        case .tar, .tarGz, .tarZst, .tarXz, .tarBz2, .tarLz4, .gz, .zst, .xz, .bz2, .lz4:
            return try TarCodec.testIntegrity(at: archiveURL, format: format)
        case .rar, .sevenZip, .iso, .cab, .xar:
            return try ExtendedArchiveDriver.testIntegrity(at: archiveURL, format: format, password: password)
        }
    }

    public static func testIntegrityBatch(
        archiveURLs: [URL],
        password: String? = nil,
        encoding: FilenameEncodingOption = .auto,
        workerCount: Int? = nil,
        batchTitle: String? = nil,
        progress: (@Sendable (OperationProgress) -> Void)? = nil
    ) -> IntegrityReport {
        let start = CFAbsoluteTimeGetCurrent()
        let totalArchives = max(1, archiveURLs.count)
        var allResults: [IntegrityEntryResult] = []
        var totalPassed = 0
        var totalFailed = 0
        var totalSkipped = 0

        for (index, url) in archiveURLs.enumerated() {
            let baseFrac = Double(index) / Double(totalArchives)
            let spanFrac = 1.0 / Double(totalArchives)
            progress?(OperationProgress(
                fractionCompleted: baseFrac,
                currentItem: url.lastPathComponent,
                processedBytes: UInt64(index),
                totalBytes: UInt64(totalArchives)
            ))

            do {
                let single = try testIntegrity(archiveURL: url, password: password, encoding: encoding, workerCount: workerCount) { sub in
                    progress?(OperationProgress(
                        fractionCompleted: min(1.0, baseFrac + sub.fractionCompleted * spanFrac),
                        currentItem: "\(url.lastPathComponent): \(sub.currentItem)",
                        processedBytes: UInt64(index),
                        totalBytes: UInt64(totalArchives)
                    ))
                }
                totalPassed += single.passedCount
                totalFailed += single.failedCount
                totalSkipped += single.skippedEncryptedCount
                for item in single.results {
                    let scopedPath = archiveURLs.count > 1
                        ? "\(url.lastPathComponent) / \(item.path)"
                        : item.path
                    allResults.append(IntegrityEntryResult(path: scopedPath, status: item.status, detail: item.detail))
                }
            } catch BoltZipError.passwordRequired {
                totalSkipped += 1
                allResults.append(IntegrityEntryResult(
                    path: url.lastPathComponent,
                    status: .missingPassword,
                    detail: BoltCoreLocalization.t("归档已加密，需要密码", "封存檔已加密，需要密碼", "Archive is encrypted; password required", "書庫が暗号化されています（パスワードが必要）")
                ))
            } catch {
                totalFailed += 1
                allResults.append(IntegrityEntryResult(
                    path: url.lastPathComponent,
                    status: .failed,
                    detail: error.localizedDescription
                ))
            }
        }

        progress?(OperationProgress(
            fractionCompleted: 1.0,
            currentItem: BoltCoreLocalization.t("校验完成", "驗證完成", "Verification complete", "検証完了"),
            processedBytes: UInt64(totalArchives),
            totalBytes: UInt64(totalArchives)
        ))

        let title = batchTitle ?? (archiveURLs.count == 1
            ? archiveURLs[0].lastPathComponent
            : BoltCoreLocalization.t(
                "\(archiveURLs.count) 个压缩包",
                "\(archiveURLs.count) 個封存檔",
                "\(archiveURLs.count) Archives",
                "\(archiveURLs.count) 件の書庫"
            ))
        return IntegrityReport(
            archiveName: title,
            totalEntries: allResults.count,
            passedCount: totalPassed,
            failedCount: totalFailed,
            skippedEncryptedCount: totalSkipped,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - start,
            results: allResults
        )
    }
}
