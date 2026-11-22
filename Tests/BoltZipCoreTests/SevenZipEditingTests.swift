import Foundation
import XCTest
@testable import BoltZipCore

final class SevenZipEditingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZip7zEdit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPlainSolidSevenZipSupportsAddMkdirRenameReplaceAndDelete() throws {
        let aFile = root.appendingPathComponent("a.txt")
        let bFile = root.appendingPathComponent("b.txt")
        let cFile = root.appendingPathComponent("c.txt")
        let updatedA = root.appendingPathComponent("new_a.txt")
        try Data("alpha-v1".utf8).write(to: aFile)
        try Data("beta".utf8).write(to: bFile)
        try Data("gamma".utf8).write(to: cFile)
        try Data("alpha-v2-replaced".utf8).write(to: updatedA)

        let archive = root.appendingPathComponent("editable.7z")
        try BoltArchiveEngine.createArchive(
            from: [aFile, bFile],
            to: archive,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 3)
        )

        let listing0 = try BoltArchiveEngine.inspect(archiveURL: archive)
        XCTAssertTrue(listing0.canEditInPlace)

        try BoltArchiveEngine.editArchive(
            at: archive,
            operations: [
                .createFolder(path: "docs/"),
                .addItems(urls: [cFile], targetFolder: "docs/"),
                .replaceEntry(path: "a.txt", fileURL: updatedA),
                .renamePath(oldPath: "b.txt", newPath: "docs/renamed_b.txt"),
                .deletePaths(["docs/renamed_b.txt"])
            ],
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 3)
        )

        let listing1 = try BoltArchiveEngine.inspect(archiveURL: archive)
        let paths = Set(listing1.entries.map(\.path))
        XCTAssertTrue(paths.contains("a.txt"))
        XCTAssertTrue(paths.contains("docs/"))
        XCTAssertTrue(paths.contains("docs/c.txt"))
        XCTAssertFalse(paths.contains("b.txt"))
        XCTAssertFalse(paths.contains("docs/renamed_b.txt"))

        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "a.txt"), Data("alpha-v2-replaced".utf8))
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "docs/c.txt"), Data("gamma".utf8))
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: archive).isHealthy)
    }

    func testEncryptedSevenZipEditingPreservesHeaderEncryptionAndAtomicityOnWrongPassword() throws {
        let aFile = root.appendingPathComponent("secret.txt")
        let addFile = root.appendingPathComponent("added.txt")
        try Data("original-secret".utf8).write(to: aFile)
        try Data("added-secret".utf8).write(to: addFile)

        let archive = root.appendingPathComponent("encrypted.7z")
        try BoltArchiveEngine.createArchive(
            from: [aFile],
            to: archive,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, encryption: .aes256, password: "vault", encryptFileNames: true)
        )
        let originalSnapshot = try Data(contentsOf: archive)

        // Wrong password must fail cleanly without touching the archive
        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(
            at: archive,
            operations: [.addItems(urls: [addFile], targetFolder: "")],
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, encryption: .aes256, password: "bad", encryptFileNames: true)
        ))
        XCTAssertEqual(try Data(contentsOf: archive), originalSnapshot)

        // Valid password updates encrypted 7z and keeps header encryption (-mhe=on)
        try BoltArchiveEngine.editArchive(
            at: archive,
            operations: [.addItems(urls: [addFile], targetFolder: "sub/"), .renamePath(oldPath: "secret.txt", newPath: "sub/secret.txt")],
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, encryption: .aes256, password: "vault")
        )

        // Listing without password still blocked by -mhe=on
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive, password: nil))

        let listing = try BoltArchiveEngine.inspect(archiveURL: archive, password: "vault")
        let files = listing.entries.filter { !$0.isDirectory }
        XCTAssertEqual(Set(files.map(\.path)), ["sub/added.txt", "sub/secret.txt"])
        XCTAssertTrue(files.allSatisfy(\.isEncrypted))
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "sub/added.txt", password: "vault"), Data("added-secret".utf8))
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "sub/secret.txt", password: "vault"), Data("original-secret".utf8))
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: archive, password: "vault").isHealthy)
    }

    func testSplitSevenZipIsReadOnlyAndCommentsRejected() throws {
        let blob = root.appendingPathComponent("blob.bin")
        try Data(repeating: 0x33, count: 160_000).write(to: blob)

        let splitBase = root.appendingPathComponent("split.7z")
        let volumes = try BoltArchiveEngine.createArchive(
            from: [blob],
            to: splitBase,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65536)
        )
        let firstVol = try XCTUnwrap(volumes.first)
        let listing = try BoltArchiveEngine.inspect(archiveURL: firstVol)
        XCTAssertTrue(listing.isSplitVolume)
        XCTAssertFalse(listing.canEditInPlace)

        let add = root.appendingPathComponent("new.txt")
        try Data("x".utf8).write(to: add)
        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(at: firstVol, operations: [.addItems(urls: [add], targetFolder: "")]))

        let plain = root.appendingPathComponent("plain.7z")
        try BoltArchiveEngine.createArchive(from: [add], to: plain, options: CreateArchiveOptions(format: .sevenZip, algorithm: .store))
        XCTAssertFalse(ArchiveFormat.sevenZip.supportsArchiveComment)
        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(at: plain, operations: [.setComment("not supported")]))
    }

    func testSevenZipRejectsAncestorFileCollisionsOnEdit() throws {
        let fileA = root.appendingPathComponent("doc.txt")
        let fileB = root.appendingPathComponent("other.txt")
        try Data("hello".utf8).write(to: fileA)
        try Data("world".utf8).write(to: fileB)

        let archive = root.appendingPathComponent("collision.7z")
        try BoltArchiveEngine.createArchive(
            from: [fileA, fileB],
            to: archive,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store)
        )

        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(at: archive, operations: [.renamePath(oldPath: "other.txt", newPath: "doc.txt/other.txt")]))
        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(at: archive, operations: [.createFolder(path: "doc.txt/sub")]))
        XCTAssertThrowsError(try BoltArchiveEngine.editArchive(at: archive, operations: [.addItems(urls: [fileB], targetFolder: "doc.txt")]))

        // Original archive remains healthy after rejected edits
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: archive).isHealthy)
        let listing = try BoltArchiveEngine.inspect(archiveURL: archive)
        XCTAssertEqual(Set(listing.entries.map(\.path)), ["doc.txt", "other.txt"])
    }
}
