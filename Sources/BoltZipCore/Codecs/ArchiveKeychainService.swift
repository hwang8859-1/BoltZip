import Foundation
import Security

public protocol KeychainBackend: Sendable {
    func readPassword(account: String, service: String) throws -> String?
    func savePassword(_ password: String, account: String, service: String) throws
    func deletePassword(account: String, service: String) throws
    func deleteAllPasswords(service: String) throws -> Int
    func savedPasswordCount(service: String) -> Int
}

public struct SecurityKeychainBackend: KeychainBackend {
    public init() {}

    public func readPassword(account: String, service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    public func savePassword(_ password: String, account: String, service: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
        var addItem = query
        addItem[kSecValueData as String] = data
        addItem[kSecAttrLabel as String] = "BoltZip: \(URL(fileURLWithPath: account).lastPathComponent)"
        addItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    public func deletePassword(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func deleteAllPasswords(service: String) throws -> Int {
        let count = savedPasswordCount(service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return count
    }

    public func savedPasswordCount(service: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let list = result as? [[String: Any]] else {
            return 0
        }
        return list.count
    }
}

public final class ArchiveKeychainService: @unchecked Sendable {
    public static let defaultService = "com.boltzip.archive-passwords"
    public static let shared = ArchiveKeychainService()

    private let backend: any KeychainBackend
    private let service: String

    public init(
        backend: any KeychainBackend = SecurityKeychainBackend(),
        service: String = ArchiveKeychainService.defaultService
    ) {
        self.backend = backend
        self.service = service
    }

    public static func accountKey(for archiveURL: URL) -> String {
        let resolved = archiveURL.standardizedFileURL.resolvingSymlinksInPath()
        let stripped7z = SevenZipVolumeDiscovery.stripSplitSuffix(from: resolved)
        if stripped7z.path != resolved.path {
            return stripped7z.path.precomposedStringWithCanonicalMapping
        }
        let ext = resolved.pathExtension.lowercased()
        if ext.count >= 2, ext.hasPrefix("z"), Int(ext.dropFirst()) != nil {
            return resolved.deletingPathExtension().appendingPathExtension("zip").path.precomposedStringWithCanonicalMapping
        }
        return resolved.path.precomposedStringWithCanonicalMapping
    }

    public func password(for archiveURL: URL) -> String? {
        try? backend.readPassword(account: Self.accountKey(for: archiveURL), service: service)
    }

    public func savePassword(_ password: String, for archiveURL: URL) throws {
        guard !password.isEmpty else { return }
        try backend.savePassword(password, account: Self.accountKey(for: archiveURL), service: service)
    }

    public func removePassword(for archiveURL: URL) throws {
        try backend.deletePassword(account: Self.accountKey(for: archiveURL), service: service)
    }

    @discardableResult
    public func removeAllPasswords() throws -> Int {
        try backend.deleteAllPasswords(service: service)
    }

    public func savedCount() -> Int {
        backend.savedPasswordCount(service: service)
    }
}
