import Foundation
import XCTest
@testable import BoltZipCore

final class StandaloneStreamAndExclusionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipStreamTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testExcludeRulesFilterDirectoriesAndFilesAcrossFormats() throws {
        let project = root.appendingPathComponent("Project", isDirectory: true)
        let gitDir = project.appendingPathComponent(".git", isDirectory: true)
        let nodeDir = project.appendingPathComponent("node_modules/pkg", isDirectory: true)
        let docsDir = project.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        try Data("keep".utf8).write(to: project.appendingPathComponent("main.swift"))
        try Data("junk".utf8).write(to: project.appendingPathComponent("scratch.tmp"))
        try Data("git".utf8).write(to: gitDir.appendingPathComponent("config"))
        try Data("mod".utf8).write(to: nodeDir.appendingPathComponent("index.js"))
        try Data("doc".utf8).write(to: docsDir.appendingPathComponent("guide.md"))
        try Data("bak".utf8).write(to: docsDir.appendingPathComponent("guide.bak"))
        try Data("ds".utf8).write(to: project.appendingPathComponent(".DS_Store"))

        for format in [ArchiveFormat.zip, .tarZst, .sevenZip] {
            let outURL = root.appendingPathComponent("filtered.\(format.fileExtension)")
            let opts = CreateArchiveOptions(
                format: format,
                algorithm: format.defaultAlgorithm,
                excludeMacJunk: true,
                excludePatterns: ["*.tmp", ".git", "node_modules", "docs/*.bak"]
            )
            try BoltArchiveEngine.createArchive(from: [project], to: outURL, options: opts)
            let listing = try BoltArchiveEngine.inspect(archiveURL: outURL)
            let paths = Set(listing.entries.map(\.path))
            XCTAssertTrue(paths.contains("Project/main.swift"), format.rawValue)
            XCTAssertTrue(paths.contains("Project/docs/guide.md"), format.rawValue)
            XCTAssertFalse(paths.contains("Project/scratch.tmp"), format.rawValue)
            XCTAssertFalse(paths.contains("Project/.git/config"), format.rawValue)
            XCTAssertFalse(paths.contains("Project/node_modules/pkg/index.js"), format.rawValue)
            XCTAssertFalse(paths.contains("Project/docs/guide.bak"), format.rawValue)
            XCTAssertFalse(paths.contains("Project/.DS_Store"), format.rawValue)
        }
    }

    func testStandaloneGzipAndXzCreationPreservesGzipFilenameAndRejectsInvalidInputs() throws {
        let payload = Data("Standalone single-stream content 🚀\n".utf8)
        let input = root.appendingPathComponent("notes.txt")
        let second = root.appendingPathComponent("extra.txt")
        let folder = root.appendingPathComponent("dir", isDirectory: true)
        let link = root.appendingPathComponent("link.txt")
        try payload.write(to: input)
        try Data("extra".utf8).write(to: second)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "notes.txt")

        // Valid .gz creation preserves FNAME even if outer .gz is renamed
        let gzOut = root.appendingPathComponent("custom_archive.gz")
        try BoltArchiveEngine.createArchive(
            from: [input],
            to: gzOut,
            options: CreateArchiveOptions(format: .gz, algorithm: .deflate, level: 6)
        )
        let gzListing = try BoltArchiveEngine.inspect(archiveURL: gzOut)
        XCTAssertEqual(gzListing.format, .gz)
        XCTAssertEqual(gzListing.entries.first?.path, "notes.txt")
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: gzOut, entryPath: "notes.txt"), payload)
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: gzOut).isHealthy)

        let gzExtractDir = root.appendingPathComponent("out_gz", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: gzOut, options: ExtractOptions(destinationURL: gzExtractDir, mode: .here))
        XCTAssertEqual(try Data(contentsOf: gzExtractDir.appendingPathComponent("notes.txt")), payload)

        // Valid .xz creation
        let xzOut = root.appendingPathComponent("notes.txt.xz")
        try BoltArchiveEngine.createArchive(
            from: [input],
            to: xzOut,
            options: CreateArchiveOptions(format: .xz, algorithm: .xz, level: 4)
        )
        let xzListing = try BoltArchiveEngine.inspect(archiveURL: xzOut)
        XCTAssertEqual(xzListing.format, .xz)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: xzOut, entryPath: XCTUnwrap(xzListing.entries.first).path), payload)
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: xzOut).isHealthy)

        // Invalid inputs for standalone streams must fail cleanly without creating output files
        for fmt in [ArchiveFormat.gz, .xz] {
            for badInputs in [[input, second], [folder], [link], []] {
                let badOut = root.appendingPathComponent("bad-\(UUID().uuidString).\(fmt.fileExtension)")
                XCTAssertThrowsError(try BoltArchiveEngine.createArchive(
                    from: badInputs,
                    to: badOut,
                    options: CreateArchiveOptions(format: fmt, algorithm: fmt.defaultAlgorithm)
                ))
                XCTAssertFalse(FileManager.default.fileExists(atPath: badOut.path))
            }
        }
    }

    func testGzipFNameTraversalSanitized() throws {
        // Craft a malicious .gz header with FNAME = "../../evil/secret.txt"
        let gzPayload = try CompressionCodec.compress(data: Data("safe-gzip".utf8), algorithm: .deflate, gzipContainer: true)
        var maliciousGZ = Data([0x1F, 0x8B, 0x08, 0x08, 0, 0, 0, 0, 0, 0x03])
        maliciousGZ.append(Data("../../evil/secret.txt\0".utf8))
        maliciousGZ.append(gzPayload.dropFirst(10))

        let malURL = root.appendingPathComponent("untrusted.gz")
        try maliciousGZ.write(to: malURL)

        let entries = try BoltArchiveEngine.inspect(archiveURL: malURL).entries
        XCTAssertEqual(entries.first?.path, "secret.txt")

        let outDir = root.appendingPathComponent("gz_safe_out", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: malURL, options: ExtractOptions(destinationURL: outDir, mode: .here))
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("secret.txt")), Data("safe-gzip".utf8))
    }

    func testOutputNamingAndVolumeDeduplication() throws {
        let singleFile = root.appendingPathComponent("Report.2026.docx")
        try Data("doc".utf8).write(to: singleFile)
        XCTAssertEqual(BoltArchiveEngine.defaultBaseStem(for: [singleFile], format: .zip), "Report.2026")

        let outA = BoltArchiveEngine.makeOutputURL(stem: "Archive", format: .zip, in: root, deduplicating: true)
        XCTAssertEqual(outA.lastPathComponent, "Archive.zip")
        try Data("a".utf8).write(to: outA)

        let outB = BoltArchiveEngine.makeOutputURL(stem: "Archive", format: .zip, in: root, deduplicating: true)
        XCTAssertEqual(outB.lastPathComponent, "Archive (1).zip")

        let split7z = BoltArchiveEngine.makeOutputURL(stem: "SplitArchive", format: .sevenZip, splitVolumeSizeBytes: 65536, in: root, deduplicating: true)
        XCTAssertEqual(split7z.lastPathComponent, "SplitArchive.7z.001")
    }

    func testIntegrityBatch() throws {
        let secFile = root.appendingPathComponent("b.txt")
        try Data("batch-secret".utf8).write(to: secFile)
        let encA = root.appendingPathComponent("a_enc.zip")
        try BoltArchiveEngine.createArchive(
            from: [secFile],
            to: encA,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encryption: .aes256, password: "alpha")
        )
        let batchReport = BoltArchiveEngine.testIntegrityBatch(
            archiveURLs: [encA],
            password: "alpha",
            passwordProvider: nil
        )
        XCTAssertTrue(batchReport.isHealthy)
        XCTAssertEqual(batchReport.passedCount, 1)
    }
}
