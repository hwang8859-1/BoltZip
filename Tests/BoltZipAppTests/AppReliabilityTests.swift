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

    func testBatchExtractionPreservesEarlierOutputsEvenWhenOverwriteWasApproved() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipBatch-\(UUID().uuidString)")
        let options = ExtractOptions(destinationURL: destination, mode: .here)
        let shared = ExtractConflictSummary(destinationRoot: destination, conflictingNames: ["report.txt"],
                                            outputLocations: [destination.appendingPathComponent("report.txt")])
        let other = ExtractConflictSummary(destinationRoot: destination, conflictingNames: ["notes.txt"],
                                           outputLocations: [destination.appendingPathComponent("notes.txt")])
        let jobs = [(options, shared), (options, shared), (options, other)]
        XCTAssertEqual(WorkspaceViewModel.batchExtractionPolicies(for: jobs, requestedPolicy: .overwrite),
                       [.overwrite, .rename, .overwrite])
        XCTAssertEqual(WorkspaceViewModel.batchExtractionPolicies(for: [(options, nil), (options, shared)], requestedPolicy: .overwrite),
                       [.rename, .rename])
    }

    func testOperationErrorsUseTheSelectedInterfaceLanguage() {
        let errors: [any Error] = [
            ArchiveOperationError.outputIsInput, ArchiveOperationError.outputIsDirectory("keep"),
            ArchiveOperationError.extractionWouldReplaceSource("test.zip"),
            ArchiveOperationError.inputChanged("data"), ArchiveOperationError.encryptionRequiresZIP,
            ArchiveOperationError.filenameEncryptionRequires7z, ArchiveOperationError.sevenZipEncryptionRequiresAES256,
            ArchiveOperationError.invalidSevenZipPassword, ArchiveOperationError.sevenZipEngineUnavailable,
            ArchiveOperationError.splitVolumesRequireZIP, ArchiveOperationError.applicationNotFound,
            ArchiveOperationError.singleStreamRequiresSingleRegularFile("XZ (.xz)"),
            ArchiveOperationError.noRecoverableZipEntries,
            ArchiveOperationError.sevenZipSplitArchiveReadOnly,
            BoltZipError.missingSplitVolume("archive.part02.rar")
        ]
        for error in errors {
            let messages = [AppLanguage.zhHans, .zhHant, .en, .ja].map { L10n(language: $0).operationErrorMessage(error) }
            XCTAssertEqual(Set(messages).count, 4)
            XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        }
    }

    func testSelectedZipExportPasswordPromptKeepsTheOriginalRequest() {
        let request = SelectedZipExport(source: URL(fileURLWithPath: "source.zip"),
                                        destination: URL(fileURLWithPath: "selected.zip"),
                                        entryPaths: ["folder/data.txt"], encoding: .auto, stripMacJunk: true)
        let purpose = PasswordPurpose.exportSelectedZip(request)
        let errors = [BoltZipError.passwordRequired("source.zip"), .wrongPassword("source.zip")]
        for (index, error) in errors.enumerated() {
            guard case .passwordPrompt(.exportSelectedZip(let retry), let wrongAttempt)? = purpose.prompt(for: error) else {
                return XCTFail("Expected an export password prompt")
            }
            XCTAssertEqual(wrongAttempt, index == 1)
            XCTAssertEqual(retry.source, request.source)
            XCTAssertEqual(retry.destination, request.destination)
            XCTAssertEqual(retry.entryPaths, request.entryPaths)
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

    func testArchiveEditPasswordRetryAndCommentSupportGating() {
        let editAdd = PasswordPurpose.unlockForEdit(urls: [URL(fileURLWithPath: "extra.txt")], targetFolder: "docs/")
        let editOps = PasswordPurpose.unlockEditOperations([.deletePaths(["old.txt"])])
        for purpose in [editAdd, editOps] {
            guard case .passwordPrompt(_, let wrong1)? = purpose.prompt(for: BoltZipError.passwordRequired("a.7z")) else {
                return XCTFail("Expected password required prompt")
            }
            XCTAssertFalse(wrong1)
            guard case .passwordPrompt(_, let wrong2)? = purpose.prompt(for: BoltZipError.wrongPassword("a.7z")) else {
                return XCTFail("Expected wrong password retry prompt")
            }
            XCTAssertTrue(wrong2)
        }

        XCTAssertTrue(ArchiveFormat.zip.supportsArchiveComment)
        XCTAssertFalse(ArchiveFormat.sevenZip.supportsArchiveComment)
        XCTAssertTrue(ArchiveFormat.sevenZip.supportsInPlaceEditing)
        XCTAssertTrue(ArchiveFormat.creatableFormats.contains(.gz))
        XCTAssertTrue(ArchiveFormat.creatableFormats.contains(.xz))
    }

    func testZipLikeDetectionAndDamagedZipRecoveryPromptTrigger() {
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.zip")))
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.jar")))
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.apk")))
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.cbz")))
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.epub")))
        XCTAssertTrue(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.z01")))
        XCTAssertFalse(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.tar")))
        XCTAssertFalse(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.7z")))
        XCTAssertFalse(ArchiveFormat.isZipLike(url: URL(fileURLWithPath: "test.rar")))

        for lang in [AppLanguage.zhHans, .zhHant, .en, .ja] {
            let l = L10n(language: lang)
            XCTAssertFalse(l.recoverZipMenuTitle.isEmpty)
            XCTAssertFalse(l.recoverZipDamagedTitle.isEmpty)
            XCTAssertFalse(l.recoverZipOfferBtn.isEmpty)
            XCTAssertTrue(l.recoverZipInspectFailedOffer("bad.zip").contains("bad.zip"))
            XCTAssertTrue(l.recoverZipDamagedStatusNotice("bad.zip").contains("bad.zip"))
        }
    }

    @MainActor
    func testMCPMenuAndHelpPanelWorkflow() {
        let vm = WorkspaceViewModel()
        XCTAssertNil(vm.activeSheet)
        vm.openMCPHelpPanel()
        if case .mcpHelp = vm.activeSheet {
            // Success
        } else {
            XCTFail("Expected .mcpHelp activeSheet")
        }

        for lang in [AppLanguage.zhHans, .zhHant, .en, .ja] {
            let l = L10n(language: lang)
            XCTAssertFalse(l.mcpMenuTitle.isEmpty)
            XCTAssertFalse(l.mcpSheetTitle.isEmpty)
            XCTAssertFalse(l.mcpSheetSubtitle.isEmpty)
            XCTAssertFalse(l.mcpConfigSectionTitle.isEmpty)
            XCTAssertFalse(l.mcpCopyConfigBtn.isEmpty)
            XCTAssertFalse(l.mcpCommandSectionTitle.isEmpty)
            XCTAssertFalse(l.mcpCopyCommandBtn.isEmpty)
            XCTAssertFalse(l.mcpCopiedToast.isEmpty)
            XCTAssertFalse(l.mcpToolsSectionTitle.isEmpty)
            XCTAssertFalse(l.mcpToolCompressDesc.isEmpty)
            XCTAssertFalse(l.mcpToolExtractDesc.isEmpty)
            XCTAssertFalse(l.mcpToolBatchCompressDesc.isEmpty)
            XCTAssertFalse(l.mcpToolBatchExtractDesc.isEmpty)
            XCTAssertFalse(l.mcpToolListDesc.isEmpty)
            XCTAssertFalse(l.mcpToolTestDesc.isEmpty)
            XCTAssertFalse(l.mcpToolRecoverZipDesc.isEmpty)
        }
    }
}
