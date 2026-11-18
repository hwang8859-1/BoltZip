@testable import BoltZipCore
import Foundation
import os
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import XCTest

final class BoltZipCoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoltZipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAllOpenSourceCodecsRoundtripIncludingEmpty() throws {
        let payloads: [Data] = [
            Data(),
            Data("A".utf8),
            Data("BoltZip open-source compression engine for macOS 27.3 — 测试中文混合数据 1234567890!".utf8),
            BenchmarkRunner.generateMixedSampleData(sizeBytes: 256 * 1024)
        ]

        for algo in CompressionAlgorithm.allCases {
            for sample in payloads {
                let compressed = try CompressionCodec.compress(data: sample, algorithm: algo)
                let restored = try CompressionCodec.decompress(
                    data: compressed,
                    algorithm: algo,
                    expectedSize: sample.count
                )
                XCTAssertEqual(restored, sample, "Failed roundtrip for \(algo.rawValue) with size \(sample.count)")
            }
        }
    }

    func testZipCreateListExtractAndMacJunkFilter() throws {
        let srcFolder = tempDir.appendingPathComponent("ProjectAlpha", isDirectory: true)
        try FileManager.default.createDirectory(at: srcFolder, withIntermediateDirectories: true)
        try Data("Main README content".utf8).write(to: srcFolder.appendingPathComponent("README.md"))
        try Data([1, 2, 3]).write(to: srcFolder.appendingPathComponent(".DS_Store"))
        try Data([4, 5, 6]).write(to: srcFolder.appendingPathComponent("._README.md"))

        let sub = srcFolder.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("print(\"Hello BoltZip\")\n".utf8).write(to: sub.appendingPathComponent("main.swift"))

        let zipURL = tempDir.appendingPathComponent("ProjectAlpha.zip")
        try BoltArchiveEngine.createArchive(
            from: [srcFolder],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, excludeMacJunk: true)
        )

        let listing = try BoltArchiveEngine.inspect(archiveURL: zipURL)
        let paths = Set(listing.entries.map(\.path))
        XCTAssertTrue(paths.contains("ProjectAlpha/README.md"))
        XCTAssertTrue(paths.contains("ProjectAlpha/src/main.swift"))
        XCTAssertFalse(paths.contains(where: { $0.contains(".DS_Store") || $0.contains("._README.md") }))

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL)
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.failedCount, 0)

        let outDir = tempDir.appendingPathComponent("Out", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: zipURL, options: ExtractOptions(destinationURL: outDir, mode: .smart))
        // Smart extract: single root folder "ProjectAlpha" extracts directly into outDir/ProjectAlpha
        let extracted = try String(contentsOf: outDir.appendingPathComponent("ProjectAlpha/src/main.swift"), encoding: .utf8)
        XCTAssertEqual(extracted, "print(\"Hello BoltZip\")\n")
    }

    func testZipWithZstdAndBzip2Algorithms() throws {
        let file = tempDir.appendingPathComponent("data.json")
        let payload = BenchmarkRunner.generateMixedSampleData(sizeBytes: 120_000)
        try payload.write(to: file)

        for algo in [CompressionAlgorithm.zstd, .bzip2, .store] {
            let zipURL = tempDir.appendingPathComponent("archive-\(algo.rawValue).zip")
            try BoltArchiveEngine.createArchive(
                from: [file],
                to: zipURL,
                options: CreateArchiveOptions(format: .zip, algorithm: algo)
            )
            let readBack = try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "data.json")
            XCTAssertEqual(readBack, payload)
        }
    }

    func testWinZipAE2AES256AndZipCryptoEncryption() throws {
        let secret = Data("Top secret financial report 2026 — 机密文档".utf8)
        let file = tempDir.appendingPathComponent("secret.txt")
        try secret.write(to: file)

        for enc in [EncryptionMethod.aes256, EncryptionMethod.zipCrypto] {
            let zipURL = tempDir.appendingPathComponent("locked-\(enc.rawValue).zip")
            try BoltArchiveEngine.createArchive(
                from: [file],
                to: zipURL,
                options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encryption: enc, password: "BoltPassword!2026")
            )

            // Missing password should fail
            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "secret.txt", password: nil))
            // Wrong password should fail
            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "secret.txt", password: "wrong"))

            // Correct password restores exact bytes
            let restored = try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "secret.txt", password: "BoltPassword!2026")
            XCTAssertEqual(restored, secret)

            let reportBad = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL, password: nil)
            XCTAssertEqual(reportBad.skippedEncryptedCount, 1)

            let reportGood = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL, password: "BoltPassword!2026")
            XCTAssertTrue(reportGood.isHealthy)
        }
    }

    func testSystemUnzipInteroperability() throws {
        let src = tempDir.appendingPathComponent("interop.txt")
        let content = "Interoperability check between BoltZip and macOS system unzip / tar\n"
        try Data(content.utf8).write(to: src)

        let zipURL = tempDir.appendingPathComponent("interop.zip")
        try BoltArchiveEngine.createArchive(
            from: [src],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        let sysOut = tempDir.appendingPathComponent("sys_out", isDirectory: true)
        try FileManager.default.createDirectory(at: sysOut, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", zipURL.path, "-d", sysOut.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let extracted = try String(contentsOf: sysOut.appendingPathComponent("interop.txt"), encoding: .utf8)
        XCTAssertEqual(extracted, content)
    }

    func testWindowsGBKFilenameEncodingAutoDetection() throws {
        // Construct a ZIP with GB18030 / CP936 filename bytes WITHOUT UTF-8 flag bit 11 (simulating Windows Explorer / old WinRAR)
        let chinesePath = "财务报表/2026年度汇总.txt"
        let src = tempDir.appendingPathComponent("tmp.txt")
        try Data("100万".utf8).write(to: src)

        let zipURL = tempDir.appendingPathComponent("win_gbk.zip")
        try BoltArchiveEngine.createArchive(
            from: [src],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encoding: .gb18030)
        )
        // Rename entry to GB18030 path by writing direct ZIP with GBK encoding
        let gbkCF = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let gbkEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(gbkCF))
        let gbkBytes = chinesePath.data(using: gbkEnc)!
        let decoded = FilenameEncoding.decode(gbkBytes, hasUTF8Flag: false, preferred: .auto)
        XCTAssertEqual(decoded, chinesePath)
    }

    func testInPlaceZipEditingAddRenameDeleteCreateFolder() throws {
        let aURL = tempDir.appendingPathComponent("a.txt")
        let bURL = tempDir.appendingPathComponent("b.txt")
        let cURL = tempDir.appendingPathComponent("c.txt")
        try Data("alpha".utf8).write(to: aURL)
        try Data("beta".utf8).write(to: bURL)
        try Data("gamma".utf8).write(to: cURL)

        let zipURL = tempDir.appendingPathComponent("editable.zip")
        try BoltArchiveEngine.createArchive(
            from: [aURL, bURL],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        try BoltArchiveEngine.editZip(
            at: zipURL,
            operations: [
                .createFolder(path: "docs/"),
                .addItems(urls: [cURL], targetFolder: "docs/"),
                .renamePath(oldPath: "a.txt", newPath: "docs/a_renamed.txt"),
                .deletePaths(["b.txt"])
            ]
        )

        let listing = try BoltArchiveEngine.inspect(archiveURL: zipURL)
        let paths = Set(listing.entries.map(\.path))
        XCTAssertTrue(paths.contains("docs/"))
        XCTAssertTrue(paths.contains("docs/c.txt"))
        XCTAssertTrue(paths.contains("docs/a_renamed.txt"))
        XCTAssertFalse(paths.contains("a.txt"))
        XCTAssertFalse(paths.contains("b.txt"))

        XCTAssertEqual(String(data: try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "docs/a_renamed.txt"), encoding: .utf8), "alpha")
        XCTAssertEqual(String(data: try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "docs/c.txt"), encoding: .utf8), "gamma")
    }

    func testSplitVolumeZipCreateInspectTestAndExtract() throws {
        let bigFile = tempDir.appendingPathComponent("large.bin")
        var randomBytes = Data(count: 260_000)
        for i in 0..<randomBytes.count {
            randomBytes[i] = UInt8((i * 37 + i / 251) & 0xFF)
        }
        try randomBytes.write(to: bigFile)

        let zipURL = tempDir.appendingPathComponent("split_archive.zip")
        let parts = try BoltArchiveEngine.createArchive(
            from: [bigFile],
            to: zipURL,
            options: CreateArchiveOptions(
                format: .zip,
                algorithm: .store,
                splitVolumeSizeBytes: 80_000
            )
        )

        XCTAssertGreaterThanOrEqual(parts.count, 3)
        XCTAssertTrue(parts.contains { $0.lastPathComponent == "split_archive.z01" })
        XCTAssertTrue(parts.contains { $0.lastPathComponent == "split_archive.zip" })

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL)
        XCTAssertTrue(report.isHealthy)

        let extracted = try BoltArchiveEngine.readEntryData(archiveURL: zipURL, entryPath: "large.bin")
        XCTAssertEqual(extracted, randomBytes)
    }

    func testTarZstTarXzAndSevenZipWithLongUnicodePath() throws {
        let longFolder = tempDir.appendingPathComponent("这是一个超长的文件夹名称用于触发PAX扩展头记录_0123456789_0123456789_0123456789_0123456789", isDirectory: true)
        try FileManager.default.createDirectory(at: longFolder, withIntermediateDirectories: true)
        let f = longFolder.appendingPathComponent("测试文档_long_filename_test_0123456789.txt")
        let expected = "PAX + Zstd + XZ + 7z roundtrip content!"
        try Data(expected.utf8).write(to: f)

        for fmt in [ArchiveFormat.tarZst, .tarXz, .tarGz, .tarBz2, .tarLz4, .sevenZip] {
            let arch = tempDir.appendingPathComponent("pkg.\(fmt.fileExtension)")
            try BoltArchiveEngine.createArchive(
                from: [longFolder],
                to: arch,
                options: CreateArchiveOptions(format: fmt, algorithm: fmt.defaultAlgorithm)
            )
            let outDir = tempDir.appendingPathComponent("out-\(fmt.rawValue)", isDirectory: true)
            try BoltArchiveEngine.extract(archiveURL: arch, options: ExtractOptions(destinationURL: outDir, mode: .smart))
            let actual = try String(contentsOf: outDir.appendingPathComponent(longFolder.lastPathComponent).appendingPathComponent(f.lastPathComponent), encoding: .utf8)
            XCTAssertEqual(actual, expected, "Failed for \(fmt.rawValue)")
        }
    }

    func testSmartExtractMultiRootCreatesSubfolder() throws {
        let a = tempDir.appendingPathComponent("one.txt")
        let b = tempDir.appendingPathComponent("two.txt")
        try Data("1".utf8).write(to: a)
        try Data("2".utf8).write(to: b)

        let zipURL = tempDir.appendingPathComponent("BundlePackage.zip")
        try BoltArchiveEngine.createArchive(from: [a, b], to: zipURL, options: CreateArchiveOptions())

        let outDir = tempDir.appendingPathComponent("ExtractTarget", isDirectory: true)
        let resolvedRoot = try BoltArchiveEngine.extract(archiveURL: zipURL, options: ExtractOptions(destinationURL: outDir, mode: .smart))
        XCTAssertEqual(resolvedRoot.lastPathComponent, "BundlePackage")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedRoot.appendingPathComponent("one.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedRoot.appendingPathComponent("two.txt").path))
    }

    func testTamperedZipDetectedByIntegrityTest() throws {
        let file = tempDir.appendingPathComponent("clean.txt")
        try Data(repeating: 0x41, count: 4096).write(to: file)
        let zipURL = tempDir.appendingPathComponent("tamper.zip")
        try BoltArchiveEngine.createArchive(from: [file], to: zipURL, options: CreateArchiveOptions(format: .zip, algorithm: .store))

        var bytes = try Data(contentsOf: zipURL)
        bytes[80] ^= 0xFF // Flip a byte inside stored payload
        try bytes.write(to: zipURL)

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL)
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(report.failedCount, 1)
    }

    func testBsdtarOctalEscapeDecodingAndSevenZipChineseInspect() throws {
        let escaped = "\\350\\213\\217\\345\\267\\236\\351\\241\\271\\347\\233\\256-\\346\\212\\245\\351\\224\\200\\346\\235\\220\\346\\226\\231/test.pdf"
        XCTAssertEqual(ExtendedArchiveDriver.unescapeBsdtarPath(escaped), "苏州项目-报销材料/test.pdf")
        XCTAssertEqual(ExtendedArchiveDriver.unescapeBsdtarPath("plain/report.pdf"), "plain/report.pdf")

        let folder = tempDir.appendingPathComponent("苏州项目建设一处-黄旭阳", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let doc = folder.appendingPathComponent("软件设计师（中级）-证书.pdf")
        let payload = Data("%PDF-1.4\n测试内容".utf8)
        try payload.write(to: doc)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent(".DS_Store"))

        let sevenZipURL = tempDir.appendingPathComponent("苏州测试.7z")
        try BoltArchiveEngine.createArchive(
            from: [folder],
            to: sevenZipURL,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, excludeMacJunk: true)
        )

        let listing = try BoltArchiveEngine.inspect(archiveURL: sevenZipURL)
        let paths = Set(listing.entries.map(\.path))
        XCTAssertTrue(paths.contains("苏州项目建设一处-黄旭阳/软件设计师（中级）-证书.pdf"))
        XCTAssertFalse(paths.contains { $0.contains("350") || $0.contains(".DS_Store") })

        let previewData = try BoltArchiveEngine.readEntryData(
            archiveURL: sevenZipURL,
            entryPath: "苏州项目建设一处-黄旭阳/软件设计师（中级）-证书.pdf"
        )
        XCTAssertEqual(previewData, payload)
    }

    func testBenchmarkRunnerProducesValidMetrics() throws {
        let results = try BenchmarkRunner.run(on: BenchmarkRunner.generateMixedSampleData(sizeBytes: 256 * 1024))
        XCTAssertEqual(results.count, 5)
        for r in results {
            XCTAssertGreaterThan(r.compressMBps, 0)
            XCTAssertGreaterThan(r.decompressMBps, 0)
            XCTAssertGreaterThan(r.ratioPercent, 50)
        }
    }

    func testArchiveTaskControllerPauseResumeAndByteProgress() throws {
        let payload = BenchmarkRunner.generateMixedSampleData(sizeBytes: 2 * 1024 * 1024)
        let inputFile = tempDir.appendingPathComponent("payload.bin")
        try payload.write(to: inputFile)

        let zipURL = tempDir.appendingPathComponent("paused.zip")
        let controller = ArchiveTaskController()
        let recorded = OSAllocatedUnfairLock(initialState: (didPause: false, maxProcessed: UInt64(0), totalBytes: UInt64(0), lastFraction: 0.0))

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12) {
            controller.setPaused(false)
        }

        try BoltArchiveEngine.createArchive(
            from: [inputFile],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate),
            controller: controller
        ) { progress in
            let shouldTriggerPause = recorded.withLock { state -> Bool in
                state.maxProcessed = max(state.maxProcessed, progress.processedBytes)
                state.totalBytes = max(state.totalBytes, progress.totalBytes)
                state.lastFraction = max(state.lastFraction, progress.fractionCompleted)
                if !state.didPause && progress.processedBytes >= 128 * 1024 {
                    state.didPause = true
                    return true
                }
                return false
            }
            if shouldTriggerPause {
                controller.setPaused(true)
            }
        }

        let summary = recorded.withLock { $0 }
        XCTAssertTrue(summary.didPause)
        XCTAssertGreaterThan(summary.totalBytes, 0)
        XCTAssertEqual(summary.maxProcessed, summary.totalBytes)
        XCTAssertEqual(summary.lastFraction, 1.0, accuracy: 0.001)

        let outDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        _ = try BoltArchiveEngine.extract(
            archiveURL: zipURL,
            options: ExtractOptions(destinationURL: outDir, mode: .here),
            controller: ArchiveTaskController()
        )
        let extractedData = try Data(contentsOf: outDir.appendingPathComponent("payload.bin"))
        XCTAssertEqual(extractedData, payload)
    }

    func testArchiveTaskControllerCancelCleansUpPartialOutputs() throws {
        let payload = BenchmarkRunner.generateMixedSampleData(sizeBytes: 2 * 1024 * 1024)
        let inputFile = tempDir.appendingPathComponent("cancel-input.bin")
        try payload.write(to: inputFile)

        let zipURL = tempDir.appendingPathComponent("cancelled.zip")
        let controller = ArchiveTaskController()
        let didCancel = OSAllocatedUnfairLock(initialState: false)

        XCTAssertThrowsError(
            try BoltArchiveEngine.createArchive(
                from: [inputFile],
                to: zipURL,
                options: CreateArchiveOptions(format: .zip, algorithm: .deflate),
                controller: controller
            ) { progress in
                if progress.processedBytes >= 128 * 1024 {
                    let triggered = didCancel.withLock { flag -> Bool in
                        if !flag {
                            flag = true
                            return true
                        }
                        return false
                    }
                    if triggered {
                        controller.cancel()
                    }
                }
            }
        ) { error in
            if case .cancelled = (error as? BoltZipError) {
                // Expected cancellation error
            } else {
                XCTFail("Expected BoltZipError.cancelled, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: zipURL.path))
    }

    func testExtractConflictDetectionAndAutoRenameRootDirectory() throws {
        let projectDir = tempDir.appendingPathComponent("ProjectAlpha", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "new version".write(to: projectDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("ProjectAlpha.zip")
        _ = try BoltArchiveEngine.createArchive(
            from: [projectDir],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        // Mutate existing folder content to represent an existing path collision
        try "existing version".write(to: projectDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let smartOpts = ExtractOptions(destinationURL: tempDir, mode: .smart, overwritePolicy: .overwrite)
        let conflicts = try BoltArchiveEngine.detectExtractConflicts(archiveURL: zipURL, options: smartOpts)
        XCTAssertTrue(conflicts.hasConflicts)
        XCTAssertEqual(conflicts.conflictingNames, ["ProjectAlpha"])

        let renameOpts = ExtractOptions(destinationURL: tempDir, mode: .smart, overwritePolicy: .rename)
        _ = try BoltArchiveEngine.extract(archiveURL: zipURL, options: renameOpts)

        // Existing folder preserved untouched while auto-renamed copy received new contents
        XCTAssertEqual(
            try String(contentsOf: projectDir.appendingPathComponent("readme.txt"), encoding: .utf8),
            "existing version"
        )
        let renamedDir = tempDir.appendingPathComponent("ProjectAlpha (1)", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedDir.path))
        XCTAssertEqual(
            try String(contentsOf: renamedDir.appendingPathComponent("readme.txt"), encoding: .utf8),
            "new version"
        )
    }

    func testRarFormatDetectionInspectReadExtractAndIntegrity() throws {
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/sample.rar")), .rar)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/sample.part1.rar")), .rar)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/sample.part02.rar")), .rar)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/sample.r00")), .rar)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/sample.r15")), .rar)

        func encodeVInt(_ value: UInt64) -> Data {
            var v = value
            var out = Data()
            while true {
                var byte = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 { byte |= 0x80 }
                out.append(byte)
                if v == 0 { break }
            }
            return out
        }

        func appendUInt32LE(_ dst: inout Data, _ val: UInt32) {
            dst.append(UInt8(val & 0xFF))
            dst.append(UInt8((val >> 8) & 0xFF))
            dst.append(UInt8((val >> 16) & 0xFF))
            dst.append(UInt8((val >> 24) & 0xFF))
        }

        func buildRar5Block(type: UInt64, flags: UInt64, body: Data, payload: Data = Data()) -> Data {
            var core = Data()
            core.append(encodeVInt(type))
            core.append(encodeVInt(flags))
            if (flags & 0x0002) != 0 {
                core.append(encodeVInt(UInt64(payload.count)))
            }
            core.append(body)
            let headerSize = encodeVInt(UInt64(core.count))
            var crcInput = Data()
            crcInput.append(headerSize)
            crcInput.append(core)
            let crc = CompressionCodec.crc32(crcInput)

            var block = Data()
            appendUInt32LE(&block, crc)
            block.append(crcInput)
            block.append(payload)
            return block
        }

        func buildRar5FileHeader(path: String, payload: Data) -> Data {
            let nameBytes = Data(path.utf8)
            var fbody = Data()
            fbody.append(encodeVInt(0x0004)) // Data CRC32 present
            fbody.append(encodeVInt(UInt64(payload.count)))
            fbody.append(encodeVInt(0o644))
            appendUInt32LE(&fbody, CompressionCodec.crc32(payload))
            fbody.append(encodeVInt(0)) // Store method
            fbody.append(encodeVInt(1)) // Unix Host OS
            fbody.append(encodeVInt(UInt64(nameBytes.count)))
            fbody.append(nameBytes)
            return buildRar5Block(type: 2, flags: 0x0002, body: fbody, payload: payload)
        }

        let payloadA = Data("RAR5 中文路径与文件内容测试 — BoltZip Engine!\n".utf8)
        let payloadB = Data("Second file inside RAR5 container\n".utf8)

        var rarData = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) // Rar!\x1a\x07\x01\x00
        rarData.append(buildRar5Block(type: 1, flags: 0, body: encodeVInt(0))) // Main archive header
        rarData.append(buildRar5FileHeader(path: "项目资料/说明文档.txt", payload: payloadA))
        rarData.append(buildRar5FileHeader(path: "项目资料/second.txt", payload: payloadB))
        rarData.append(buildRar5Block(type: 5, flags: 0, body: encodeVInt(0))) // End of archive

        let rarURL = tempDir.appendingPathComponent("测试归档.rar")
        try rarData.write(to: rarURL)

        let listing = try BoltArchiveEngine.inspect(archiveURL: rarURL)
        XCTAssertEqual(listing.format, .rar)
        XCTAssertEqual(listing.entries.count, 2)
        XCTAssertEqual(Set(listing.entries.map(\.path)), ["项目资料/说明文档.txt", "项目资料/second.txt"])

        let preview = try BoltArchiveEngine.readEntryData(archiveURL: rarURL, entryPath: "项目资料/说明文档.txt")
        XCTAssertEqual(preview, payloadA)

        let healthyReport = try BoltArchiveEngine.testIntegrity(archiveURL: rarURL)
        XCTAssertTrue(healthyReport.isHealthy)
        XCTAssertEqual(healthyReport.passedCount, 2)
        XCTAssertEqual(healthyReport.failedCount, 0)

        let outDir = tempDir.appendingPathComponent("rar_out", isDirectory: true)
        let resolvedRoot = try BoltArchiveEngine.extract(
            archiveURL: rarURL,
            options: ExtractOptions(destinationURL: outDir, mode: .smart)
        )
        XCTAssertEqual(
            try Data(contentsOf: resolvedRoot.appendingPathComponent("项目资料/说明文档.txt")),
            payloadA
        )
        XCTAssertEqual(
            try Data(contentsOf: resolvedRoot.appendingPathComponent("项目资料/second.txt")),
            payloadB
        )

        // Truncate archive stream and verify real integrity test reports failure
        let truncated = Data(rarData.prefix(rarData.count - 15))
        let badRarURL = tempDir.appendingPathComponent("bad.rar")
        try truncated.write(to: badRarURL)
        let badReport = try BoltArchiveEngine.testIntegrity(archiveURL: badRarURL)
        XCTAssertFalse(badReport.isHealthy)
        XCTAssertGreaterThan(badReport.failedCount, 0)

        // Verify multi-volume RAR volume resolution (.part1.rar + .part2.rar and .rar + .r00)
        let part1 = tempDir.appendingPathComponent("movie.part1.rar")
        let part2 = tempDir.appendingPathComponent("movie.part2.rar")
        try Data().write(to: part1)
        try Data().write(to: part2)
        XCTAssertEqual(
            ExtendedArchiveDriver.resolveVolumePaths(for: part2, format: .rar).map { URL(fileURLWithPath: $0).lastPathComponent },
            ["movie.part1.rar", "movie.part2.rar"]
        )

        let legacyMain = tempDir.appendingPathComponent("legacy.rar")
        let legacyR00 = tempDir.appendingPathComponent("legacy.r00")
        let legacyR01 = tempDir.appendingPathComponent("legacy.r01")
        try Data().write(to: legacyMain)
        try Data().write(to: legacyR00)
        try Data().write(to: legacyR01)
        XCTAssertEqual(
            ExtendedArchiveDriver.resolveVolumePaths(for: legacyR00, format: .rar).map { URL(fileURLWithPath: $0).lastPathComponent },
            ["legacy.rar", "legacy.r00", "legacy.r01"]
        )
    }

    func testMultiCoreParallelZipCreateExtractAndIntegrity() throws {
        XCTAssertGreaterThanOrEqual(CompressionCodec.activeCoreCount, 1)

        let batchDir = tempDir.appendingPathComponent("ParallelBatch", isDirectory: true)
        try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)

        var expectedByName: [String: Data] = [:]
        for i in 0..<24 {
            let fileName = String(format: "part_%02d_数据.bin", i)
            let data = BenchmarkRunner.generateMixedSampleData(sizeBytes: 32 * 1024 + i * 777)
            expectedByName[fileName] = data
            try data.write(to: batchDir.appendingPathComponent(fileName))
        }

        let zipURL = tempDir.appendingPathComponent("ParallelBatch.zip")
        try BoltArchiveEngine.createArchive(
            from: [batchDir],
            to: zipURL,
            options: CreateArchiveOptions(
                format: .zip,
                algorithm: .zstd,
                encryption: .aes256,
                password: "ParallelPassword!2026"
            )
        )

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL, password: "ParallelPassword!2026")
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.passedCount, 25) // 1 root folder + 24 files
        XCTAssertEqual(report.failedCount, 0)

        let extractDir = tempDir.appendingPathComponent("ParallelOut", isDirectory: true)
        _ = try BoltArchiveEngine.extract(
            archiveURL: zipURL,
            options: ExtractOptions(
                destinationURL: extractDir,
                mode: .smart,
                password: "ParallelPassword!2026"
            )
        )

        for (name, expectedData) in expectedByName {
            let restored = try Data(contentsOf: extractDir.appendingPathComponent("ParallelBatch").appendingPathComponent(name))
            XCTAssertEqual(restored, expectedData, "Mismatch for \(name)")
        }

        // Verify multi-core buffer compression (> 512 KB triggers Zstd/XZ worker threads)
        let largeResults = try BenchmarkRunner.run(on: BenchmarkRunner.generateMixedSampleData(sizeBytes: 768 * 1024))
        XCTAssertEqual(largeResults.count, 5)
        for r in largeResults {
            XCTAssertGreaterThan(r.compressMBps, 0)
            XCTAssertGreaterThan(r.decompressMBps, 0)
        }
    }

    func testComicArchiveDetectionAndAssociationGroupMetadata() throws {
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/issue1.cbz")), .zip)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/issue2.cbr")), .rar)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/issue3.cb7")), .sevenZip)

        let pageURL = tempDir.appendingPathComponent("page01.txt")
        try Data("Comic page 1".utf8).write(to: pageURL)
        let cbzURL = tempDir.appendingPathComponent("comic.cbz")
        try BoltArchiveEngine.createArchive(
            from: [pageURL],
            to: cbzURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )
        let listing = try BoltArchiveEngine.inspect(archiveURL: cbzURL)
        XCTAssertEqual(listing.format, .zip)
        XCTAssertEqual(listing.entries.map(\.name), ["page01.txt"])

        #if canImport(AppKit) && canImport(UniformTypeIdentifiers)
        XCTAssertFalse(ArchiveAssociationGroup.commonArchiveGroups.contains(.iso))
        XCTAssertTrue(ArchiveAssociationGroup.commonArchiveGroups.contains(.zip))
        XCTAssertTrue(ArchiveAssociationGroup.commonArchiveGroups.contains(.sevenZip))
        XCTAssertNotNil(UTType("public.zip-archive"))
        XCTAssertNotNil(UTType("public.tar-archive"))
        XCTAssertNotNil(UTType("public.iso-image"))
        for group in ArchiveAssociationGroup.allCases {
            XCTAssertFalse(group.utTypeIdentifiers.isEmpty, "Expected UTI identifiers for \(group.rawValue)")
            XCTAssertFalse(group.fallbackExtensions.isEmpty, "Expected fallback extensions for \(group.rawValue)")
            XCTAssertNotNil(group.primaryUTType, "Expected resolved or dynamic UTType for \(group.rawValue)")
        }
        #endif
    }

    func testCoreLocalizationAcrossSupportedLanguages() throws {
        defer { BoltCoreLocalization.overrideLanguage = nil }

        XCTAssertEqual(BoltCoreLanguage.resolve(preferredLanguages: ["ja-JP"]), .ja)
        XCTAssertEqual(BoltCoreLanguage.resolve(preferredLanguages: ["zh-Hant-TW"]), .zhHant)
        XCTAssertEqual(BoltCoreLanguage.resolve(preferredLanguages: ["zh-HK"]), .zhHant)
        XCTAssertEqual(BoltCoreLanguage.resolve(preferredLanguages: ["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(BoltCoreLanguage.resolve(preferredLanguages: ["en-US"]), .en)

        BoltCoreLocalization.overrideLanguage = .en
        XCTAssertEqual(BoltZipError.cancelled.localizedDescription, "Operation cancelled")
        XCTAssertTrue(EncryptionMethod.aes256.displayName.contains("AES-256"))
        XCTAssertEqual(OverwritePolicy.skip.displayName, "Skip Existing")

        BoltCoreLocalization.overrideLanguage = .ja
        XCTAssertEqual(BoltZipError.cancelled.localizedDescription, "操作がキャンセルされました")
        XCTAssertEqual(OverwritePolicy.overwrite.displayName, "既存ファイルを上書き")

        BoltCoreLocalization.overrideLanguage = .zhHant
        XCTAssertTrue(BoltZipError.wrongPassword("secret.zip").localizedDescription.contains("密碼錯誤"))

        BoltCoreLocalization.overrideLanguage = .zhHans
        XCTAssertEqual(BoltZipError.cancelled.localizedDescription, "操作已取消")
    }

    func testBatchArchiveFilteringAndIntegrityAggregation() throws {
        let dir = tempDir.appendingPathComponent("folder.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plainTxt = tempDir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: plainTxt)

        let srcA = tempDir.appendingPathComponent("a.txt")
        let srcB = tempDir.appendingPathComponent("b.txt")
        try Data("Alpha payload".utf8).write(to: srcA)
        try Data("Beta payload".utf8).write(to: srcB)

        let zipA = tempDir.appendingPathComponent("first.zip")
        let zipB = tempDir.appendingPathComponent("second.zip")
        try BoltArchiveEngine.createArchive(from: [srcA], to: zipA, options: CreateArchiveOptions(format: .zip, algorithm: .deflate))
        try BoltArchiveEngine.createArchive(
            from: [srcB],
            to: zipB,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encryption: .aes256, password: "pw")
        )

        let filtered = BoltArchiveEngine.filterArchiveURLs([dir, plainTxt, zipA, zipB])
        XCTAssertEqual(filtered, [zipA, zipB])

        let reportNoPw = BoltArchiveEngine.testIntegrityBatch(archiveURLs: filtered)
        XCTAssertEqual(reportNoPw.totalEntries, 2)
        XCTAssertEqual(reportNoPw.passedCount, 1)
        XCTAssertEqual(reportNoPw.skippedEncryptedCount, 1)
        XCTAssertEqual(reportNoPw.failedCount, 0)
        XCTAssertFalse(reportNoPw.isHealthy)
        XCTAssertTrue(reportNoPw.results.contains { $0.path.hasPrefix("first.zip /") })
        XCTAssertTrue(reportNoPw.results.contains { $0.path.hasPrefix("second.zip /") })

        let reportWithPw = BoltArchiveEngine.testIntegrityBatch(archiveURLs: filtered, password: "pw")
        XCTAssertEqual(reportWithPw.passedCount, 2)
        XCTAssertEqual(reportWithPw.failedCount, 0)
        XCTAssertEqual(reportWithPw.skippedEncryptedCount, 0)
        XCTAssertTrue(reportWithPw.isHealthy)
    }

    func testSevenZipCompressionLevelsAndSplitZipEditGuard() throws {
        // 1. Verify 7z algorithm & level options actually affect output size & extract cleanly
        let sample = BenchmarkRunner.generateMixedSampleData(sizeBytes: 512 * 1024)
        let srcFile = tempDir.appendingPathComponent("payload.json")
        try sample.write(to: srcFile)

        let store7z = tempDir.appendingPathComponent("store.7z")
        let fast7z = tempDir.appendingPathComponent("fast.7z")
        let max7z = tempDir.appendingPathComponent("max.7z")

        try BoltArchiveEngine.createArchive(
            from: [srcFile],
            to: store7z,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, level: 0)
        )
        try BoltArchiveEngine.createArchive(
            from: [srcFile],
            to: fast7z,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 1)
        )
        try BoltArchiveEngine.createArchive(
            from: [srcFile],
            to: max7z,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 9)
        )

        let storeSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: store7z.path)[.size] as? NSNumber).intValue
        let fastSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: fast7z.path)[.size] as? NSNumber).intValue
        let maxSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: max7z.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(storeSize, fastSize)
        XCTAssertGreaterThan(fastSize, maxSize)

        let out7z = tempDir.appendingPathComponent("out7z", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: max7z, options: ExtractOptions(destinationURL: out7z, mode: .here))
        XCTAssertEqual(try Data(contentsOf: out7z.appendingPathComponent("payload.json")), sample)

        // 2. Verify split-volume ZIP marks isSplitVolume & blocks destructive in-place edits
        let splitZip = tempDir.appendingPathComponent("split.zip")
        let created = try BoltArchiveEngine.createArchive(
            from: [srcFile],
            to: splitZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .store, splitVolumeSizeBytes: 128 * 1024)
        )
        XCTAssertGreaterThan(created.count, 1)

        let listing = try BoltArchiveEngine.inspect(archiveURL: splitZip)
        XCTAssertTrue(listing.isSplitVolume)
        XCTAssertFalse(listing.canEditInPlace)

        XCTAssertThrowsError(try BoltArchiveEngine.editZip(
            at: splitZip,
            operations: [.createFolder(path: "forbidden/")]
        )) { error in
            guard case BoltZipError.unsupportedFormat = error else {
                XCTFail("Expected unsupportedFormat for split-volume ZIP edit, got \(error)")
                return
            }
        }
        // Confirm split volume integrity remained intact
        let report = try BoltArchiveEngine.testIntegrity(archiveURL: splitZip)
        XCTAssertTrue(report.isHealthy)
    }

    func testCentralizedVersionMetadata() {
        XCTAssertFalse(BoltZipVersion.current.isEmpty)
        XCTAssertEqual(BoltZipVersion.current, "1.0.1")
        XCTAssertFalse(BoltZipVersion.build.isEmpty)
    }
}
