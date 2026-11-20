import Foundation
import XCTest
@testable import BoltZipCore

final class ApplicationPackageEditingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipPackageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ path: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func run(_ executable: String, _ args: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        if !allowFailure { XCTAssertEqual(process.terminationStatus, 0, text) }
        return text
    }

    private func jarFixture() throws -> URL {
        guard try run("/usr/bin/javac", ["-version"], allowFailure: true).contains("javac ") else { throw XCTSkip("JDK unavailable") }
        let java = try write("Main.java", Data("""
        import java.nio.charset.StandardCharsets;
        import java.io.*;
        import java.util.jar.*;
        public class Main {
            public static void main(String[] args) throws Exception {
                if (args.length > 0) {
                    try (JarInputStream in = new JarInputStream(new FileInputStream(args[0]))) {
                        System.out.print(in.getManifest().getMainAttributes().getValue("Main-Class"));
                    }
                } else {
                    try (InputStream in = Main.class.getResourceAsStream("/message.txt")) {
                        ByteArrayOutputStream out = new ByteArrayOutputStream();
                        byte[] b = new byte[512]; int n;
                        while ((n = in.read(b)) >= 0) out.write(b, 0, n);
                        System.out.print(new String(out.toByteArray(), StandardCharsets.UTF_8).trim());
                    }
                }
            }
        }
        """.utf8))
        _ = try run("/usr/bin/javac", ["--release", "8", java.path])
        let manifest = try write("META-INF/MANIFEST.MF", Data("Manifest-Version: 1.0\r\nMain-Class: Main\r\n\r\n".utf8))
        let jar = root.appendingPathComponent("application.jar")
        try BoltArchiveEngine.createArchive(from: [manifest.deletingLastPathComponent(), root.appendingPathComponent("Main.class")],
            to: jar, options: CreateArchiveOptions(algorithm: .store))
        let message = try write("message.txt", Data(("before" + String(repeating: " ", count: 200)).utf8))
        try BoltArchiveEngine.editZip(at: jar, operations: [.addItems(urls: [message], targetFolder: "")], options: CreateArchiveOptions(algorithm: .deflate))
        return jar
    }

    func testRunnableJARRemainsRunnableAndRetainsMixedEntryMethods() throws {
        let jar = try jarFixture()
        XCTAssertEqual(try run("/usr/bin/java", ["-jar", jar.path]), "before")
        let reader = ZipReader(url: jar)
        let before = try reader.parseArchive()
        let accessor = try ZipVolumeAccessor(archiveURL: jar)
        defer { accessor.closeAll() }
        try accessor.configureVolumes(totalDisks: 1)
        let untouched = try XCTUnwrap(before.records.first { String(data: $0.rawPathBytes, encoding: .utf8) == "Main.class" })
        let rawClass = try reader.readRawPayload(for: untouched, accessor: accessor)
        let changed = try write("edited-message.txt", Data("after".utf8))
        try BoltArchiveEngine.editZip(at: jar, operations: [.replaceEntry(path: "message.txt", fileURL: changed)])
        XCTAssertEqual(try run("/usr/bin/java", ["-jar", jar.path]), "after")
        XCTAssertEqual(try run("/usr/bin/java", ["-jar", jar.path, jar.path]), "Main")
        XCTAssertEqual(try BoltArchiveEngine.entryCompressionProfile(at: jar, path: "message.txt").method, 8)
        XCTAssertEqual(try BoltArchiveEngine.entryCompressionProfile(at: jar, path: "META-INF/MANIFEST.MF").method, 0)
        let afterReader = ZipReader(url: jar), afterAccessor = try ZipVolumeAccessor(archiveURL: jar)
        defer { afterAccessor.closeAll() }
        try afterAccessor.configureVolumes(totalDisks: 1)
        let after = try afterReader.parseArchive()
        XCTAssertEqual(before.records.map(\.rawPathBytes), after.records.map(\.rawPathBytes))
        let newClass = try XCTUnwrap(after.records.first { $0.rawPathBytes == untouched.rawPathBytes })
        XCTAssertEqual(try afterReader.readRawPayload(for: newClass, accessor: afterAccessor), rawClass)
    }

    func testUnsupportedReplacementOffersARealZIPWithoutChangingSource() throws {
        let file = try write("payload.txt", Data(String(repeating: "payload", count: 100).utf8))
        let archive = root.appendingPathComponent("original.jar")
        try BoltArchiveEngine.createArchive(from: [file], to: archive, options: CreateArchiveOptions())
        var bytes = try Data(contentsOf: archive)
        // Method 9 (Deflate64) is readable through libarchive but is not a writer codec.
        // Only inspect the preflight failure here; exporting a supported source is tested below.
        if let central = bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])) {
            bytes[central.lowerBound + 10] = 9; bytes[central.lowerBound + 11] = 0
        }
        try bytes.write(to: archive)
        let changed = try write("replacement.txt", Data("new".utf8))
        XCTAssertThrowsError(try BoltArchiveEngine.editZip(at: archive, operations: [.replaceEntry(path: "payload.txt", fileURL: changed)]))
        XCTAssertEqual(try Data(contentsOf: archive), bytes)

        let source = root.appendingPathComponent("source.jar")
        try BoltArchiveEngine.createArchive(from: [file], to: source, options: CreateArchiveOptions())
        let before = try Data(contentsOf: source), output = root.appendingPathComponent("fallback.zip")
        try BoltArchiveEngine.exportEditedArchiveAsZip(at: source, to: output, operations: [.replaceEntry(path: "payload.txt", fileURL: changed)])
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: output, entryPath: "payload.txt"), Data("new".utf8))
    }

    func testReplacementReusesEverySupportedMethodAndOriginalEncryption() throws {
        let archive = root.appendingPathComponent("mixed.jar")
        let methods: [CompressionAlgorithm] = [.store, .deflate, .bzip2, .zstd]
        let plain = Data(String(repeating: "original payload", count: 100).utf8)
        var files: [URL] = []
        for (index, method) in methods.enumerated() {
            let file = try write("entry-\(index).txt", plain)
            files.append(file)
            let options = CreateArchiveOptions(algorithm: method, level: method == .bzip2 ? 3 : nil,
                encryption: index == 2 ? .zipCrypto : .none, password: index == 2 ? "fixture" : nil)
            if index == 0 { try BoltArchiveEngine.createArchive(from: [file], to: archive, options: options) }
            else { try BoltArchiveEngine.editZip(at: archive, operations: [.addItems(urls: [file], targetFolder: "")], options: options) }
        }
        for file in files { try Data("x".utf8).write(to: file) }
        // Adding same-name files is also replacement; preserve entry order and storage policy.
        try BoltArchiveEngine.editZip(at: archive, operations: [.addItems(urls: files, targetFolder: "")],
            options: CreateArchiveOptions(algorithm: .store, encryption: .aes256, password: "fixture"))
        let records = try ZipReader(url: archive).parseArchive().records
        XCTAssertEqual(records.map(\.compressionMethod), [0, 8, 12, 93])
        XCTAssertEqual(records.map { $0.flags & 1 != 0 }, [false, false, true, false])
        XCTAssertTrue(try ZipReader(url: archive).testIntegrity(password: "fixture").isHealthy)
        for file in files {
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: file.lastPathComponent, password: "fixture"), Data("x".utf8))
        }
    }

    func testAPKOpensAndSavesWithoutSigningConfiguration() throws {
        let manifest = try write("AndroidManifest.xml", Data([0x03, 0x00, 0x08, 0x00]))
        let library = try write("libfixture.so", Data(repeating: 0x42, count: 2048))
        let apk = root.appendingPathComponent("application.apk")
        try BoltArchiveEngine.createArchive(from: [manifest, library], to: apk, options: CreateArchiveOptions(algorithm: .store))
        let resource = try write("message.txt", Data(("before" + String(repeating: " ", count: 100)).utf8))
        try BoltArchiveEngine.editZip(at: apk, operations: [.addItems(urls: [resource], targetFolder: "assets/")])
        // A v2-style signing block can appear between the last payload and the central directory.
        // Saving has no signing dependency, including when such an opaque block is present.
        var bytes = try Data(contentsOf: apk)
        let end = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards)).lowerBound
        let central = Int(ZipBinary.readUInt32LE(bytes, at: end + 16))
        var block = Data()
        ZipBinary.appendUInt64LE(&block, 24)
        ZipBinary.appendUInt64LE(&block, 24)
        block.append(Data("APK Sig Block 42".utf8))
        bytes.insert(contentsOf: block, at: central)
        var offset = Data()
        ZipBinary.appendUInt32LE(&offset, UInt32(central + block.count))
        bytes.replaceSubrange((end + block.count + 16)..<(end + block.count + 20), with: offset)
        try bytes.write(to: apk)
        XCTAssertTrue(try BoltArchiveEngine.inspect(archiveURL: apk).canEditInPlace)
        let originalManifest = try BoltArchiveEngine.readEntryData(archiveURL: apk, entryPath: "AndroidManifest.xml")
        let edited = try write("edited.txt", Data("edited".utf8))
        try BoltArchiveEngine.editZip(at: apk, operations: [.replaceEntry(path: "assets/message.txt", fileURL: edited)])
        XCTAssertEqual(try BoltArchiveEngine.entryCompressionProfile(at: apk, path: "assets/message.txt").method, 8)
        XCTAssertEqual(try BoltArchiveEngine.entryCompressionProfile(at: apk, path: "libfixture.so").method, 0)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: apk, entryPath: "AndroidManifest.xml"), originalManifest)
        XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: apk, entryPath: "assets/message.txt"), Data("edited".utf8))
        XCTAssertTrue(try ZipReader(url: apk).testIntegrity().isHealthy)
    }
}
