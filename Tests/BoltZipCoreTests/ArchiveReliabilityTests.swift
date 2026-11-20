import Foundation
import os
import XCTest
@testable import BoltZipCore

final class ArchiveReliabilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipReliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func source(_ name: String = "payload.txt", data: Data = Data("payload".utf8)) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testCreatingArchivesNeverDeletesExistingDirectories() throws {
        let file = try source()
        for format in ArchiveFormat.creatableFormats {
            let output = root.appendingPathComponent("existing.\(format.fileExtension)")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let sentinel = output.appendingPathComponent("keep.txt")
            try Data("keep".utf8).write(to: sentinel)
            XCTAssertThrowsError(try BoltArchiveEngine.createArchive(from: [file], to: output, options: CreateArchiveOptions(format: format)))
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        }
    }

    func testUnsupportedEncryptionAndSplitOptionsFailWithoutReplacingOutput() throws {
        let file = try source()
        for format in ArchiveFormat.creatableFormats where format != .zip {
            let output = try source("preserved.\(format.fileExtension)", data: Data("existing archive".utf8))
            for options in [CreateArchiveOptions(format: format, encryption: .aes256, password: "secret"),
                            CreateArchiveOptions(format: format, splitVolumeSizeBytes: 65536)] {
                XCTAssertThrowsError(try BoltArchiveEngine.createArchive(from: [file], to: output, options: options))
                XCTAssertEqual(try Data(contentsOf: output), Data("existing archive".utf8))
            }
        }
    }

    func testSameNamedInputsArePreservedWithDistinctArchiveNames() throws {
        let a = try source("one/same.txt", data: Data("FIRST".utf8))
        let b = try source("two/same.txt", data: Data("LAST!".utf8))
        for format in [ArchiveFormat.zip, .tarZst, .sevenZip] {
            let archive = root.appendingPathComponent("duplicates.\(format.fileExtension)")
            try BoltArchiveEngine.createArchive(from: [a, b, a], to: archive, options: CreateArchiveOptions(format: format, algorithm: format.defaultAlgorithm))
            let entries = try BoltArchiveEngine.inspect(archiveURL: archive).entries
            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(Set(entries.map(\.path)), ["same.txt", "same (1).txt"])
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "same.txt"), Data("FIRST".utf8))
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "same (1).txt"), Data("LAST!".utf8))
        }
    }

    func testDuplicateZIPRecordsDecodeTheirOwnPayloadWhenRenamed() throws {
        let a = try source("a.txt", data: Data("FIRST".utf8))
        let b = try source("b.txt", data: Data("LAST!".utf8))
        let archive = root.appendingPathComponent("records.zip")
        try BoltArchiveEngine.createArchive(from: [a, b], to: archive, options: CreateArchiveOptions(algorithm: .store))
        var bytes = try Data(contentsOf: archive)
        let old = Data("b.txt".utf8)
        while let range = bytes.range(of: old) { bytes.replaceSubrange(range, with: Data("a.txt".utf8)) }
        try bytes.write(to: archive)
        let output = root.appendingPathComponent("renamed-records")
        try BoltArchiveEngine.extract(archiveURL: archive, options: ExtractOptions(destinationURL: output, mode: .here, overwritePolicy: .rename))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("a.txt")), Data("FIRST".utf8))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("a (1).txt")), Data("LAST!".utf8))
    }

    func testFlatPublicationPreservesDirectoriesAndRollsBackSplitFailures() throws {
        let incoming = try source("incoming.txt")
        let directory = root.appendingPathComponent("out/incoming.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: sentinel)
        let published = try BoltArchiveEngine.publishExtractedFile(from: incoming, to: directory, under: directory.deletingLastPathComponent(), policy: .overwrite)
        XCTAssertEqual(published?.lastPathComponent, "incoming (1).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))

        let a = try source("old.z01", data: Data("old first".utf8))
        let b = try source("old.zip", data: Data("old last".utf8))
        let staged = try source("new", data: Data("new first".utf8))
        XCTAssertThrowsError(try ArchiveOutputTransaction.publish([staged, root.appendingPathComponent("missing")], to: [a, b]))
        XCTAssertEqual(try Data(contentsOf: a), Data("old first".utf8))
        XCTAssertEqual(try Data(contentsOf: b), Data("old last".utf8))
    }
}
