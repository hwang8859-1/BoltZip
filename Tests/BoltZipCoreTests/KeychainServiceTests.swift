import Foundation
import os
import XCTest
@testable import BoltZipCore

private final class InMemoryKeychainBackend: KeychainBackend {
    private let lock = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    private func composite(account: String, service: String) -> String {
        "\(service)::\(account)"
    }

    func readPassword(account: String, service: String) throws -> String? {
        let key = composite(account: account, service: service)
        return lock.withLock { $0[key] }
    }

    func savePassword(_ password: String, account: String, service: String) throws {
        let key = composite(account: account, service: service)
        lock.withLock { $0[key] = password }
    }

    func deletePassword(account: String, service: String) throws {
        let key = composite(account: account, service: service)
        lock.withLock { _ = $0.removeValue(forKey: key) }
    }

    func deleteAllPasswords(service: String) throws -> Int {
        let prefix = "\(service)::"
        return lock.withLock { dict in
            let matches = dict.keys.filter { $0.hasPrefix(prefix) }
            for k in matches { dict.removeValue(forKey: k) }
            return matches.count
        }
    }

    func savedPasswordCount(service: String) -> Int {
        let prefix = "\(service)::"
        return lock.withLock { dict in
            dict.keys.filter { $0.hasPrefix(prefix) }.count
        }
    }
}

final class KeychainServiceTests: XCTestCase {
    func testKeychainNormalizesSplitVolumeAccountKeysAndSupportsRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipKC-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ArchiveKeychainService(backend: InMemoryKeychainBackend(), service: "test.boltzip")

        let zipMain = root.appendingPathComponent("split.zip")
        let zipPart = root.appendingPathComponent("split.z01")
        try Data().write(to: zipMain)
        try Data().write(to: zipPart)

        let seven001 = root.appendingPathComponent("archive.7z.001")
        let seven002 = root.appendingPathComponent("archive.7z.002")
        try Data().write(to: seven001)
        try Data().write(to: seven002)

        try service.savePassword("pw-zip", for: zipPart)
        XCTAssertEqual(service.password(for: zipMain), "pw-zip")
        XCTAssertEqual(service.password(for: zipPart), "pw-zip")

        try service.savePassword("pw-7z", for: seven001)
        XCTAssertEqual(service.password(for: seven002), "pw-7z")
        XCTAssertEqual(service.savedCount(), 2)

        // Updating overwrites cleanly rather than duplicating
        try service.savePassword("pw-7z-new", for: seven002)
        XCTAssertEqual(service.password(for: seven001), "pw-7z-new")
        XCTAssertEqual(service.savedCount(), 2)

        try service.removePassword(for: zipMain)
        XCTAssertNil(service.password(for: zipPart))
        XCTAssertEqual(service.savedCount(), 1)

        let cleared = try service.removeAllPasswords()
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(service.savedCount(), 0)
        XCTAssertNil(service.password(for: seven001))
    }
}
