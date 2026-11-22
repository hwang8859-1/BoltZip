import Foundation
import XCTest
@testable import BoltZipCore

final class ZipRecoveryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRecoverZipSavesVerifiedEntriesWhenPayloadCorruptedAndLeavesOriginalIntact() throws {
        let folder = root.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let goodText = Data("Intact plain text content for recovery verification!\n".utf8)
        let corruptPayload = Data(repeating: 0x5A, count: 4096)
        try goodText.write(to: folder.appendingPathComponent("good.txt"))
        try corruptPayload.write(to: folder.appendingPathComponent("broken.bin"))

        let sourceZip = root.appendingPathComponent("damaged.zip")
        try BoltArchiveEngine.createArchive(
            from: [folder],
            to: sourceZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        // Corrupt bytes inside broken.bin payload without breaking Central Directory
        var bytes = try Data(contentsOf: sourceZip)
        let reader = ZipReader(url: sourceZip)
        let parsed = try reader.parseArchive()
        let brokenRecord = try XCTUnwrap(parsed.records.first {
            ZipReader.makeEntry(from: $0, encoding: .auto).path.hasSuffix("broken.bin")
        })
        let flipPos = Int(brokenRecord.localHeaderOffset) + 60
        XCTAssertLessThan(flipPos, bytes.count)
        bytes[flipPos] ^= 0xFF
        bytes[flipPos + 1] ^= 0xAA
        try bytes.write(to: sourceZip)
        let damagedSnapshot = try Data(contentsOf: sourceZip)

        let recoveredURL = root.appendingPathComponent("repaired.zip")
        let report = try BoltArchiveEngine.recoverZip(at: sourceZip, to: recoveredURL)

        XCTAssertFalse(report.usedLocalHeaderFallbackScan)
        XCTAssertEqual(report.recoveredArchiveURL?.standardizedFileURL, recoveredURL.standardizedFileURL)
        XCTAssertTrue(report.recoveredEntries.contains { $0.path == "bundle/good.txt" })
        XCTAssertEqual(report.unrecoverableEntries.count, 1)
        XCTAssertEqual(report.unrecoverableEntries.first?.entryPath, "bundle/broken.bin")
        XCTAssertFalse(report.unrecoverableEntries.first?.reason.isEmpty ?? true)

        // Original damaged archive untouched
        XCTAssertEqual(try Data(contentsOf: sourceZip), damagedSnapshot)

        // Repaired archive opens cleanly, passes integrity, and restores good.txt
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: recoveredURL).isHealthy)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: recoveredURL, entryPath: "bundle/good.txt"), goodText)
    }

    func testRecoverZipUsesLocalHeaderFallbackScanWhenEOCDAndCentralDirectoryTruncated() throws {
        let a = root.appendingPathComponent("alpha.txt")
        let b = root.appendingPathComponent("beta.txt")
        let goodA = Data(String(repeating: "Alpha intact record line.\n", count: 40).utf8)
        let goodB = Data(String(repeating: "Beta intact record line.\n", count: 40).utf8)
        try goodA.write(to: a)
        try goodB.write(to: b)

        let zipURL = root.appendingPathComponent("no_eocd.zip")
        try BoltArchiveEngine.createArchive(
            from: [a, b],
            to: zipURL,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        // Truncate Central Directory + EOCD at end of file
        var data = try Data(contentsOf: zipURL)
        let cdMarker = Data([0x50, 0x4B, 0x01, 0x02])
        let cdStart = try XCTUnwrap(data.range(of: cdMarker)?.lowerBound)
        data = data.prefix(cdStart)
        try data.write(to: zipURL)

        // Normal open fails without EOCD
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: zipURL))

        let outURL = root.appendingPathComponent("recovered_no_eocd.zip")
        let report = try BoltArchiveEngine.recoverZip(at: zipURL, to: outURL)
        XCTAssertTrue(report.usedLocalHeaderFallbackScan)
        XCTAssertEqual(report.recoveredCount, 2)
        XCTAssertTrue(report.unrecoverableEntries.isEmpty)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: outURL, entryPath: "alpha.txt"), goodA)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: outURL, entryPath: "beta.txt"), goodB)
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: outURL).isHealthy)
    }

    func testRecoverZipHandlesEncryptedEntriesAndLeavesOutputAbsentWhenZeroRecoverable() throws {
        let file = root.appendingPathComponent("secret.txt")
        let secretBody = Data("Top secret AES-256 recoverable content\n".utf8)
        try secretBody.write(to: file)

        let encZip = root.appendingPathComponent("enc_damaged.zip")
        try BoltArchiveEngine.createArchive(
            from: [file],
            to: encZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate, encryption: .aes256, password: "correct")
        )

        // Destroy EOCD so fallback scan must inspect AES entry directly from Local File Header + extra fields
        var raw = try Data(contentsOf: encZip)
        let cdMarker = Data([0x50, 0x4B, 0x01, 0x02])
        let cdStart = try XCTUnwrap(raw.range(of: cdMarker)?.lowerBound)
        raw = raw.prefix(cdStart)
        try raw.write(to: encZip)

        let wrongOut = root.appendingPathComponent("wrong_attempt.zip")
        let wrongReport = try BoltArchiveEngine.recoverZip(at: encZip, to: wrongOut, password: "wrong")
        XCTAssertEqual(wrongReport.recoveredCount, 0)
        XCTAssertEqual(wrongReport.unrecoverableCount, 1)
        XCTAssertNil(wrongReport.recoveredArchiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wrongOut.path))

        let okOut = root.appendingPathComponent("ok_recovered.zip")
        let okReport = try BoltArchiveEngine.recoverZip(at: encZip, to: okOut, password: "correct")
        XCTAssertEqual(okReport.recoveredCount, 1)
        XCTAssertTrue(okReport.unrecoverableEntries.isEmpty)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: okOut, entryPath: "secret.txt", password: "correct"), secretBody)
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: okOut, password: "correct").isHealthy)
    }

    func testFallbackScanSkipsNestedStoredZipAndMissingSplitPartialRecovery() throws {
        // 1. Nested Store inner .zip must not produce duplicate inner entries when EOCD is missing
        let innerFile = root.appendingPathComponent("inside_inner.txt")
        try Data("inside nested stored zip\n".utf8).write(to: innerFile)
        let innerZip = root.appendingPathComponent("nested_bundle.zip")
        try BoltArchiveEngine.createArchive(
            from: [innerFile],
            to: innerZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .deflate)
        )

        let sibling = root.appendingPathComponent("outer_note.txt")
        let siblingBody = Data("Outer note preserved alongside stored nested archive\n".utf8)
        try siblingBody.write(to: sibling)

        let outerZip = root.appendingPathComponent("outer_stored_corrupt.zip")
        try BoltArchiveEngine.createArchive(
            from: [innerZip, sibling],
            to: outerZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .store)
        )
        var raw = try Data(contentsOf: outerZip)
        // Truncate right at the outer ZIP's EOCD / Central Directory without slicing inside nested_bundle.zip
        let eocdMarker = Data([0x50, 0x4B, 0x05, 0x06])
        let eocdStart = try XCTUnwrap(raw.range(of: eocdMarker, options: .backwards)?.lowerBound)
        let cdOffset = Int(raw[eocdStart + 16])
            | (Int(raw[eocdStart + 17]) << 8)
            | (Int(raw[eocdStart + 18]) << 16)
            | (Int(raw[eocdStart + 19]) << 24)
        raw = raw.prefix(cdOffset)
        try raw.write(to: outerZip)

        let nestedRecovered = root.appendingPathComponent("outer_recovered.zip")
        let nestedReport = try BoltArchiveEngine.recoverZip(at: outerZip, to: nestedRecovered)
        XCTAssertTrue(nestedReport.usedLocalHeaderFallbackScan)
        XCTAssertEqual(Set(nestedReport.recoveredEntries.map(\.path)), ["nested_bundle.zip", "outer_note.txt"])
        XCTAssertEqual(nestedReport.totalScannedCount, 2)
        XCTAssertFalse(nestedReport.recoveredEntries.contains { $0.path == "inside_inner.txt" })

        // 2. Missing .z01 in split ZIP still recovers surviving entries on later volumes
        let partA = root.appendingPathComponent("01_alpha.bin")
        let partB = root.appendingPathComponent("02_omega.bin")
        try Data((0..<90_000).map { UInt8(($0 * 7) & 0xFF) }).write(to: partA)
        let bodyB = Data((0..<90_000).map { UInt8(($0 * 13 + 3) & 0xFF) })
        try bodyB.write(to: partB)

        let splitZip = root.appendingPathComponent("split_partial.zip")
        let vols = try BoltArchiveEngine.createArchive(
            from: [partA, partB],
            to: splitZip,
            options: CreateArchiveOptions(format: .zip, algorithm: .store, splitVolumeSizeBytes: 80_000)
        )
        XCTAssertGreaterThanOrEqual(vols.count, 3)
        let firstSplit = splitZip.deletingPathExtension().appendingPathExtension("z01")
        try FileManager.default.removeItem(at: firstSplit)

        let splitRecovered = root.appendingPathComponent("split_recovered.zip")
        let splitReport = try BoltArchiveEngine.recoverZip(at: splitZip, to: splitRecovered)
        XCTAssertEqual(splitReport.recoveredCount, 1)
        XCTAssertEqual(splitReport.recoveredEntries.first?.path, "02_omega.bin")
        XCTAssertEqual(splitReport.unrecoverableCount, 1)
        XCTAssertEqual(splitReport.unrecoverableEntries.first?.entryPath, "01_alpha.bin")
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: splitRecovered, entryPath: "02_omega.bin"), bodyB)
    }
}
