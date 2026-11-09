import Foundation
import CryptoKit
import CommonCrypto
import Security

enum CryptoError: Error {
    case kdf, badData, truncated
}

/// All cryptography used by AYN.
/// - Vault data: AES-256-GCM with a random 256-bit master key.
/// - Master key is wrapped by: password (PBKDF2-SHA256, 600k rounds), recovery key, and a Secure Enclave key (Face ID).
enum AYNCrypto {
    static let pbkdfRounds: UInt32 = 600_000

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    static func newMasterKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func pbkdf2(_ password: String, salt: Data, rounds: UInt32 = pbkdfRounds) throws -> SymmetricKey {
        let pw = password.precomposedStringWithCanonicalMapping
        var derived = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                          pw, pw.utf8.count,
                                          saltBytes, saltBytes.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                          rounds,
                                          &derived, derived.count)
        guard status == Int32(kCCSuccess) else { throw CryptoError.kdf }
        return SymmetricKey(data: derived)
    }

    static func seal(_ data: Data, key: SymmetricKey, aad: Data? = nil) throws -> Data {
        let box: AES.GCM.SealedBox
        if let aad { box = try AES.GCM.seal(data, using: key, authenticating: aad) }
        else { box = try AES.GCM.seal(data, using: key) }
        guard let combined = box.combined else { throw CryptoError.badData }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey, aad: Data? = nil) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: Data(data))
        if let aad { return try AES.GCM.open(box, using: key, authenticating: aad) }
        return try AES.GCM.open(box, using: key)
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }

    // MARK: Inbox (anonymous public-key encryption)
    // Used while the vault is LOCKED (intruder photos, screenshot log):
    // anyone can encrypt to the public key, only the unlocked vault can read.

    static func sealToPublicKey(_ data: Data, recipient: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let eph = Curve25519.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: recipient)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: eph.publicKey.rawRepresentation,
                                                 sharedInfo: Data("AYN-INBOX".utf8),
                                                 outputByteCount: 32)
        return eph.publicKey.rawRepresentation + (try seal(data, key: key))
    }

    static func openFromPublicKey(_ data: Data, privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard data.count > 32 else { throw CryptoError.badData }
        let ephRaw = Data(data.prefix(32))
        let eph = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: eph)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: ephRaw,
                                                 sharedInfo: Data("AYN-INBOX".utf8),
                                                 outputByteCount: 32)
        return try open(Data(data.dropFirst(32)), key: key)
    }

    // MARK: Chunked file encryption (for photos / videos / documents of any size)
    // Format: "AYN1" + UInt64 plaintext size, then repeated [UInt32 len][AES-GCM combined chunk].
    // Each chunk authenticates header + chunk index, so chunks can't be reordered, swapped or dropped.

    static let chunkSize = 1 << 20
    private static let magic = Data("AYN1".utf8)

    private static func beBytes<T: FixedWidthInteger>(_ v: T) -> Data {
        var be = v.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    private static func readBE(_ d: Data) -> UInt64 {
        var v: UInt64 = 0
        for b in d { v = (v << 8) | UInt64(b) }
        return v
    }

    static func encryptFile(from src: URL, to dst: URL, key: SymmetricKey) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        try? FileManager.default.removeItem(at: dst)
        FileManager.default.createFile(atPath: dst.path, contents: nil,
                                       attributes: [.protectionKey: FileProtectionType.complete])
        let out = try FileHandle(forWritingTo: dst)
        defer { try? out.close() }

        let header = magic + beBytes(size)
        try out.write(contentsOf: header)
        var index: UInt64 = 0
        var written: UInt64 = 0
        while true {
            let chunk = try autoreleasepool { try input.read(upToCount: chunkSize) } ?? Data()
            if chunk.isEmpty { break }
            let sealed = try seal(chunk, key: key, aad: header + beBytes(index))
            try out.write(contentsOf: beBytes(UInt32(sealed.count)))
            try out.write(contentsOf: sealed)
            index += 1
            written += UInt64(chunk.count)
        }
        guard written == size else { throw CryptoError.truncated }
    }

    static func encryptData(_ data: Data, to dst: URL, key: SymmetricKey) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tmp, options: [.completeFileProtection])
        defer { try? FileManager.default.removeItem(at: tmp) }
        try encryptFile(from: tmp, to: dst, key: key)
    }

    static func decryptFile(from src: URL, to dst: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        guard let header = try input.read(upToCount: 12), header.count == 12, header.prefix(4) == magic else {
            throw CryptoError.badData
        }
        let total = readBE(header.suffix(8))
        try? FileManager.default.removeItem(at: dst)
        FileManager.default.createFile(atPath: dst.path, contents: nil,
                                       attributes: [.protectionKey: FileProtectionType.complete])
        let out = try FileHandle(forWritingTo: dst)
        defer { try? out.close() }
        var index: UInt64 = 0
        var written: UInt64 = 0
        while true {
            guard let lenData = try input.read(upToCount: 4), lenData.count == 4 else { break }
            let len = Int(readBE(lenData))
            guard len > 0, len < chunkSize + 64, let sealed = try input.read(upToCount: len), sealed.count == len else {
                throw CryptoError.badData
            }
            let plain = try open(sealed, key: key, aad: Data(header) + beBytes(index))
            try out.write(contentsOf: plain)
            written += UInt64(plain.count)
            index += 1
        }
        guard written == total else { throw CryptoError.truncated }
    }

    static func decryptToData(from src: URL, key: SymmetricKey) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try decryptFile(from: src, to: tmp, key: key)
        return try Data(contentsOf: tmp)
    }
}

extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

// MARK: - Keychain

enum Keychain {
    static let service = "com.mnlovo.saver"

    @discardableResult
    static func set(_ data: Data, account: String,
                    accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) -> Bool {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
