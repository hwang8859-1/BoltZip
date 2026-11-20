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

    func testArchiveContentOverridesUnknownAndMisleadingExtensions() throws {
        let file = try source()
        for format in ArchiveFormat.creatableFormats {
            let archive = root.appendingPathComponent("original.\(format.fileExtension)")
            try BoltArchiveEngine.createArchive(from: [file], to: archive, options: CreateArchiveOptions(format: format, algorithm: format.defaultAlgorithm))
            for ext in ["arbitrary", "", "jar", "apk"] {
                let renamed = root.appendingPathComponent("renamed-\(format.rawValue)-\(ext)" + (ext.isEmpty ? "" : ".\(ext)"))
                try FileManager.default.copyItem(at: archive, to: renamed)
                XCTAssertEqual(try ArchiveFormat.detectForReading(from: renamed), format)
                let listing = try BoltArchiveEngine.inspect(archiveURL: renamed)
                XCTAssertEqual(listing.format, format)
                XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: renamed, entryPath: file.lastPathComponent), Data("payload".utf8))
                XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: renamed).isHealthy)
            }
        }
        let text = try source("plain.unknown", data: Data("not an archive".utf8))
        XCTAssertNil(try ArchiveFormat.detectForReading(from: text))
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: text))

        let directory = root.appendingPathComponent("directory.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertNil(try ArchiveFormat.detectForReading(from: directory))

        let symlink = root.appendingPathComponent("archive-link.unknown")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: root.appendingPathComponent("original.zip"))
        XCTAssertEqual(try ArchiveFormat.detectForReading(from: symlink), .zip)
    }

    func testSingleCompressedStreamsAreRecognizedWithoutExtensions() throws {
        let data = Data("single stream".utf8)
        for (format, algorithm) in [(ArchiveFormat.gz, CompressionAlgorithm.deflate), (.zst, .zstd), (.xz, .xz), (.bz2, .bzip2), (.lz4, .lz4)] {
            let archive = try source("stream-\(format.rawValue).data", data: CompressionCodec.compress(data: data, algorithm: algorithm, gzipContainer: format == .gz))
            XCTAssertEqual(try ArchiveFormat.detectForReading(from: archive), format)
            let listing = try BoltArchiveEngine.inspect(archiveURL: archive)
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: XCTUnwrap(listing.entries.first).path), data)
        }
    }

    func testCompressedZIPIsReadAsAnOuterStreamRatherThanAnUnwrappedZIP() throws {
        let file = try source()
        let zip = root.appendingPathComponent("inner.zip")
        try BoltArchiveEngine.createArchive(from: [file], to: zip, options: CreateArchiveOptions())
        let zipData = try Data(contentsOf: zip)
        let outer = try source("outer.unknown", data: CompressionCodec.compress(data: zipData, algorithm: .deflate, gzipContainer: true))
        let listing = try BoltArchiveEngine.inspect(archiveURL: outer)
        XCTAssertEqual(listing.format, .gz)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: outer, entryPath: XCTUnwrap(listing.entries.first).path), zipData)
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
            var unsupportedOptions = [CreateArchiveOptions(format: format, splitVolumeSizeBytes: 65536)]
            if !format.supportsEncryption {
                unsupportedOptions.append(CreateArchiveOptions(format: format, encryption: .aes256, password: "secret"))
            }
            for options in unsupportedOptions {
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

    func testSevenZipProgressCancellationPreservesExistingOutputAndStopsTraversal() throws {
        let file = try source("data.bin", data: Data(repeating: 0x42, count: 4 * 1024 * 1024))
        let output = try source("preserved.7z", data: Data("original archive".utf8))
        let controller = ArchiveTaskController()
        let observed = OSAllocatedUnfairLock(initialState: UInt64(0))
        XCTAssertThrowsError(try BoltArchiveEngine.createArchive(from: [file], to: output,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store), controller: controller) { progress in
                observed.withLock { $0 = max($0, progress.processedBytes) }
                if progress.processedBytes >= 1024 * 1024 { controller.cancel() }
            }) { error in
                guard case BoltZipError.cancelled = error else { return XCTFail("Unexpected error: \(error)") }
            }
        XCTAssertGreaterThan(observed.withLock { $0 }, 0)
        XCTAssertLessThan(observed.withLock { $0 }, 4 * 1024 * 1024)
        XCTAssertEqual(try Data(contentsOf: output), Data("original archive".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".boltzip-output-") })
    }

    func testOutputInsideInputIsExcludedAndSymbolicLinksDoNotRecurse() throws {
        let folder = root.appendingPathComponent("input")
        _ = try source("input/nested/file.txt")
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("self").path, withDestinationPath: ".")
        for format in [ArchiveFormat.zip, .tarZst, .sevenZip] {
            let archive = folder.appendingPathComponent("result.\(format.fileExtension)")
            try Data("old output".utf8).write(to: archive)
            try BoltArchiveEngine.createArchive(from: [folder], to: archive, options: CreateArchiveOptions(format: format, algorithm: format.defaultAlgorithm))
            let entries = try BoltArchiveEngine.inspect(archiveURL: archive).entries
            XCTAssertTrue(entries.contains { $0.path == "input/nested/file.txt" })
            XCTAssertTrue(entries.contains { $0.path == "input/self" && $0.isSymbolicLink })
            XCTAssertFalse(entries.contains { $0.path == "input/" + archive.lastPathComponent })
            XCTAssertLessThan(entries.count, 10)
            try FileManager.default.removeItem(at: archive)
        }
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
