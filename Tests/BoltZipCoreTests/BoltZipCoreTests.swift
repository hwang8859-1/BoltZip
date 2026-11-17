@testable import BoltZipCore
import Foundation
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
}
