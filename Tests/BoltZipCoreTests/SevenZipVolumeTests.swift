import Foundation
import XCTest
@testable import BoltZipCore

final class SevenZipVolumeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZip7zSplit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testOpenCompleteSplitSevenZipCreatedBySevenZipFromAnyVolume() throws {
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let binaryData = pseudoRandomData(count: 180_000)
        try binaryData.write(to: src.appendingPathComponent("blob.bin"))
        let noteData = Data("Split 7z 文本内容\n".utf8)
        try noteData.write(to: src.appendingPathComponent("文档.txt"))
        try Data().write(to: src.appendingPathComponent("empty.txt"))
        try FileManager.default.createSymbolicLink(atPath: src.appendingPathComponent("alias.txt").path,
                                                  withDestinationPath: "文档.txt")

        let base = root.appendingPathComponent("sevenzip_created.7z")
        let result = try SevenZipCommand.run(
            ["a", "-t7z", "-m0=Copy", "-snl", "-v65536b", "-scsUTF-8", "-sccUTF-8", "--",
             base.path, "blob.bin", "文档.txt", "empty.txt", "alias.txt"],
            password: nil,
            directory: src
        )
        XCTAssertEqual(result.status, 0)

        let volumes = (1...3).map { root.appendingPathComponent("sevenzip_created.7z.00\($0)") }
        for vol in volumes {
            XCTAssertTrue(FileManager.default.fileExists(atPath: vol.path), vol.lastPathComponent)
            XCTAssertEqual(try ArchiveFormat.detectForReading(from: vol), .sevenZip)
            XCTAssertEqual(ExtendedArchiveDriver.resolveVolumePaths(for: vol, format: .sevenZip), volumes.map(\.path))
        }

        for opened in [volumes[0], volumes[1], volumes[2]] {
            let listing = try BoltArchiveEngine.inspect(archiveURL: opened)
            XCTAssertEqual(listing.format, .sevenZip)
            XCTAssertTrue(listing.isSplitVolume)
            XCTAssertEqual(Set(listing.entries.map(\.path)), ["blob.bin", "文档.txt", "empty.txt", "alias.txt"])

            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: opened, entryPath: "blob.bin"), binaryData)
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: opened, entryPath: "文档.txt"), noteData)
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: opened, entryPath: "empty.txt"), Data())
            XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: opened).isHealthy)

            let outDir = root.appendingPathComponent("out-\(opened.pathExtension)", isDirectory: true)
            let extractedRoot = try BoltArchiveEngine.extract(archiveURL: opened, options: ExtractOptions(destinationURL: outDir, mode: .smart))
            XCTAssertEqual(extractedRoot.lastPathComponent, "sevenzip_created")
            XCTAssertEqual(try Data(contentsOf: extractedRoot.appendingPathComponent("blob.bin")), binaryData)
            XCTAssertEqual(try Data(contentsOf: extractedRoot.appendingPathComponent("文档.txt")), noteData)
            XCTAssertEqual(try Data(contentsOf: extractedRoot.appendingPathComponent("empty.txt")), Data())
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: extractedRoot.appendingPathComponent("alias.txt").path),
                           "文档.txt")
        }

        let singleOut = root.appendingPathComponent("single.txt")
        try BoltArchiveEngine.extractSingleEntryToFile(archiveURL: volumes[2], entryPath: "文档.txt", destinationFileURL: singleOut)
        XCTAssertEqual(try Data(contentsOf: singleOut), noteData)
    }

    func testMissingAndCorruptedVolumesAreReportedAndPreserveDestination() throws {
        let data = pseudoRandomData(count: 170_000)
        let input = root.appendingPathComponent("payload.bin")
        try data.write(to: input)
        let volumes = try BoltArchiveEngine.createArchive(
            from: [input],
            to: root.appendingPathComponent("missing_case.7z"),
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65_536)
        )
        XCTAssertEqual(volumes.count, 3)

        for missingIndex in 0..<3 {
            let dir = root.appendingPathComponent("case-\(missingIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var copied: [URL] = []
            for (idx, vol) in volumes.enumerated() where idx != missingIndex {
                let target = dir.appendingPathComponent(vol.lastPathComponent)
                try FileManager.default.copyItem(at: vol, to: target)
                copied.append(target)
            }
            let opened = missingIndex == 0 ? copied.last! : copied.first!
            let expectedMissing = volumes[missingIndex].lastPathComponent
            XCTAssertEqual(ExtendedArchiveDriver.resolveVolumePaths(for: opened, format: .sevenZip), [opened.path])

            let extractOut = dir.appendingPathComponent("out", isDirectory: true)
            try FileManager.default.createDirectory(at: extractOut, withIntermediateDirectories: true)
            let existingFile = extractOut.appendingPathComponent("payload.bin")
            let existingBytes = Data("preserve existing".utf8)
            try existingBytes.write(to: existingFile)

            XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: opened)) { error in
                guard case BoltZipError.missingSplitVolume(let name) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(name, expectedMissing)
            }
            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: opened, entryPath: "payload.bin"))
            XCTAssertThrowsError(try BoltArchiveEngine.extract(
                archiveURL: opened,
                options: ExtractOptions(destinationURL: extractOut, mode: .here, overwritePolicy: .overwrite)
            ))
            XCTAssertThrowsError(try BoltArchiveEngine.extractSingleEntryToFile(
                archiveURL: opened, entryPath: "payload.bin", destinationFileURL: existingFile
            ))
            XCTAssertThrowsError(try BoltArchiveEngine.testIntegrity(archiveURL: opened)) { error in
                guard case BoltZipError.missingSplitVolume(let name) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(name, expectedMissing)
            }
            XCTAssertEqual(try Data(contentsOf: existingFile), existingBytes)
        }

        // Corrupt last volume's NextHeader bytes
        let corruptDir = root.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let corruptVols = try volumes.map { vol -> URL in
            let dst = corruptDir.appendingPathComponent(vol.lastPathComponent)
            try FileManager.default.copyItem(at: vol, to: dst)
            return dst
        }
        var lastData = try Data(contentsOf: corruptVols[2])
        lastData[lastData.count - 1] ^= 0xFF
        try lastData.write(to: corruptVols[2])
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: corruptVols[0])) { error in
            guard case BoltZipError.invalidArchive = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(try BoltArchiveEngine.testIntegrity(archiveURL: corruptVols[0]).isHealthy)

        // Out-of-range volume index
        let stray = corruptDir.appendingPathComponent("missing_case.7z.099")
        try Data("stray".utf8).write(to: stray)
        XCTAssertThrowsError(try SevenZipVolumeDiscovery.resolve(stray))
    }

    func testStandaloneSingleVolumeNamed001AndContinuationStartingWithGzipMagic() throws {
        // 1. Standalone .7z named single.7z.001 with stray single.7z.002
        let src = root.appendingPathComponent("hello.txt")
        try Data("standalone".utf8).write(to: src)
        let single = root.appendingPathComponent("single.7z.001")
        try BoltArchiveEngine.createArchive(
            from: [src],
            to: single,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store)
        )
        let stray = root.appendingPathComponent("single.7z.002")
        try Data("unrelated extra bytes".utf8).write(to: stray)

        let singleListing = try BoltArchiveEngine.inspect(archiveURL: single)
        XCTAssertFalse(singleListing.isSplitVolume)
        XCTAssertEqual(singleListing.entries.map(\.path), ["hello.txt"])
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: single, entryPath: "hello.txt"), Data("standalone".utf8))
        XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: stray))

        // 2. Continuation volume .7z.002 whose bytes happen to start with gzip magic 1F 8B
        var gzipLikePayload = Data(count: 140_000)
        // Stored entry starts after 32-byte 7z header, so offset (65536 - 32) falls at byte 0 of .7z.002.
        gzipLikePayload[65_536 - 32] = 0x1F
        gzipLikePayload[65_536 - 32 + 1] = 0x8B
        gzipLikePayload[65_536 - 32 + 2] = 0x08
        let trickyInput = root.appendingPathComponent("tricky.bin")
        try gzipLikePayload.write(to: trickyInput)
        let trickyVols = try BoltArchiveEngine.createArchive(
            from: [trickyInput],
            to: root.appendingPathComponent("tricky.7z"),
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65_536)
        )
        XCTAssertGreaterThanOrEqual(trickyVols.count, 2)
        XCTAssertEqual(try Data(contentsOf: trickyVols[1]).prefix(3), Data([0x1F, 0x8B, 0x08]))
        XCTAssertEqual(try ArchiveFormat.detectForReading(from: trickyVols[1]), .sevenZip)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: trickyVols[1], entryPath: "tricky.bin"), gzipLikePayload)
    }

    func testEncryptedSplitSevenZipDataAndHeaderEncryptionInteroperatesWithSevenZip() throws {
        let folder = root.appendingPathComponent("secret_folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = pseudoRandomData(count: 155_000)
        try payload.write(to: folder.appendingPathComponent("secret.bin"))
        try Data("visible text".utf8).write(to: folder.appendingPathComponent("note.txt"))
        let password = "Split7z!密码"

        for hideNames in [false, true] {
            let base = root.appendingPathComponent("enc_\(hideNames ? "hdr" : "data").7z")
            let volumes = try BoltArchiveEngine.createArchive(
                from: [folder],
                to: base,
                options: CreateArchiveOptions(
                    format: .sevenZip,
                    algorithm: .store,
                    encryption: .aes256,
                    password: password,
                    splitVolumeSizeBytes: 65_536,
                    encryptFileNames: hideNames
                )
            )
            XCTAssertGreaterThanOrEqual(volumes.count, 2)

            if hideNames {
                XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: volumes[0])) { error in
                    guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
                }
                XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: volumes[1], password: "wrong")) { error in
                    guard case BoltZipError.wrongPassword = error else { return XCTFail("\(error)") }
                }
            } else {
                let visible = try BoltArchiveEngine.inspect(archiveURL: volumes[0])
                XCTAssertTrue(visible.isSplitVolume)
                XCTAssertTrue(visible.hasEncryptedEntries)
            }

            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: volumes[0], entryPath: "secret_folder/note.txt")) { error in
                guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
            }
            XCTAssertThrowsError(try BoltArchiveEngine.testIntegrity(archiveURL: volumes[0])) { error in
                guard case BoltZipError.passwordRequired = error else { return XCTFail("\(error)") }
            }
            XCTAssertThrowsError(try BoltArchiveEngine.testIntegrity(archiveURL: volumes[0], password: "wrong")) { error in
                guard case BoltZipError.wrongPassword = error else { return XCTFail("\(error)") }
            }

            let outDir = root.appendingPathComponent("dec_\(hideNames)", isDirectory: true)
            try FileManager.default.createDirectory(at: outDir.appendingPathComponent("secret_folder"), withIntermediateDirectories: true)
            let guarded = outDir.appendingPathComponent("secret_folder/note.txt")
            try Data("keep on wrong password".utf8).write(to: guarded)
            XCTAssertThrowsError(try BoltArchiveEngine.extract(
                archiveURL: volumes[0],
                options: ExtractOptions(destinationURL: outDir, mode: .here, password: "wrong")
            )) { error in
                guard case BoltZipError.wrongPassword = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try Data(contentsOf: guarded), Data("keep on wrong password".utf8))

            let listing = try BoltArchiveEngine.inspect(archiveURL: volumes[1], password: password)
            XCTAssertTrue(listing.isSplitVolume)
            XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: volumes[1], password: password).isHealthy)
            try BoltArchiveEngine.extract(
                archiveURL: volumes[1],
                options: ExtractOptions(destinationURL: outDir, mode: .here, password: password)
            )
            XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("secret_folder/secret.bin")), payload)
            XCTAssertEqual(try Data(contentsOf: guarded), Data("visible text".utf8))

            // Verify 7zz CLI itself tests and extracts BoltZip-created split 7z volumes cleanly.
            let sevenZipTest = try SevenZipCommand.run(
                ["t", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", volumes[0].path],
                password: password
            )
            XCTAssertEqual(sevenZipTest.status, 0)

            let sevenZipExtractDir = root.appendingPathComponent("7zz_out_\(hideNames)", isDirectory: true)
            let sevenZipExtract = try SevenZipCommand.run(
                ["x", "-y", "-o\(sevenZipExtractDir.path)", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", volumes[0].path],
                password: password
            )
            XCTAssertEqual(sevenZipExtract.status, 0)
            XCTAssertEqual(try Data(contentsOf: sevenZipExtractDir.appendingPathComponent("secret_folder/secret.bin")), payload)
        }
    }

    func testSplitSevenZipProtectsAllSourceVolumesAndRejectsInputCollisions() throws {
        let protectedName = "bundle.7z.002"
        let inputDir = root.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        let entryPayload = pseudoRandomData(count: 150_000)
        try entryPayload.write(to: inputDir.appendingPathComponent(protectedName))

        let bundleBase = root.appendingPathComponent("bundle.7z")
        let volumes = try BoltArchiveEngine.createArchive(
            from: [inputDir.appendingPathComponent(protectedName)],
            to: bundleBase,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65_536)
        )
        XCTAssertGreaterThanOrEqual(volumes.count, 2)
        let originalVolumes = try volumes.map { try Data(contentsOf: $0) }

        XCTAssertThrowsError(try BoltArchiveEngine.extract(
            archiveURL: volumes[0],
            options: ExtractOptions(destinationURL: root, mode: .here, overwritePolicy: .overwrite)
        )) { error in
            guard case ArchiveOperationError.extractionWouldReplaceSource = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try BoltArchiveEngine.extractSingleEntryToFile(
            archiveURL: volumes[0], entryPath: protectedName, destinationFileURL: volumes[1]
        )) { error in
            guard case ArchiveOperationError.extractionWouldReplaceSource = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try BoltArchiveEngine.exportSelectedEntriesAsZip(
            at: volumes[0], to: volumes[1], entryPaths: [protectedName]
        )) { error in
            guard case ArchiveOperationError.outputIsInput = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try volumes.map { try Data(contentsOf: $0) }, originalVolumes)

        // Overwrite policy .rename preserves all source volumes while extracting with a non-colliding filename.
        try BoltArchiveEngine.extract(
            archiveURL: volumes[0],
            options: ExtractOptions(destinationURL: root, mode: .here, overwritePolicy: .rename)
        )
        XCTAssertEqual(try volumes.map { try Data(contentsOf: $0) }, originalVolumes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("bundle.7z (1).002")), entryPayload)

        // Creating a split 7z whose output volume equals one of the explicit inputs must refuse and preserve the input.
        XCTAssertThrowsError(try BoltArchiveEngine.createArchive(
            from: [volumes[1]],
            to: bundleBase,
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65_536)
        )) { error in
            guard case ArchiveOperationError.outputIsInput = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try volumes.map { try Data(contentsOf: $0) }, originalVolumes)
    }

    func testCreateSplitSevenZipCodecsSingleVolumeNormalizationCancelAndHelper() throws {
        // 1. LZMA2 split creation & 7zz verification
        let folder = root.appendingPathComponent("lzma2_src", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = pseudoRandomData(count: 165_000)
        try data.write(to: folder.appendingPathComponent("random.dat"))
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("link").path,
                                                  withDestinationPath: "random.dat")

        let lzmaVols = try BoltArchiveEngine.createArchive(
            from: [folder],
            to: root.appendingPathComponent("lzma2.7z.001"),
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, level: 3, splitVolumeSizeBytes: 65_536)
        )
        XCTAssertGreaterThanOrEqual(lzmaVols.count, 2)
        XCTAssertEqual(lzmaVols.first?.lastPathComponent, "lzma2.7z.001")
        XCTAssertTrue(try BoltArchiveEngine.testIntegrity(archiveURL: lzmaVols[0]).isHealthy)
        let check = try SevenZipCommand.run(["t", "-bso0", "-bse2", "-bsp0", "-spd", "-ssc", "--", lzmaVols[0].path], password: nil)
        XCTAssertEqual(check.status, 0)

        // 2. Archive smaller than split threshold yields single .7z.001 volume
        let smallFile = root.appendingPathComponent("tiny.txt")
        try Data("tiny".utf8).write(to: smallFile)
        let singleSplitVols = try BoltArchiveEngine.createArchive(
            from: [smallFile],
            to: root.appendingPathComponent("tiny.7z"),
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .xz, splitVolumeSizeBytes: 1024 * 1024)
        )
        XCTAssertEqual(singleSplitVols.map(\.lastPathComponent), ["tiny.7z.001"])
        XCTAssertFalse(try BoltArchiveEngine.inspect(archiveURL: singleSplitVols[0]).isSplitVolume)

        // 3. Byte-splitter helper matches exact chunk layout
        let splitDir = root.appendingPathComponent("helper_split", isDirectory: true)
        try FileManager.default.createDirectory(at: splitDir, withIntermediateDirectories: true)
        let sourceBlob = splitDir.appendingPathComponent("raw.bin")
        let rawBytes = pseudoRandomData(count: 140_000)
        try rawBytes.write(to: sourceBlob)
        try SevenZipArchiveWriter.splitFile(sourceBlob, in: splitDir, baseName: "raw.7z", partSize: 65_536)
        let reassembled = try (1...3).reduce(into: Data()) { acc, idx in
            acc.append(try Data(contentsOf: splitDir.appendingPathComponent("raw.7z.00\(idx)")))
        }
        XCTAssertEqual(reassembled, rawBytes)

        // 4. Cancellation preserves existing .7z.001
        let bigFile = root.appendingPathComponent("big.bin")
        try Data(repeating: 0x33, count: 4 * 1024 * 1024).write(to: bigFile)
        let existingVol = root.appendingPathComponent("cancel.7z.001")
        let originalBytes = Data("existing volume 1".utf8)
        try originalBytes.write(to: existingVol)
        let controller = ArchiveTaskController()
        controller.cancel()
        XCTAssertThrowsError(try BoltArchiveEngine.createArchive(
            from: [bigFile],
            to: root.appendingPathComponent("cancel.7z"),
            options: CreateArchiveOptions(format: .sevenZip, algorithm: .store, splitVolumeSizeBytes: 65_536),
            controller: controller
        )) { error in
            guard case BoltZipError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: existingVol), originalBytes)

        // 5. Filename helpers
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/a.7z.001")), .sevenZip)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/a.7z.002")), .sevenZip)
        XCTAssertEqual(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/comic.cb7.001")), .sevenZip)
        XCTAssertNil(ArchiveFormat.detect(from: URL(fileURLWithPath: "/tmp/other.zip.001")))
        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "a.7z.001"), .sevenZip)
        XCTAssertEqual(BoltDocumentIconKind.resolve(forFilename: "a.7z.002"), .sevenZip)
        XCTAssertEqual(BoltArchiveEngine.archiveBaseStem(URL(fileURLWithPath: "/tmp/a.7z.001")), "a")
    }

    private func pseudoRandomData(count: Int) -> Data {
        var bytes = Data(count: count)
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            bytes[i] = UInt8((state >> 32) & 0xFF)
        }
        return bytes
    }
}
