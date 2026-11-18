import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum ZipCrypto {
    public enum AESStrength: UInt8, Sendable {
        case aes128 = 1
        case aes192 = 2
        case aes256 = 3

        public var saltLength: Int {
            switch self {
            case .aes128: return 8
            case .aes192: return 12
            case .aes256: return 16
            }
        }

        public var keyLength: Int {
            switch self {
            case .aes128: return 16
            case .aes192: return 24
            case .aes256: return 32
            }
        }
    }

    // MARK: - WinZip AE-1 / AE-2 AES Encryption

    public static func encryptAES256(plaintext: Data, password: String) throws -> Data {
        let strength = AESStrength.aes256
        var salt = Data(count: strength.saltLength)
        let secStatus = salt.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, strength.saltLength, buf.baseAddress!)
        }
        guard secStatus == errSecSuccess else {
            throw BoltZipError.compressionFailed(BoltCoreLocalization.t("无法生成加密随机盐", "無法產生加密隨機鹽", "Failed to generate random encryption salt", "暗号化ソルトの生成に失敗しました"))
        }

        let (encKey, authKey, pwVerify) = try deriveWinZipAESKeys(
            password: password,
            salt: salt,
            keyLength: strength.keyLength
        )
        let ciphertext = try aesCTRTransform(data: plaintext, key: encKey)
        let fullHmac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: ciphertext, using: SymmetricKey(data: authKey)))
        let authTag = fullHmac.prefix(10)

        var output = Data(capacity: salt.count + 2 + ciphertext.count + 10)
        output.append(salt)
        output.append(pwVerify)
        output.append(ciphertext)
        output.append(authTag)
        return output
    }

    public static func decryptAES(
        payload: Data,
        password: String,
        strength: AESStrength,
        entryName: String
    ) throws -> Data {
        let minOverhead = strength.saltLength + 2 + 10
        guard payload.count >= minOverhead else {
            throw BoltZipError.corruptedEntry(entry: entryName, detail: BoltCoreLocalization.t("AES 加密数据长度不足", "AES 加密資料長度不足", "AES encrypted payload is truncated", "AES 暗号化データの長さが不足しています"))
        }

        let salt = payload.prefix(strength.saltLength)
        let pwVerify = payload.subdata(in: strength.saltLength..<(strength.saltLength + 2))
        let ciphertext = payload.subdata(in: (strength.saltLength + 2)..<(payload.count - 10))
        let authTag = payload.suffix(10)

        let (encKey, authKey, derivedVerify) = try deriveWinZipAESKeys(
            password: password,
            salt: salt,
            keyLength: strength.keyLength
        )

        guard constantTimeEqual(pwVerify, derivedVerify) else {
            throw BoltZipError.wrongPassword(entryName)
        }

        let computedTag = Data(HMAC<Insecure.SHA1>.authenticationCode(for: ciphertext, using: SymmetricKey(data: authKey))).prefix(10)
        guard constantTimeEqual(authTag, computedTag) else {
            throw BoltZipError.corruptedEntry(entry: entryName, detail: BoltCoreLocalization.t("AES HMAC-SHA1 完整性校验未通过", "AES HMAC-SHA1 完整性驗證未通過", "AES HMAC-SHA1 integrity verification failed", "AES HMAC-SHA1 の整合性検証に失敗しました"))
        }

        return try aesCTRTransform(data: ciphertext, key: encKey)
    }

    private static func deriveWinZipAESKeys(
        password: String,
        salt: Data,
        keyLength: Int
    ) throws -> (encKey: Data, authKey: Data, pwVerify: Data) {
        let totalLen = keyLength * 2 + 2
        var derived = Data(count: totalLen)
        let passwordData = Array(password.utf8)

        let rc = derived.withUnsafeMutableBytes { outBuf in
            salt.withUnsafeBytes { saltBuf in
                passwordData.withUnsafeBytes { pwBuf in
                    let pwPtr = pwBuf.bindMemory(to: Int8.self).baseAddress
                    let saltPtr = saltBuf.bindMemory(to: UInt8.self).baseAddress
                    let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr,
                        passwordData.count,
                        saltPtr,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1000,
                        outPtr,
                        totalLen
                    )
                }
            }
        }
        guard rc == kCCSuccess else {
            throw BoltZipError.compressionFailed(BoltCoreLocalization.t("PBKDF2 密钥派生失败 (\(rc))", "PBKDF2 金鑰衍生失敗 (\(rc))", "PBKDF2 key derivation failed (\(rc))", "PBKDF2 鍵導出に失敗しました (\(rc))"))
        }

        let encKey = derived.subdata(in: 0..<keyLength)
        let authKey = derived.subdata(in: keyLength..<(keyLength * 2))
        let pwVerify = derived.subdata(in: (keyLength * 2)..<totalLen)
        return (encKey, authKey, pwVerify)
    }

    /// WinZip AES uses AES-CTR with a 128-bit little-endian counter starting at 1.
    private static func aesCTRTransform(data: Data, key: Data) throws -> Data {
        if data.isEmpty { return Data() }

        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBuf in
            CCCryptorCreate(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionECBMode),
                keyBuf.baseAddress,
                key.count,
                nil,
                &cryptor
            )
        }
        guard status == kCCSuccess, let cryptorRef = cryptor else {
            throw BoltZipError.compressionFailed(BoltCoreLocalization.t("无法初始化 AES-CTR 加密器", "無法初始化 AES-CTR 加密器", "Failed to initialize AES-CTR cipher", "AES-CTR 暗号化器の初期化に失敗しました"))
        }
        defer { CCCryptorRelease(cryptorRef) }

        var counter: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let batchBlocks = 256
        let batchBytes = batchBlocks * 16
        var counterBatch = [UInt8](repeating: 0, count: batchBytes)
        var keystreamBatch = [UInt8](repeating: 0, count: batchBytes)

        var output = Data(count: data.count)
        let inputBytes = [UInt8](data)
        var offset = 0

        output.withUnsafeMutableBytes { outRaw in
            guard let outPtr = outRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            while offset < inputBytes.count {
                let remaining = inputBytes.count - offset
                let blocksNeeded = min(batchBlocks, (remaining + 15) / 16)
                let bytesNeeded = blocksNeeded * 16

                for b in 0..<blocksNeeded {
                    let dstOffset = b * 16
                    for j in 0..<16 {
                        counterBatch[dstOffset + j] = counter[j]
                    }
                    // Little-endian increment
                    for j in 0..<16 {
                        counter[j] &+= 1
                        if counter[j] != 0 { break }
                    }
                }

                var moved = 0
                CCCryptorUpdate(cryptorRef, counterBatch, bytesNeeded, &keystreamBatch, bytesNeeded, &moved)

                let chunkLen = min(remaining, bytesNeeded)
                for i in 0..<chunkLen {
                    outPtr[offset + i] = inputBytes[offset + i] ^ keystreamBatch[i]
                }
                offset += chunkLen
            }
        }
        return output
    }

    private static func constantTimeEqual<D1: DataProtocol, D2: DataProtocol>(_ a: D1, _ b: D2) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) {
            diff |= (x ^ y)
        }
        return diff == 0
    }

    // MARK: - Legacy PKWARE ZipCrypto

    private struct ZipCryptoState {
        var k0: UInt32 = 0x12345678
        var k1: UInt32 = 0x23456789
        var k2: UInt32 = 0x34567890

        init(password: String) {
            for b in password.utf8 {
                updateKeys(b)
            }
        }

        mutating func updateKeys(_ byte: UInt8) {
            k0 = ZipCrypto.crc32Byte(k0, byte)
            k1 = (k1 &+ (k0 & 0xFF)) &* 134775813 &+ 1
            k2 = ZipCrypto.crc32Byte(k2, UInt8((k1 >> 24) & 0xFF))
        }

        func decryptByte() -> UInt8 {
            let temp = (k2 & 0xFFFF) | 2
            return UInt8(((temp &* (temp ^ 1)) >> 8) & 0xFF)
        }
    }

    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32Byte(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
        (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)]
    }

    public static func encryptZipCrypto(plaintext: Data, crc32: UInt32, password: String) throws -> Data {
        var state = ZipCryptoState(password: password)
        var header = [UInt8](repeating: 0, count: 12)
        let sec = SecRandomCopyBytes(kSecRandomDefault, 11, &header)
        guard sec == errSecSuccess else {
            throw BoltZipError.compressionFailed(BoltCoreLocalization.t("无法生成 ZipCrypto 随机数", "無法產生 ZipCrypto 隨機數", "Failed to generate ZipCrypto random header", "ZipCrypto 乱数ヘッダの生成に失敗しました"))
        }
        header[11] = UInt8((crc32 >> 24) & 0xFF)

        var out = Data(capacity: 12 + plaintext.count)
        for b in header {
            let t = state.decryptByte()
            state.updateKeys(b)
            out.append(b ^ t)
        }
        for b in plaintext {
            let t = state.decryptByte()
            state.updateKeys(b)
            out.append(b ^ t)
        }
        return out
    }

    public static func decryptZipCrypto(
        payload: Data,
        crc32: UInt32,
        dosTime: UInt16,
        hasDataDescriptor: Bool,
        password: String,
        entryName: String
    ) throws -> Data {
        guard payload.count >= 12 else {
            throw BoltZipError.corruptedEntry(entry: entryName, detail: BoltCoreLocalization.t("ZipCrypto 数据头部不完整", "ZipCrypto 資料標頭不完整", "Incomplete ZipCrypto encryption header", "ZipCrypto データヘッダが不完全です"))
        }

        var state = ZipCryptoState(password: password)
        let bytes = [UInt8](payload)
        var lastDecryptedByte: UInt8 = 0
        for i in 0..<12 {
            let c = bytes[i] ^ state.decryptByte()
            state.updateKeys(c)
            lastDecryptedByte = c
        }

        let expectedByte = hasDataDescriptor ? UInt8((dosTime >> 8) & 0xFF) : UInt8((crc32 >> 24) & 0xFF)
        let altExpected = UInt8((crc32 >> 24) & 0xFF)
        if lastDecryptedByte != expectedByte && lastDecryptedByte != altExpected {
            throw BoltZipError.wrongPassword(entryName)
        }

        var output = Data(count: bytes.count - 12)
        output.withUnsafeMutableBytes { rawOut in
            guard let ptr = rawOut.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 12..<bytes.count {
                let c = bytes[i] ^ state.decryptByte()
                state.updateKeys(c)
                ptr[i - 12] = c
            }
        }
        return output
    }
}
