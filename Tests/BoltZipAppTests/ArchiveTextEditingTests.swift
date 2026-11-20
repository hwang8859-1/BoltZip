import BoltZipCore
import Foundation
import XCTest
@testable import BoltZipApp

final class ArchiveTextEditingTests: XCTestCase {
    private func profile() throws -> ArchiveEntryCompressionProfile {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipTextTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("text.txt"), archive = root.appendingPathComponent("test.jar")
        try Data(String(repeating: "payload", count: 30).utf8).write(to: file)
        try BoltArchiveEngine.createArchive(from: [file], to: archive, options: CreateArchiveOptions())
        return try BoltArchiveEngine.entryCompressionProfile(at: archive, path: "text.txt")
    }

    func testEditorPreservesUnicodeBOMAndLineEndings() throws {
        for (encoding, bom) in [(String.Encoding.utf8, Data([0xef, 0xbb, 0xbf])),
                                (.utf16LittleEndian, Data([0xff, 0xfe])), (.utf16BigEndian, Data([0xfe, 0xff]))] {
            let original = bom + (try XCTUnwrap("你好\r\nworld\r\n".data(using: encoding)))
            let decoded = try XCTUnwrap(ArchiveTextDocument.decode(original))
            let document = ArchiveTextDocument(archiveURL: URL(fileURLWithPath: "/tmp/test.jar"), entryPath: "text.txt",
                text: decoded.0, encoding: decoded.1, bom: decoded.2, lineEnding: "\r\n", archiveModifiedDate: nil, profile: try profile())
            XCTAssertEqual(document.encoded("你好\nchanged\n"), bom + (try XCTUnwrap("你好\r\nchanged\r\n".data(using: encoding))))
        }
        XCTAssertNil(ArchiveTextDocument.decode(Data([0x00, 0x01, 0x02])))
        XCTAssertNil(ArchiveTextDocument.decode(Data([0xff, 0xfe, 0x00, 0x00])))
    }

    func testJARManifestKeepsItsRequiredTerminatingBlankLine() throws {
        let document = ArchiveTextDocument(archiveURL: URL(fileURLWithPath: "/tmp/test.jar"), entryPath: "META-INF/MANIFEST.MF",
            text: "", encoding: .utf8, bom: Data(), lineEnding: "\r\n", archiveModifiedDate: nil, profile: try profile())
        XCTAssertEqual(document.encoded("Manifest-Version: 1.0\nMain-Class: Main"), Data("Manifest-Version: 1.0\r\nMain-Class: Main\r\n\r\n".utf8))
    }

    func testCompressionDefaultsAndUnsupportedModesAreLocalized() throws {
        let profile = try profile()
        XCTAssertNil(profile.recordedLevel)
        XCTAssertEqual(profile.defaultLevel, 6)
        let errors: [ArchiveEditCompatibilityError] = [.unsupportedCompression(path: "data", method: 9),
            .unsupportedEncryption(path: "data"), .ambiguousEntry("data")]
        for error in errors {
            let messages = [AppLanguage.zhHans, .zhHant, .en, .ja].map { L10n(language: $0).operationErrorMessage(error) }
            XCTAssertEqual(Set(messages).count, 4)
        }
        for language in [AppLanguage.zhHans, .zhHant, .en, .ja] {
            XCTAssertTrue(L10n(language: language).compressionPreservationNotice(profile).contains("6"))
        }
    }
}
