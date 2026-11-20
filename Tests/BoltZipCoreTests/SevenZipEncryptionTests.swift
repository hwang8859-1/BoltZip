import Foundation
import XCTest
@testable import BoltZipCore

final class SevenZipEncryptionTests: XCTestCase {
    private let password = "中文 pass 🔐"
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipEncrypted7z-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testEncryptedHeadersRequirePasswordAndRoundTrip() throws {
        let folder = root.appendingPathComponent("private")
        let names = ["合同.txt", "-报告[1]?.txt ", "sub/内容.bin", "sub/empty"]
        for (index, name) in names.enumerated() {
            let file = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload(index).write(to: file)
        }
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("link").path,
                                                  withDestinationPath: "合同.txt")
        let archive = root.appendingPathComponent("protected.archive")
        try BoltArchiveEngine.createArchive(from: [folder], to: archive, options: encryptedOptions(hideNames: true))

        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive)) { error in
            guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive, password: "wrong")) { error in
            guard case BoltZipError.wrongPassword = error else { return XCTFail("\(error)") }
        }
        let listing = try BoltArchiveEngine.inspect(archiveURL: archive, password: password)
        XCTAssertEqual(listing.format, .sevenZip)
        XCTAssertTrue(listing.hasEncryptedEntries)
        for name in names {
            XCTAssertTrue(listing.entries.contains { $0.path == "private/\(name)" }, name)
        }
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: archive, password: password).isHealthy)
        XCTAssertThrowsError(try BoltArchiveEngine.testIntegrity(archiveURL: archive))

        let name = "private/\(names[0])"
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: name, password: password), payload(0))
        XCTAssertEqual(try ExtendedArchiveDriver.readEntryData(at: archive, path: name, password: password,
                                                               exactOutputSize: UInt64(payload(0).count)), payload(0))
        XCTAssertThrowsError(try ExtendedArchiveDriver.readEntryData(at: archive, path: name, password: password, exactOutputSize: 5))
        let preview = root.appendingPathComponent("preview.txt")
        try BoltArchiveEngine.extractSingleEntryToFile(archiveURL: archive, entryPath: name,
                                                       destinationFileURL: preview, password: password)
        XCTAssertEqual(try Data(contentsOf: preview), payload(0))
        XCTAssertThrowsError(try BoltArchiveEngine.extractSingleEntryToFile(
            archiveURL: archive, entryPath: name, destinationFileURL: preview, password: "wrong"
        ))
        XCTAssertEqual(try Data(contentsOf: preview), payload(0))

        let destination = root.appendingPathComponent("roundtrip")
        try BoltArchiveEngine.extract(archiveURL: archive,
                                      options: ExtractOptions(destinationURL: destination, mode: .here, password: password))
        for (index, name) in names.enumerated() {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("private/\(name)")), payload(index))
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("private/link").path),
                       "合同.txt")
    }

    func testContentOnlyEncryptionLeavesNamesVisibleAndProtectsExistingFiles() throws {
        let name = "visible.txt"
        let file = root.appendingPathComponent(name)
        try payload(0).write(to: file)
        let archive = root.appendingPathComponent("content-only.7z")
        try BoltArchiveEngine.createArchive(from: [file], to: archive, options: encryptedOptions(hideNames: false))

        let entry = try XCTUnwrap(BoltArchiveEngine.inspect(archiveURL: archive).entries.first)
        XCTAssertEqual(entry.path, name)
        XCTAssertTrue(entry.isEncrypted)
        XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: name)) { error in
            guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
        }
        let destination = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let target = destination.appendingPathComponent(name)
        let existing = Data("existing data".utf8)
        try existing.write(to: target)
        XCTAssertThrowsError(try BoltArchiveEngine.extract(archiveURL: archive, options: ExtractOptions(
            destinationURL: destination, mode: .here, password: "wrong"
        ))) { error in
            guard case BoltZipError.wrongPassword = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: target), existing)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [name])
        try BoltArchiveEngine.extract(archiveURL: archive, options: ExtractOptions(
            destinationURL: destination, mode: .here, password: password
        ))
        XCTAssertEqual(try Data(contentsOf: target), payload(0))
    }

    func testInvalidSettingsLeaveExistingArchiveUntouched() throws {
        let input = root.appendingPathComponent("input")
        let output = root.appendingPathComponent("existing")
        try payload(0).write(to: input)
        try payload(1).write(to: output)
        let invalidOptions = [
            CreateArchiveOptions(format: .zip, encryption: .aes256, password: password, encryptFileNames: true),
            CreateArchiveOptions(format: .sevenZip, encryption: .zipCrypto, password: password, encryptFileNames: true),
            CreateArchiveOptions(format: .sevenZip, encryption: .aes256, encryptFileNames: true),
            CreateArchiveOptions(format: .sevenZip, encryption: .aes256, password: "\n", encryptFileNames: true)
        ]
        for options in invalidOptions {
            XCTAssertThrowsError(try BoltArchiveEngine.createArchive(from: [input], to: output, options: options))
            XCTAssertEqual(try Data(contentsOf: output), payload(1))
        }
    }

    func testEncryptedHeadersHideNamesEvenWhenAllEntriesAreEmpty() throws {
        let folder = root.appendingPathComponent("hidden")
        let emptyFolder = folder.appendingPathComponent("empty-folder")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("empty-file"))
        let archive = root.appendingPathComponent("empty.7z")
        try BoltArchiveEngine.createArchive(from: [folder], to: archive, options: encryptedOptions(hideNames: true))
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive)) { error in
            guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
        }
        let listing = try BoltArchiveEngine.inspect(archiveURL: archive, password: password)
        XCTAssertEqual(Set(listing.entries.map(\.path)), ["hidden/", "hidden/empty-folder/", "hidden/empty-file"])
        let destination = root.appendingPathComponent("out")
        try BoltArchiveEngine.extract(archiveURL: archive,
                                      options: ExtractOptions(destinationURL: destination, mode: .here, password: password))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("hidden/empty-file")), Data())
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("hidden/empty-folder").path))
    }

    func testAmbiguousSevenZipPathsFailBeforeReplacingExistingArchive() throws {
        let folder = root.appendingPathComponent("folder")
        let nested = folder.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try payload(0).write(to: nested.appendingPathComponent("data"))
        try payload(1).write(to: folder.appendingPathComponent("sub\\data"))
        let output = root.appendingPathComponent("collision.7z")
        let before = Data("keep this archive".utf8)
        try before.write(to: output)
        for options in [encryptedOptions(hideNames: true), CreateArchiveOptions(format: .sevenZip, algorithm: .xz, workerCount: 1)] {
            XCTAssertThrowsError(try BoltArchiveEngine.createArchive(from: [folder], to: output, options: options)) { error in
                guard case BoltZipError.entryAlreadyExists = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try Data(contentsOf: output), before)
        }
    }

    func testHelperProgressDecodesSplitFramesAndIgnoresFileNames() {
        var parser = SevenZipWriteProgress()
        XCTAssertEqual(parser.receive(Data("  0%\u{8}  3".utf8)), [])
        XCTAssertEqual(parser.receive(Data("5% + made-up 92%\u{8}\u{8} 80".utf8)), [35])
        XCTAssertEqual(parser.receive(Data("% + name\r 77%\r100%".utf8)), [80, 100])
    }

    private func encryptedOptions(hideNames: Bool) -> CreateArchiveOptions {
        CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 1,
                             encryption: .aes256, password: password, encryptFileNames: hideNames)
    }

    private func payload(_ index: Int) -> Data {
        index == 3 ? Data() : Data(repeating: UInt8(index + 65), count: 90_005 + index * 614)
    }
}
