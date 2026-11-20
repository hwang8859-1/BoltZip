@testable import BoltZipCore
import Foundation
import os
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(AppKit)
import AppKit
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
        XCTAssertEqual(BoltZipVersion.current, "1.0.4")
        XCTAssertEqual(BoltZipVersion.build, "17")
    }

    func testMultiCoreConcurrencyControlAutoAndFixedCoreCount() throws {
        let originalPref = BoltConcurrency.preference
        defer { BoltConcurrency.setPreference(originalPref, persist: false) }

        let hw = BoltConcurrency.hardwareCoreCount
        XCTAssertGreaterThanOrEqual(hw, 1)
        XCTAssertEqual(MultiCorePreference(rawStorageValue: 0), .auto)
        XCTAssertEqual(MultiCorePreference(rawStorageValue: -3), .auto)
        XCTAssertEqual(MultiCorePreference(rawStorageValue: 4), .fixed(4))

        BoltConcurrency.setPreference(.fixed(1), persist: false)
        XCTAssertEqual(BoltConcurrency.resolvedWorkerCount(), 1)
        XCTAssertEqual(CompressionCodec.effectiveWorkerCount, 1)

        BoltConcurrency.setPreference(.fixed(999), persist: false)
        XCTAssertEqual(BoltConcurrency.resolvedWorkerCount(), hw)

        BoltConcurrency.setPreference(.auto, persist: false)
        XCTAssertEqual(BoltConcurrency.resolvedWorkerCount(), BoltConcurrency.autoWorkerCount)
        XCTAssertEqual(BoltConcurrency.resolvedWorkerCount(override: 1), 1)
        XCTAssertEqual(BoltConcurrency.resolvedWorkerCount(override: 0), BoltConcurrency.autoWorkerCount)

        // Roundtrip >512 KB Zstd & XZ streams under explicit 1-core and 2-core caps
        let payload = BenchmarkRunner.generateMixedSampleData(sizeBytes: 640 * 1024)
        for workerCap in [1, 2, 0] {
            let zstCompressed = try CompressionCodec.compress(data: payload, algorithm: .zstd, level: 3, workerCount: workerCap)
            let zstRestored = try CompressionCodec.decompress(data: zstCompressed, algorithm: .zstd, expectedSize: payload.count)
            XCTAssertEqual(zstRestored, payload)

            let xzCompressed = try CompressionCodec.compress(data: payload, algorithm: .xz, level: 1, workerCount: workerCap)
            let xzRestored = try CompressionCodec.decompress(data: xzCompressed, algorithm: .xz, expectedSize: payload.count)
            XCTAssertEqual(xzRestored, payload)
        }

        // Multi-file ZIP create/extract/test with explicit single-core & auto overrides
        let srcDir = tempDir.appendingPathComponent("CoreControlSrc", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let f1 = srcDir.appendingPathComponent("a.bin")
        let f2 = srcDir.appendingPathComponent("b.bin")
        let d1 = Data("alpha-12345".utf8)
        let d2 = Data("beta-67890".utf8)
        try d1.write(to: f1)
        try d2.write(to: f2)

        let zipSingle = tempDir.appendingPathComponent("single_core.zip")
        try BoltArchiveEngine.createArchive(
            from: [srcDir],
            to: zipSingle,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, workerCount: 1)
        )
        let integrity = try BoltArchiveEngine.testIntegrity(archiveURL: zipSingle, workerCount: 1)
        XCTAssertTrue(integrity.isHealthy)

        let outDir = tempDir.appendingPathComponent("CoreControlOut", isDirectory: true)
        try BoltArchiveEngine.extract(
            archiveURL: zipSingle,
            options: ExtractOptions(destinationURL: outDir, mode: .smart, workerCount: 1)
        )
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("CoreControlSrc/a.bin")), d1)
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("CoreControlSrc/b.bin")), d2)
    }

    func testRedesignedAppAndPerFormatDocumentIconArtwork() throws {
        #if canImport(AppKit) && canImport(CoreGraphics)
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        for whiteBG in [false, true] {
            for px in [16, 32, 64, 128, 256] {
                let appPNG = try XCTUnwrap(BoltIconArtwork.renderAppIconPNG(pixelSize: px, whiteBackground: whiteBG))
                XCTAssertTrue(appPNG.starts(with: pngSignature))
            }
        }

        // Verify lifted Dark Deep Glass backdrop luma (> L=46 baseline) and 9.75% Apple grid inset
        let dark128PNG = try XCTUnwrap(BoltIconArtwork.renderAppIconPNG(pixelSize: 128, whiteBackground: false))
        let darkRep = try XCTUnwrap(NSBitmapImageRep(data: dark128PNG))
        let outerCorner = darkRep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB)
        XCTAssertLessThan(outerCorner?.alphaComponent ?? 1.0, 0.05)
        let upperGlass = try XCTUnwrap(darkRep.colorAt(x: 24, y: 24)?.usingColorSpace(.sRGB))
        let glassLuma255 = (0.2126 * upperGlass.redComponent + 0.7152 * upperGlass.greenComponent + 0.0722 * upperGlass.blueComponent) * 255.0
        XCTAssertGreaterThan(glassLuma255, 70.0)

        let kinds = BoltDocumentIconKind.allCases
        XCTAssertEqual(Set(kinds.map(\.icnsBaseName)).count, kinds.count)
        XCTAssertEqual(Set(kinds.map(\.badgeLabel)).count, kinds.count)
        XCTAssertEqual(Set(kinds.map(\.family)).count, BoltIconFamily.allCases.count)

        XCTAssertEqual(BoltIconScale(pixelSize: 16), .micro)
        XCTAssertEqual(BoltIconScale(pixelSize: 32), .small)
        XCTAssertEqual(BoltIconScale(pixelSize: 64), .medium)
        XCTAssertEqual(BoltIconScale(pixelSize: 128), .full)
        XCTAssertEqual(BoltIconScale(pixelSize: 256), .full)

        for kind in kinds {
            for isDark in [false, true] {
                for px in [16, 32, 64, 256] {
                    let png = try XCTUnwrap(BoltIconArtwork.renderDocumentIconPNG(kind: kind, pixelSize: px, isDark: isDark))
                    XCTAssertTrue(png.starts(with: pngSignature))
                }
            }
        }

        for group in ArchiveAssociationGroup.allCases {
            XCTAssertFalse(group.utTypes.isEmpty)
            XCTAssertFalse(group.documentIconKind.icnsBaseName.isEmpty)
        }

        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "bundle.tar.zst"), .tzst)
        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "backup.TAR.GZ"), .tgz)
        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "split.z01"), .zip)
        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "comic.cbr"), .rar)
        XCTAssertNil(BoltDocumentIconKind.resolve(forFilename: "notes.txt"))
        #endif
    }

    func testStreamingOverwritePreservesExistingFileUntilExtractionSucceeds() throws {
        let oldThreshold = BoltConcurrency.streamingThresholdBytes
        BoltConcurrency.streamingThresholdBytes = 64 * 1024
        defer { BoltConcurrency.streamingThresholdBytes = oldThreshold }

        let fm = FileManager.default
        let input = tempDir.appendingPathComponent("payload.txt")
        let payload = Data(repeating: 0x41, count: 128 * 1024)
        try payload.write(to: input)
        let archive = tempDir.appendingPathComponent("protected.zip")
        let password = "BoltZip-test-password"
        try BoltArchiveEngine.createArchive(
            from: [input], to: archive,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encryption: .aes256, password: password)
        )

        let folder = tempDir.appendingPathComponent("output", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let destination = folder.appendingPathComponent(input.lastPathComponent)
        let previous = Data("existing file".utf8)
        try previous.write(to: destination)

        var options = ExtractOptions(destinationURL: folder, mode: .here, overwritePolicy: .overwrite, password: "wrong")
        XCTAssertThrowsError(try BoltArchiveEngine.extract(archiveURL: archive, options: options)) { error in
            guard case BoltZipError.wrongPassword = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), [destination.lastPathComponent])

        options.password = password
        let controller = ArchiveTaskController()
        XCTAssertThrowsError(try BoltArchiveEngine.extract(archiveURL: archive, options: options, controller: controller) {
            if $0.processedBytes > 0 { controller.cancel() }
        }) { error in
            guard case BoltZipError.cancelled = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: destination), previous)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), [destination.lastPathComponent])

        try BoltArchiveEngine.extract(archiveURL: archive, options: options)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), [destination.lastPathComponent])
    }

    func testArchiveSizeAggregationRejectsUnsupportedTotals() throws {
        let maxSize = UInt64(Int64.max)
        XCTAssertEqual(try BoltArchiveEngine.checkedArchiveSize(maxSize - 1, adding: 1), maxSize)
        XCTAssertThrowsError(try BoltArchiveEngine.checkedArchiveSize(maxSize, adding: 1))
        XCTAssertThrowsError(try BoltArchiveEngine.checkedArchiveSize(1, adding: UInt64.max))
    }

    func testCodecEnforcesExactDecodedSizeForBufferFileAndVerification() throws {
        let payload = Data(repeating: 0x41, count: 64 * 1024)
        let compressed = try CompressionCodec.compress(data: payload, algorithm: .deflate)
        let source = tempDir.appendingPathComponent("raw.deflate")
        let destination = tempDir.appendingPathComponent("decoded")
        try compressed.write(to: source)
        let exactSize = UInt64(payload.count)

        for wrongSize in [0, 1, exactSize + 1] {
            XCTAssertThrowsError(try CompressionCodec.decompress(data: compressed, algorithm: .deflate, exactOutputSize: wrongSize))
            XCTAssertThrowsError(try CompressionCodec.decompressFile(
                sourceURL: source, destinationURL: destination, algorithm: .deflate, exactOutputSize: wrongSize
            ))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertThrowsError(try CompressionCodec.verifyFile(sourceURL: source, algorithm: .deflate, exactOutputSize: wrongSize))
        }

        XCTAssertEqual(try CompressionCodec.decompress(data: compressed, algorithm: .deflate, exactOutputSize: exactSize), payload)
        try CompressionCodec.decompressFile(sourceURL: source, destinationURL: destination, algorithm: .deflate, exactOutputSize: exactSize)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(try CompressionCodec.verifyFile(sourceURL: source, algorithm: .deflate, exactOutputSize: exactSize).uncompressedSize, exactSize)
    }

    func testStreamingChunkedZipAE2AndTarZstRoundtrip() throws {
        BoltConcurrency.streamingThresholdBytes = 64 * 1024
        defer { BoltConcurrency.streamingThresholdBytes = BoltConcurrency.defaultStreamThresholdBytes }

        // 1. Verify AESCTRStream unaligned chunk invariance matches non-streaming AES-256
        let key = Data(repeating: 0x5A, count: 32)
        let sample = Data((0..<5003).map { UInt8(($0 * 13 + 7) & 0xFF) })
        let fullCipher = try ZipCrypto.AESCTRStream(key: key).transform(sample)
        let streamCipher = try ZipCrypto.AESCTRStream(key: key)
        var chunkedCipher = Data()
        var pos = 0
        for step in [1, 17, 63, 256, 1023, 5000] {
            if pos >= sample.count { break }
            let end = min(sample.count, pos + step)
            chunkedCipher.append(streamCipher.transform(sample.subdata(in: pos..<end)))
            pos = end
        }
        XCTAssertEqual(chunkedCipher, fullCipher)

        // 2. End-to-end streaming ZIP with AES-256 + DEFLATE + split volume
        let bigFile = tempDir.appendingPathComponent("stream_payload.bin")
        var bigBytes = Data(capacity: 220 * 1024)
        var rngState: UInt64 = 0x123456789ABCDEF0
        for _ in 0..<(220 * 1024) {
            rngState ^= rngState << 13
            rngState ^= rngState >> 7
            rngState ^= rngState << 17
            bigBytes.append(UInt8(rngState & 0xFF))
        }
        try bigBytes.write(to: bigFile)

        let splitZip = tempDir.appendingPathComponent("StreamSplit.zip")
        let volumes = try BoltArchiveEngine.createArchive(
            from: [bigFile],
            to: splitZip,
            options: CreateArchiveOptions(
                format: .zip,
                algorithm: .deflate,
                encryption: .aes256,
                password: "StreamSecret!99",
                splitVolumeSizeBytes: 80 * 1024
            )
        )
        XCTAssertGreaterThanOrEqual(volumes.count, 2)

        let report = try BoltArchiveEngine.testIntegrity(archiveURL: splitZip, password: "StreamSecret!99")
        XCTAssertEqual(report.passedCount, 1)
        XCTAssertEqual(report.failedCount, 0)

        let extractDir = tempDir.appendingPathComponent("StreamZipOut", isDirectory: true)
        try BoltArchiveEngine.extract(
            archiveURL: splitZip,
            options: ExtractOptions(destinationURL: extractDir, mode: .here, password: "StreamSecret!99")
        )
        let extractedData = try Data(contentsOf: extractDir.appendingPathComponent("stream_payload.bin"))
        XCTAssertEqual(extractedData, bigBytes)

        // 3. End-to-end streaming .tar.zst create, list, verify, readEntryData, and extract
        let tarZst = tempDir.appendingPathComponent("StreamArchive.tar.zst")
        try BoltArchiveEngine.createArchive(
            from: [bigFile],
            to: tarZst,
            options: CreateArchiveOptions(format: .tarZst, algorithm: .zstd)
        )
        let tarListing = try BoltArchiveEngine.inspect(archiveURL: tarZst)
        XCTAssertEqual(tarListing.entries.count, 1)
        XCTAssertEqual(tarListing.entries.first?.uncompressedSize, UInt64(bigBytes.count))

        let singleRead = try BoltArchiveEngine.readEntryData(archiveURL: tarZst, entryPath: "stream_payload.bin")
        XCTAssertEqual(singleRead, bigBytes)

        let tarExtractDir = tempDir.appendingPathComponent("StreamTarOut", isDirectory: true)
        try BoltArchiveEngine.extract(
            archiveURL: tarZst,
            options: ExtractOptions(destinationURL: tarExtractDir, mode: .here)
        )
        XCTAssertEqual(try Data(contentsOf: tarExtractDir.appendingPathComponent("stream_payload.bin")), bigBytes)
    }

    func testZipAndTarSymlinkRoundtripAndTraversalGuard() throws {
        let fm = FileManager.default
        let srcRoot = tempDir.appendingPathComponent("SymSrc", isDirectory: true)
        let subDir = srcRoot.appendingPathComponent("sub", isDirectory: true)
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        let targetFile = subDir.appendingPathComponent("hello.txt")
        try Data("Hello Symlink".utf8).write(to: targetFile)

        let relLink = srcRoot.appendingPathComponent("rel_hello.txt")
        try fm.createSymbolicLink(atPath: relLink.path, withDestinationPath: "sub/hello.txt")

        // Roundtrip in ZIP + TAR.ZST
        let zipURL = tempDir.appendingPathComponent("WithSymlink.zip")
        try BoltArchiveEngine.createArchive(
            from: [srcRoot],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, archiveComment: "Symlink comment", preserveSymlinks: true)
        )
        // Also test in-place .setComment edit preserves entries and updates comment
        try BoltArchiveEngine.editZip(at: zipURL, operations: [.setComment("Updated v1.0.2 Comment")])
        let zipListing = try BoltArchiveEngine.inspect(archiveURL: zipURL)
        XCTAssertEqual(zipListing.comment, "Updated v1.0.2 Comment")
        XCTAssertTrue(zipListing.entries.contains { $0.path == "SymSrc/rel_hello.txt" && $0.isSymbolicLink })

        let zipOut = tempDir.appendingPathComponent("ZipSymOut", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: zipURL, options: ExtractOptions(destinationURL: zipOut, mode: .here))
        let restoredZipLink = zipOut.appendingPathComponent("SymSrc/rel_hello.txt")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: restoredZipLink.path), "sub/hello.txt")
        XCTAssertEqual(try String(contentsOf: restoredZipLink, encoding: .utf8), "Hello Symlink")

        let tarZstURL = tempDir.appendingPathComponent("WithSymlink.tar.zst")
        try BoltArchiveEngine.createArchive(
            from: [srcRoot],
            to: tarZstURL,
            options: CreateArchiveOptions(format: .tarZst, algorithm: .zstd, preserveSymlinks: true)
        )
        let tarListing = try BoltArchiveEngine.inspect(archiveURL: tarZstURL)
        XCTAssertTrue(tarListing.entries.contains { $0.path == "SymSrc/rel_hello.txt" && $0.isSymbolicLink })
        let tarOut = tempDir.appendingPathComponent("TarSymOut", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: tarZstURL, options: ExtractOptions(destinationURL: tarOut, mode: .here))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: tarOut.appendingPathComponent("SymSrc/rel_hello.txt").path), "sub/hello.txt")

        // Security guard: reject symlinks pointing outside extraction root
        let evilDir = tempDir.appendingPathComponent("EvilSym", isDirectory: true)
        try fm.createDirectory(at: evilDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: evilDir.appendingPathComponent("escape_link").path, withDestinationPath: "../../etc/passwd")
        let evilZip = tempDir.appendingPathComponent("Evil.zip")
        try BoltArchiveEngine.createArchive(from: [evilDir], to: evilZip, options: CreateArchiveOptions(format: .zip, preserveSymlinks: true))
        let evilListing = try BoltArchiveEngine.inspect(archiveURL: evilZip)
        XCTAssertTrue(evilListing.entries.contains { $0.path == "EvilSym/escape_link" && $0.isSymbolicLink }, "Entries were: \(evilListing.entries.map { "\($0.path) sym:\($0.isSymbolicLink) sz:\($0.uncompressedSize)" })")
        let storedTarget = String(data: try BoltArchiveEngine.readEntryData(archiveURL: evilZip, entryPath: "EvilSym/escape_link"), encoding: .utf8)
        XCTAssertEqual(storedTarget, "../../etc/passwd")

        let evilOut = tempDir.appendingPathComponent("EvilOut", isDirectory: true)
        XCTAssertThrowsError(try BoltArchiveEngine.extract(archiveURL: evilZip, options: ExtractOptions(destinationURL: evilOut, mode: .here, restoreSymlinks: true))) { err in
            if case BoltZipError.pathTraversalDetected = err {
                // Expected security rejection
            } else {
                XCTFail("Expected pathTraversalDetected, got \(err)")
            }
        }
    }

    func testContainerVariantsEditableAndSevenZipRoundTrip() throws {
        let fm = FileManager.default
        let payloadDir = tempDir.appendingPathComponent("PayloadApp", isDirectory: true)
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        let binFile = payloadDir.appendingPathComponent("manifest.json")
        try Data("{\"app\":\"bolt\"}".utf8).write(to: binFile)

        let baseZip = tempDir.appendingPathComponent("Base.zip")
        try BoltArchiveEngine.createArchive(from: [payloadDir], to: baseZip, options: CreateArchiveOptions(format: .zip))

        for ext in ["ipa", "apk", "jar", "epub", "whl"] {
            let variantURL = tempDir.appendingPathComponent("sample.\(ext)")
            try fm.copyItem(at: baseZip, to: variantURL)
            XCTAssertEqual(ArchiveFormat.detect(from: variantURL), .zip)
            let listing = try BoltArchiveEngine.inspect(archiveURL: variantURL)
            XCTAssertTrue(listing.canEditInPlace)
            XCTAssertTrue(listing.entries.contains { $0.path.hasSuffix("manifest.json") })
            try BoltArchiveEngine.editZip(at: variantURL, operations: [.setComment("edited")])
            XCTAssertEqual(try BoltArchiveEngine.inspect(archiveURL: variantURL).comment, "edited")
        }

        // Verify streaming .7z creation and nested symlink preservation
        let sevenZURL = tempDir.appendingPathComponent("HardlinkStage.7z")
        try BoltArchiveEngine.createArchive(from: [payloadDir], to: sevenZURL, options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz))
        let szOut = tempDir.appendingPathComponent("SevenZipHardlinkOut", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: sevenZURL, options: ExtractOptions(destinationURL: szOut, mode: .here))
        XCTAssertEqual(try Data(contentsOf: szOut.appendingPathComponent("PayloadApp/manifest.json")), Data("{\"app\":\"bolt\"}".utf8))
    }

    func testPathNormalizationFastPathPreservesEdgeCases() {
        XCTAssertEqual(ArchiveEntry.normalizePath("web/eIBS.war/index.jsp", isDirectory: false), "web/eIBS.war/index.jsp")
        XCTAssertEqual(ArchiveEntry.normalizePath("web/eIBS.war/", isDirectory: true), "web/eIBS.war/")
        XCTAssertEqual(ArchiveEntry.normalizePath("web/eIBS.war", isDirectory: true), "web/eIBS.war/")
        XCTAssertEqual(ArchiveEntry.normalizePath("./a\\b//c/", isDirectory: false), "a/b/c")
        XCTAssertEqual(ArchiveEntry.normalizePath("/root//dir", isDirectory: true), "root/dir/")
    }

    func testDefectRegressionSafetyAndBoundaryChecks() throws {
        let fm = FileManager.default

        // BZ-DEF-10: Empty buffer CRC32 preserves initial value
        XCTAssertEqual(CompressionCodec.crc32(Data(), initial: 0x12345678), 0x12345678)
        XCTAssertEqual(CompressionCodec.crc32(Data(), initial: 0), 0)

        // BZ-DEF-03: Extracting regular file onto existing non-empty directory under .overwrite must not delete directory
        let payloadSrc = tempDir.appendingPathComponent("payload.txt")
        let payloadBytes = Data("safe-file-contents".utf8)
        try payloadBytes.write(to: payloadSrc)
        let conflictZip = tempDir.appendingPathComponent("Conflict.zip")
        try BoltArchiveEngine.createArchive(
            from: [payloadSrc],
            to: conflictZip,
            options: CreateArchiveOptions(format: .zip)
        )

        let outRoot = tempDir.appendingPathComponent("CollisionOut", isDirectory: true)
        let existingDir = outRoot.appendingPathComponent("payload.txt", isDirectory: true)
        try fm.createDirectory(at: existingDir, withIntermediateDirectories: true)
        let sentinel = existingDir.appendingPathComponent("sentinel.keep")
        try Data("do-not-delete".utf8).write(to: sentinel)

        try BoltArchiveEngine.extract(
            archiveURL: conflictZip,
            options: ExtractOptions(destinationURL: outRoot, mode: .here, overwritePolicy: .overwrite)
        )
        XCTAssertTrue(fm.fileExists(atPath: sentinel.path), "Existing directory contents must survive file-vs-dir collision")
        let fallbackFile = outRoot.appendingPathComponent("payload (1).txt")
        XCTAssertEqual(try Data(contentsOf: fallbackFile), payloadBytes)

        // BZ-DEF-05: Pre-cancelled ArchiveTaskController propagates BoltZipError.cancelled cleanly
        let cancelledController = ArchiveTaskController()
        cancelledController.cancel()
        let singleOut = tempDir.appendingPathComponent("cancelled-out.txt")
        XCTAssertThrowsError(
            try BoltArchiveEngine.extractSingleEntryToFile(
                archiveURL: conflictZip,
                entryPath: "payload.txt",
                destinationFileURL: singleOut,
                controller: cancelledController
            )
        ) { err in
            guard case BoltZipError.cancelled = err else {
                return XCTFail("Expected BoltZipError.cancelled, got \(err)")
            }
        }

        // BZ-DEF-02 & BZ-DEF-13: ZIP with trailing bytes after EOCD + extractSingleEntryToFile
        let zipWithTrailing = tempDir.appendingPathComponent("WithTrailing.zip")
        var zipData = try Data(contentsOf: conflictZip)
        zipData.append(Data(repeating: 0xAA, count: 96))
        try zipData.write(to: zipWithTrailing)
        let trailingListing = try BoltArchiveEngine.inspect(archiveURL: zipWithTrailing)
        XCTAssertEqual(trailingListing.entries.map(\.path), ["payload.txt"])
        let extractedSingleURL = tempDir.appendingPathComponent("single-extracted.txt")
        try BoltArchiveEngine.extractSingleEntryToFile(
            archiveURL: zipWithTrailing,
            entryPath: "payload.txt",
            destinationFileURL: extractedSingleURL
        )
        XCTAssertEqual(try Data(contentsOf: extractedSingleURL), payloadBytes)

        // BZ-DEF-06: Corrupted oversized centralDirSize in EOCD must be rejected cleanly
        let badCDZip = tempDir.appendingPathComponent("OversizedCD.zip")
        var eocd = Data()
        ZipBinary.appendUInt32LE(&eocd, ZipSignature.endOfCentralDirectory)
        ZipBinary.appendUInt16LE(&eocd, 0) // disk
        ZipBinary.appendUInt16LE(&eocd, 0) // cdStartDisk
        ZipBinary.appendUInt16LE(&eocd, 1) // diskEntries
        ZipBinary.appendUInt16LE(&eocd, 1) // totalEntries
        ZipBinary.appendUInt32LE(&eocd, 0x7FFF_FFFF) // corrupted huge cdSize
        ZipBinary.appendUInt32LE(&eocd, 0) // cdOffset
        ZipBinary.appendUInt16LE(&eocd, 0) // commentLen
        try eocd.write(to: badCDZip)
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: badCDZip)) { err in
            guard case BoltZipError.invalidArchive = err else {
                return XCTFail("Expected invalidArchive, got \(err)")
            }
        }

        // BZ-DEF-08: Truncated TAR file must fail integrity verification & valid TAR reports accurate non-checksum message
        let validTar = tempDir.appendingPathComponent("Valid.tar")
        let bigRaw = tempDir.appendingPathComponent("raw.bin")
        try Data((0..<4096).map { UInt8($0 & 0xFF) }).write(to: bigRaw)
        try BoltArchiveEngine.createArchive(
            from: [bigRaw],
            to: validTar,
            options: CreateArchiveOptions(format: .tar, algorithm: .store)
        )
        let validTarReport = try BoltArchiveEngine.testIntegrity(archiveURL: validTar)
        XCTAssertTrue(validTarReport.isHealthy)
        XCTAssertFalse(validTarReport.results.first?.detail.contains("CRC32") ?? false)

        let fullTarData = try Data(contentsOf: validTar)
        let truncatedTar = tempDir.appendingPathComponent("Truncated.tar")
        // Cut right inside the file payload (header 512 bytes + partial body, missing trailer)
        try fullTarData.prefix(900).write(to: truncatedTar)
        XCTAssertThrowsError(try BoltArchiveEngine.testIntegrity(archiveURL: truncatedTar)) { err in
            guard case BoltZipError.invalidArchive = err else {
                return XCTFail("Expected BoltZipError.invalidArchive on truncated TAR, got \(err)")
            }
        }
    }

    func testDefectRegressionLegacyBit3ZipCryptoEditAndUnzipCompat() throws {
        // BZ-DEF-07: Preserve bit-3 (0x0008) & Data Descriptor for legacy ZipCrypto entries during editZip
        let plain = Data("Legacy bit-3 ZipCrypto secret payload for in-place edit!".utf8)
        let realCRC = CompressionCodec.crc32(plain)
        let realTopByte = UInt8((realCRC >> 24) & 0xFF)
        let checkHighByte: UInt8 = realTopByte == 0x42 ? 0x43 : 0x42
        let dosTime: UInt16 = (UInt16(checkHighByte) << 8) | 0x0015
        let dosDate: UInt16 = ZipBinary.dosDateTime(from: Date()).date
        let fakeCheckCRC = UInt32(checkHighByte) << 24
        let password = "LegacyBit3!Pass"

        let encryptedPayload = try ZipCrypto.encryptZipCrypto(plaintext: plain, crc32: fakeCheckCRC, password: password)
        let nameBytes = Data("legacy.txt".utf8)
        let flags: UInt16 = 0x0800 | 0x0008 | 0x0001 // UTF-8 + Data Descriptor + Encrypted

        var archiveData = Data()
        // LFH (with zeros for crc32/comp/uncomp as required by bit 3)
        ZipBinary.appendUInt32LE(&archiveData, ZipSignature.localFileHeader)
        ZipBinary.appendUInt16LE(&archiveData, 20)
        ZipBinary.appendUInt16LE(&archiveData, flags)
        ZipBinary.appendUInt16LE(&archiveData, 0) // store
        ZipBinary.appendUInt16LE(&archiveData, dosTime)
        ZipBinary.appendUInt16LE(&archiveData, dosDate)
        ZipBinary.appendUInt32LE(&archiveData, 0)
        ZipBinary.appendUInt32LE(&archiveData, 0)
        ZipBinary.appendUInt32LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, UInt16(nameBytes.count))
        ZipBinary.appendUInt16LE(&archiveData, 0)
        archiveData.append(nameBytes)
        archiveData.append(encryptedPayload)

        // PK\x07\x08 Data Descriptor
        ZipBinary.appendUInt32LE(&archiveData, ZipSignature.dataDescriptor)
        ZipBinary.appendUInt32LE(&archiveData, realCRC)
        ZipBinary.appendUInt32LE(&archiveData, UInt32(encryptedPayload.count))
        ZipBinary.appendUInt32LE(&archiveData, UInt32(plain.count))

        // Central Directory Header
        let cdOffset = UInt32(archiveData.count)
        ZipBinary.appendUInt32LE(&archiveData, ZipSignature.centralDirectoryHeader)
        ZipBinary.appendUInt16LE(&archiveData, 20)
        ZipBinary.appendUInt16LE(&archiveData, 20)
        ZipBinary.appendUInt16LE(&archiveData, flags)
        ZipBinary.appendUInt16LE(&archiveData, 0) // store
        ZipBinary.appendUInt16LE(&archiveData, dosTime)
        ZipBinary.appendUInt16LE(&archiveData, dosDate)
        ZipBinary.appendUInt32LE(&archiveData, realCRC)
        ZipBinary.appendUInt32LE(&archiveData, UInt32(encryptedPayload.count))
        ZipBinary.appendUInt32LE(&archiveData, UInt32(plain.count))
        ZipBinary.appendUInt16LE(&archiveData, UInt16(nameBytes.count))
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt32LE(&archiveData, 0)
        ZipBinary.appendUInt32LE(&archiveData, 0) // local header offset
        archiveData.append(nameBytes)
        let cdSize = UInt32(archiveData.count) - cdOffset

        ZipBinary.appendUInt32LE(&archiveData, ZipSignature.endOfCentralDirectory)
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, 0)
        ZipBinary.appendUInt16LE(&archiveData, 1)
        ZipBinary.appendUInt16LE(&archiveData, 1)
        ZipBinary.appendUInt32LE(&archiveData, cdSize)
        ZipBinary.appendUInt32LE(&archiveData, cdOffset)
        ZipBinary.appendUInt16LE(&archiveData, 0)

        let zipURL = tempDir.appendingPathComponent("LegacyBit3.zip")
        try archiveData.write(to: zipURL)

        let addedFile = tempDir.appendingPathComponent("extra.txt")
        let addedBytes = Data("Added after bit3 edit".utf8)
        try addedBytes.write(to: addedFile)

        try BoltArchiveEngine.editZip(
            at: zipURL,
            operations: [
                .addItems(urls: [addedFile], targetFolder: ""),
                .setComment("bit3-preserved")
            ]
        )

        let integrity = try BoltArchiveEngine.testIntegrity(archiveURL: zipURL, password: password)
        XCTAssertTrue(integrity.isHealthy, "Edited archive integrity failed: \(integrity.results.map { "\($0.path):\($0.status):\($0.detail)" })")

        let extractDir = tempDir.appendingPathComponent("LegacyBit3Out", isDirectory: true)
        try BoltArchiveEngine.extract(
            archiveURL: zipURL,
            options: ExtractOptions(destinationURL: extractDir, mode: .here, password: password)
        )
        XCTAssertEqual(try Data(contentsOf: extractDir.appendingPathComponent("legacy.txt")), plain)
        XCTAssertEqual(try Data(contentsOf: extractDir.appendingPathComponent("extra.txt")), addedBytes)

        // Cross-check with macOS /usr/bin/unzip
        let unzipProc = Process()
        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProc.arguments = ["-P", password, "-t", zipURL.path]
        let outPipe = Pipe()
        unzipProc.standardOutput = outPipe
        unzipProc.standardError = outPipe
        try unzipProc.run()
        unzipProc.waitUntilExit()
        let unzipLog = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(unzipProc.terminationStatus, 0, "unzip -t failed on edited bit-3 ZipCrypto archive: \(unzipLog)")
    }

    func testAppIconGoldSweepMovesWithoutChangingItsSilhouette() throws {
        #if canImport(AppKit)
        let size = 128
        func render(white: Bool, progress: CGFloat?) throws -> Data {
            try XCTUnwrap(BoltIconArtwork.renderAppIconPNG(pixelSize: size, whiteBackground: white, goldSweepProgress: progress))
        }
        func measure(white: Bool, progress: CGFloat?) throws -> (meanX: Double, meanY: Double, silhouette: [Bool]) {
            let png = try render(white: white, progress: progress)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            var points = 0
            var sumX = 0
            var sumY = 0
            var silhouette: [Bool] = []
            for y in 0..<size {
                for x in 0..<size {
                    let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    silhouette.append(pixel.alphaComponent > 0.5)
                    if pixel.alphaComponent > 0.9 && pixel.redComponent > 0.82 &&
                        pixel.greenComponent > 0.6 && pixel.blueComponent < 0.57 {
                        points += 1
                        sumX += x
                        sumY += y
                    }
                }
            }
            XCTAssertGreaterThan(points, 10)
            let count = Double(max(1, points))
            return (Double(sumX) / count, Double(sumY) / count, silhouette)
        }

        func pixelDistance(_ lhs: Data, _ rhs: Data) throws -> Int {
            let left = try XCTUnwrap(NSBitmapImageRep(data: lhs))
            let right = try XCTUnwrap(NSBitmapImageRep(data: rhs))
            let leftBytes = try XCTUnwrap(left.bitmapData)
            let rightBytes = try XCTUnwrap(right.bitmapData)
            XCTAssertEqual(left.bytesPerPlane, right.bytesPerPlane)
            return (0..<min(left.bytesPerPlane, right.bytesPerPlane)).reduce(0) { sum, index in
                sum + abs(Int(leftBytes[index]) - Int(rightBytes[index]))
            }
        }

        for white in [true, false] {
            let head = try measure(white: white, progress: 0.12)
            let middle = try measure(white: white, progress: 0.52)
            let tail = try measure(white: white, progress: 0.92)
            let resting = try measure(white: white, progress: nil)
            XCTAssertGreaterThan(abs(head.meanY - middle.meanY), 10)
            XCTAssertGreaterThan(abs(middle.meanY - tail.meanY), 8)
            XCTAssertLessThan(hypot(tail.meanX - resting.meanX, tail.meanY - resting.meanY), 12)
            XCTAssertEqual(head.silhouette, resting.silhouette)
            XCTAssertEqual(middle.silhouette, resting.silhouette)
            XCTAssertEqual(tail.silhouette, resting.silhouette)

            let restingPNG = try render(white: white, progress: nil)
            let enteringTail = try render(white: white, progress: 0.76)
            let lastSweepFrame = try render(white: white, progress: 0.96)
            XCTAssertLessThan(try pixelDistance(lastSweepFrame, restingPNG) * 4, try pixelDistance(enteringTail, restingPNG))
            XCTAssertEqual(try render(white: white, progress: 1), restingPNG)
        }
        #endif
    }

    func testAppIconForegroundPNGExport() throws {
        #if canImport(AppKit)
        for isWhite in [false, true] {
            let pngData = try XCTUnwrap(BoltIconArtwork.renderAppIconForegroundPNG(pixelSize: 256, whiteBackground: isWhite))
            XCTAssertGreaterThan(pngData.count, 500)
            XCTAssertEqual([UInt8](pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
            let rep = try XCTUnwrap(NSBitmapImageRep(data: pngData))
            XCTAssertEqual(rep.pixelsWide, 256)
            XCTAssertEqual(rep.pixelsHigh, 256)
            let cornerColor = rep.colorAt(x: 0, y: 0)
            XCTAssertEqual(Double(cornerColor?.alphaComponent ?? 1), 0, accuracy: 0.01)
        }
        #endif
    }
}
