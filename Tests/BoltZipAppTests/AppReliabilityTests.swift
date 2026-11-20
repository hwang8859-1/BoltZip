import BoltZipCore
import Foundation
import XCTest
@testable import BoltZipApp

final class AppReliabilityTests: XCTestCase {
    func testArchiveBadgeKeepsTheOriginalFilenameSuffix() {
        let l = L10n(language: .zhHans)
        for (filename, expected) in [("sample.jar", "ZIP (.jar)"), ("sample.apk", "ZIP (.apk)"),
                                     ("sample.JAR", "ZIP (.JAR)"), ("sample.unrecognized", "ZIP (.unrecognized)"),
                                     ("sample", "ZIP")] {
            XCTAssertEqual(l.archiveFormatDisplayName(.zip, fileURL: URL(fileURLWithPath: filename)), expected)
        }
        XCTAssertEqual(l.archiveFormatDisplayName(.tarGz, fileURL: URL(fileURLWithPath: "sample.tar.gz")), "TAR + Gzip (.tar.gz)")
        XCTAssertEqual(l.archiveFormatDisplayName(.tarGz, fileURL: URL(fileURLWithPath: "sample.TGZ")), "TAR + Gzip (.TGZ)")
    }

    func testOperationErrorsUseTheSelectedInterfaceLanguage() {
        let errors: [ArchiveOperationError] = [.outputIsInput, .outputIsDirectory("keep"), .inputChanged("data"), .encryptionRequiresZIP, .splitVolumesRequireZIP, .applicationNotFound]
        for error in errors {
            let messages = [AppLanguage.zhHans, .zhHant, .en, .ja].map { L10n(language: $0).operationErrorMessage(error) }
            XCTAssertEqual(Set(messages).count, 4)
            XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        }
    }

    func testThrottledUpdateCheckDoesNotCountAsNetworkCheck() async throws {
        let result = try await UpdateCheckerService.checkForUpdates(force: false, savedETag: "unchanged", skippedVersion: "", lastCheckTimestamp: Date().timeIntervalSince1970 - 60)
        XCTAssertFalse(result.didPerformCheck)
        XCTAssertEqual(result.newETag, "unchanged")
    }

    func testUpdaterErrorsAreLocalizedInAllInterfaceLanguages() {
        let errors: [UpdateError] = [.noDMGAsset, .missingChecksumManifest, .invalidResponse, .downloadFailed, .checksumMismatch(expected: "aaa", actual: "bbb")]
        for error in errors {
            let messages = [AppLanguage.zhHans, .zhHant, .en, .ja].map { L10n(language: $0).operationErrorMessage(error) }
            XCTAssertEqual(Set(messages).count, 4)
        }
    }

    func testMalformedVersionsCannotMasqueradeAsNewReleases() {
        for value in ["bad.999.1", "1..2", "1.-2.3", "1.2.3.4", "1.2.beta", "", "1.99999999999999999999999999"] {
            XCTAssertNil(SemanticVersion(value), value)
        }
        XCTAssertEqual(SemanticVersion("v1.2.3")?.formatted, "1.2.3")
        XCTAssertTrue(SemanticVersion("1.0.4")! > SemanticVersion("1.0.3")!)
    }

    func testInstallerDownloadDoesNotSelectAnExistingFileOrDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipDownloadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("installer.dmg")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let sentinel = original.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: sentinel)
        let next = UpdateCheckerService.availableDownloadURL(original)
        XCTAssertEqual(next.lastPathComponent, "installer (1).dmg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }
}
