import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// Face ID unlock: the master key is encrypted with a key that lives inside the iPhone's
/// Secure Enclave chip and can only be used after a successful Face ID check.
/// If faces are added/removed in iOS settings, the key is invalidated and the password is required.
enum SecureEnclaveVault {
    private struct Blob: Codable {
        var seKey: Data      // opaque handle to the Secure Enclave key (useless outside this chip)
        var ephPub: Data
        var wrapped: Data
    }

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    private static func account(_ space: VaultSpace) -> String { "se.\(space.rawValue)" }

    static func isEnrolled(_ space: VaultSpace) -> Bool { Keychain.get(account(space)) != nil }

    static func enroll(masterKey: SymmetricKey, space: VaultSpace) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
                                                           kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet],
                                                           &error) else {
            throw CryptoError.badData
        }
        let se = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let eph = P256.KeyAgreement.PrivateKey()
        let shared = try eph.sharedSecretFromKeyAgreement(with: se.publicKey)
        let kek = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: Data("AYN-SE".utf8),
                                                 sharedInfo: eph.publicKey.x963Representation,
                                                 outputByteCount: 32)
        let wrapped = try AYNCrypto.seal(masterKey.rawData, key: kek)
        let blob = Blob(seKey: se.dataRepresentation, ephPub: eph.publicKey.x963Representation, wrapped: wrapped)
        let data = try JSONEncoder().encode(blob)
        Keychain.set(data, account: account(space), accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    static func unlock(space: VaultSpace, context: LAContext) throws -> SymmetricKey {
        guard let data = Keychain.get(account(space)) else { throw CryptoError.badData }
        let blob = try JSONDecoder().decode(Blob.self, from: data)
        let se = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob.seKey, authenticationContext: context)
        let ephPub = try P256.KeyAgreement.PublicKey(x963Representation: blob.ephPub)
        let shared = try se.sharedSecretFromKeyAgreement(with: ephPub)
        let kek = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                 salt: Data("AYN-SE".utf8),
                                                 sharedInfo: blob.ephPub,
                                                 outputByteCount: 32)
        return SymmetricKey(data: try AYNCrypto.open(blob.wrapped, key: kek))
    }

    static func remove(_ space: VaultSpace) { Keychain.delete(account(space)) }
}

enum Biometrics {
    static var biometryType: LABiometryType {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var name: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return tr("البصمة", "Biometrics")
        }
    }

    static var icon: String {
        switch biometryType {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    /// Returns an authenticated context (re-usable for the Secure Enclave key) or nil.
    static func authenticate(reason: String) async -> LAContext? {
        let c = LAContext()
        c.localizedFallbackTitle = ""
        c.localizedCancelTitle = tr("إلغاء", "Cancel")
        do {
            let ok = try await c.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return ok ? c : nil
        } catch {
            return nil
        }
    }
}
