import Foundation
import XCTest
@testable import BoltZipCore

final class CompressionProfileAndConversionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipProfiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCompressionProfilePersistenceNeverStoresPasswordsAndSanitizesOptions() throws {
        let store = CompressionProfileStore(directoryURL: root)
        let first = CompressionProfile(
            name: "Work Backup",
            format: .sevenZip,
            algorithm: .xz,
            level: 99, // clamped to 9
            encryption: .zipCrypto, // sanitized to .aes256 for 7z
            encryptFileNames: true,
            splitVolumeSizeBytes: 1024, // < 64KiB sanitized to nil
            excludeMacJunk: true,
            excludePatterns: ["*.tmp", "  .git/ ", ""],
            preserveSymlinks: false,
            namingTemplate: "{name}_{date}",
            isDefaultQuickPreset: true
        )
        let second = CompressionProfile(
            name: "Fast Tar",
            format: .tarZst,
            algorithm: .deflate, // sanitized to .zstd
            level: 5,
            encryption: .aes256, // stripped for tarZst
            namingTemplate: "../escape/test",
            isDefaultQuickPreset: true // supersedes first as quick default
        )

        try store.save([first, second])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)

        XCTAssertEqual(loaded[0].level, 9)
        XCTAssertEqual(loaded[0].encryption, .aes256)
        XCTAssertNil(loaded[0].splitVolumeSizeBytes)
        XCTAssertEqual(loaded[0].excludePatterns, ["*.tmp", ".git"])
        XCTAssertFalse(loaded[0].isDefaultQuickPreset)

        XCTAssertEqual(loaded[1].algorithm, .zstd)
        XCTAssertEqual(loaded[1].encryption, .none)
        XCTAssertTrue(loaded[1].isDefaultQuickPreset)
        XCTAssertFalse(loaded[1].namingTemplate.contains("/"))

        let jsonText = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(jsonText.lowercased().contains("password"))

        let opts = CreateArchiveOptions(profile: loaded[0], password: nil)
        XCTAssertEqual(opts.encryption, .none)
        XCTAssertFalse(opts.encryptFileNames)
        XCTAssertEqual(opts.excludePatterns, ["*.tmp", ".git"])

        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let rendered = loaded[0].resolveOutputURL(
            for: [root.appendingPathComponent("Report.txt")],
            in: root,
            deduplicating: false,
            date: date
        )
        XCTAssertTrue(rendered.lastPathComponent.hasPrefix("Report_2025-"))
        XCTAssertTrue(rendered.lastPathComponent.hasSuffix(".7z"))

        XCTAssertEqual(store.defaultQuickPreset()?.name, "Fast Tar")
        XCTAssertTrue(try store.delete(named: "Fast Tar"))
        XCTAssertEqual(store.load().count, 1)
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

    func testBatchFormatConversionSupportsEncryptedAndSplitArchivesWithoutMutatingSources() throws {
        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        let subDir = srcDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let bodyA = Data(repeating: 0x41, count: 90_000)
        let bodyB = Data("nested conversion payload\n".utf8)
        try bodyA.write(to: srcDir.appendingPathComponent("big.bin"))
        try bodyB.write(to: subDir.appendingPathComponent("readme.md"))
        try FileManager.default.createSymbolicLink(atPath: srcDir.appendingPathComponent("alias.md").path, withDestinationPath: "sub/readme.md")

        let plainZip = root.appendingPathComponent("plain.zip")
        try BoltArchiveEngine.createArchive(from: [srcDir], to: plainZip, options: CreateArchiveOptions(format: .zip, algorithm: .deflate))

        let enc7z = root.appendingPathComponent("secret.7z")
        try BoltArchiveEngine.createArchive(
            from: [srcDir],
            to: enc7z,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, encryption: .aes256, password: "pw7", encryptFileNames: true)
        )

        let split7zBase = root.appendingPathComponent("split.7z")
        let splitVols = try BoltArchiveEngine.createArchive(
            from: [srcDir],
            to: split7zBase,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65536)
        )
        let splitFirst = try XCTUnwrap(splitVols.first)

        let beforePlainZip = try Data(contentsOf: plainZip)
        let beforeEnc7z = try Data(contentsOf: enc7z)

        let outDir = root.appendingPathComponent("converted", isDirectory: true)
        final class RetryAttemptBox: @unchecked Sendable {
            var count = 0
        }
        let retries = RetryAttemptBox()

        let targetOpts = CreateArchiveOptions(
            format: .zip,
            algorithm: .zstd,
            level: 3,
            encryption: .aes256,
            password: "newpw",
            preserveSymlinks: true
        )
        let report = try BoltArchiveEngine.convertArchives(
            sources: [plainZip, enc7z, splitFirst],
            destinationDirectory: outDir,
            options: targetOpts,
            sourcePasswordProvider: { url, isWrong in
                guard url == enc7z else { return nil }
                retries.count += 1
                return isWrong ? "pw7" : "wrong_first"
            },
            overwritePolicy: .rename,
            namingTemplate: "{name}_cv"
        )

        XCTAssertTrue(report.isAllHealthy)
        XCTAssertEqual(report.succeededCount, 3)
        XCTAssertEqual(retries.count, 2)

        // Sources untouched
        XCTAssertEqual(try Data(contentsOf: plainZip), beforePlainZip)
        XCTAssertEqual(try Data(contentsOf: enc7z), beforeEnc7z)

        // Converted archives valid, encrypted with target password, and preserve symlink
        for item in report.results {
            let dest = try XCTUnwrap(item.destinationURLs.first)
            XCTAssertTrue(dest.lastPathComponent.hasSuffix("_cv.zip"))
            let listing = try BoltArchiveEngine.inspect(archiveURL: dest)
            XCTAssertEqual(listing.format, .zip)
            XCTAssertTrue(listing.entries.contains { $0.path == "src/sub/readme.md" })
            XCTAssertTrue(listing.entries.contains { $0.path == "src/alias.md" && $0.isSymbolicLink })
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: dest, entryPath: "src/sub/readme.md", password: "newpw"), bodyB)
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: dest, entryPath: "src/big.bin", password: "newpw"), bodyA)
        }
    }

    func testGzipFNameTraversalSanitizedAndProfileUpsertReturnsResolvedID() throws {
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

        // Verify CompressionProfileStore.upsert returns canonical existing ID on name match
        let store = CompressionProfileStore(directoryURL: root.appendingPathComponent("store_id"))
        let first = try store.upsert(CompressionProfile(name: "Daily", format: .zip, algorithm: .deflate))
        let updated = try store.upsert(CompressionProfile(name: "daily", format: .sevenZip, algorithm: .xz))
        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(store.load().count, 1)

        // Verify testIntegrityBatch with per-archive passwordProvider
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
            password: nil,
            passwordProvider: { url in url == encA ? "alpha" : nil }
        )
        XCTAssertTrue(batchReport.isHealthy)
        XCTAssertEqual(batchReport.passedCount, 1)
    }
}
