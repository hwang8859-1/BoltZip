import Foundation
import XCTest
@testable import BoltZipCore

final class RARVolumeReliabilityTests: XCTestCase {
    func testCompleteArchiveOpenedFromItsLastVolume() throws {
        try withFixture { _, paths in
            let archive = paths[2]
            let listing = try BoltArchiveEngine.inspect(archiveURL: archive)
            XCTAssertTrue(listing.isSplitVolume)
            XCTAssertEqual(ExtendedArchiveDriver.resolveVolumePaths(for: archive, format: .rar), paths.map(\.path))
            XCTAssertEqual(listing.entries.map(\.path), ["protected.txt"])
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "protected.txt"),
                           Data("BoltZip protects this data.\n".utf8))
            XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: archive).isHealthy)
        }
    }

    func testMissingVolumesNeverOverwriteAnExistingFile() throws {
        for missingIndex in 0..<3 {
            try withFixture { root, paths in
                try FileManager.default.removeItem(at: paths[missingIndex])
                let archive = paths[missingIndex == 0 ? 2 : 0]
                let expected = paths[missingIndex].lastPathComponent
                XCTAssertEqual(ExtendedArchiveDriver.resolveVolumePaths(for: archive, format: .rar), [archive.path])
                let output = root.appendingPathComponent("output", isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                let file = output.appendingPathComponent("protected.txt")
                let existing = Data("previous destination".utf8)
                try existing.write(to: file)

                XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive)) { error in
                    guard case BoltZipError.missingSplitVolume(let name) = error else { return XCTFail("\(error)") }
                    XCTAssertEqual(name, expected)
                }
                XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "protected.txt"))
                XCTAssertThrowsError(try BoltArchiveEngine.extract(
                    archiveURL: archive,
                    options: ExtractOptions(destinationURL: output, mode: .here, overwritePolicy: .overwrite)
                ))
                XCTAssertThrowsError(try BoltArchiveEngine.extractSingleEntryToFile(
                    archiveURL: archive, entryPath: "protected.txt", destinationFileURL: file
                ))
                do {
                    let report = try BoltArchiveEngine.testIntegrity(archiveURL: archive)
                    XCTAssertFalse(report.isHealthy)
                } catch let error as BoltZipError {
                    guard case .missingSplitVolume = error else { return XCTFail("\(error)") }
                }
                XCTAssertEqual(try Data(contentsOf: file), existing)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["protected.txt"])
            }
        }
    }

    func testAdjacentUnrelatedFileCannotStandInForARequiredVolume() throws {
        try withFixture { _, paths in
            try Data("not a RAR volume".utf8).write(to: paths[1])
            XCTAssertThrowsError(try RARVolumeDiscovery.resolve(paths[0])) { error in
                guard case BoltZipError.missingSplitVolume(let name) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(name, paths[1].lastPathComponent)
            }
        }
    }

    private func withFixture(_ body: (URL, [URL]) throws -> Void) throws {
        // Three small RAR5 volumes holding one stored file split across all three parts.
        let encodedVolumes = [
            "UmFyIRoHAQBTKjRFAwEAAQg5SHAaAhIIBBwgjOnn9wAADXByb3RlY3RlZC50eHRCb2x0WmlwIItHUSYDBQQB",
            "UmFyIRoHAQDtVTTXBAEAAwFplpkEGgIaCAQcIEeaQ4MAAA1wcm90ZWN0ZWQudHh0cHJvdGVjdHOLR1EmAwUEAQ==",
            "UmFyIRoHAQBXBD1OBAEAAwJKh0BdGgIKDAQcILgNCxcAAA1wcm90ZWN0ZWQudHh0IHRoaXMgZGF0YS4KHXdWUQMFBAA="
        ]
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = try encodedVolumes.enumerated().map { index, encoded in
            let url = root.appendingPathComponent("archive.part0\(index + 1).rar")
            try XCTUnwrap(Data(base64Encoded: encoded)).write(to: url)
            return url
        }
        try body(root, paths)
    }
}
