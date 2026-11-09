import Foundation
import CryptoKit

/// On-disk layout (Application Support/AYN/<space>/):
///   meta.json          plain: salts + wrapped master keys (no secrets)
///   profile.enc        AES-GCM(profile)
///   accounts.enc       AES-GCM([AccountItem])
///   notes.enc          AES-GCM([SecureNote])
///   files.enc          AES-GCM([VaultFile])
///   blobs/<id>.bin     chunked AES-GCM file contents
///   reminders.enc      AES-GCM([Reminder]) with a device key (so Siri & notification buttons work while locked)
///   inbox/<id>.bin     public-key sealed events (intruder photos) written while locked
enum VaultStorage {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Saver", isDirectory: true)
    }

    static func dir(_ space: VaultSpace) -> URL {
        let d = root.appendingPathComponent(space.rawValue, isDirectory: true)
        ensure(d)
        return d
    }

    static func blobsDir(_ space: VaultSpace) -> URL {
        let d = dir(space).appendingPathComponent("blobs", isDirectory: true)
        ensure(d)
        return d
    }

    static func inboxDir(_ space: VaultSpace) -> URL {
        let d = dir(space).appendingPathComponent("inbox", isDirectory: true)
        ensure(d, protection: .completeUntilFirstUserAuthentication)
        return d
    }

    static func blobURL(_ id: UUID, space: VaultSpace) -> URL {
        blobsDir(space).appendingPathComponent(id.uuidString + ".bin")
    }

    static var tempDir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("saver-view", isDirectory: true)
        ensure(d)
        return d
    }

    static func clearTemp() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private static func ensure(_ url: URL, protection: FileProtectionType = .complete) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: protection])
        }
    }

    // MARK: meta

    static func metaURL(_ space: VaultSpace) -> URL { dir(space).appendingPathComponent("meta.json") }

    static func exists(_ space: VaultSpace) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(space.rawValue).appendingPathComponent("meta.json").path)
    }

    static func loadMeta(_ space: VaultSpace) -> VaultMeta? {
        guard let data = try? Data(contentsOf: metaURL(space)) else { return nil }
        return try? JSONDecoder().decode(VaultMeta.self, from: data)
    }

    static func saveMeta(_ meta: VaultMeta, _ space: VaultSpace) throws {
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL(space), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: encrypted collections

    static func load<T: Decodable>(_ type: T.Type, _ name: String, space: VaultSpace, key: SymmetricKey) -> T? {
        let url = dir(space).appendingPathComponent(name)
        guard let sealed = try? Data(contentsOf: url),
              let plain = try? AYNCrypto.open(sealed, key: key, aad: Data(name.utf8)) else { return nil }
        return try? PropertyListDecoder().decode(T.self, from: plain)
    }

    static func save<T: Encodable>(_ value: T, _ name: String, space: VaultSpace, key: SymmetricKey,
                                   protection: Data.WritingOptions = .completeFileProtection) throws {
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        let plain = try enc.encode(value)
        let sealed = try AYNCrypto.seal(plain, key: key, aad: Data(name.utf8))
        try sealed.write(to: dir(space).appendingPathComponent(name), options: [.atomic, protection])
    }

    static func wipe(_ space: VaultSpace) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(space.rawValue))
        SecureEnclaveVault.remove(space)
        Keychain.delete("rem.key.\(space.rawValue)")
    }

    static func wipeAll() {
        try? FileManager.default.removeItem(at: root)
        Keychain.deleteAll()
        clearTemp()
    }

    // MARK: inbox (sealed to the vault public key — works while locked)

    static func writeInbox(_ event: IntruderEvent, space: VaultSpace = .real) {
        guard let meta = loadMeta(space),
              let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: meta.inboxPublicKey) else { return }
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        guard let plain = try? enc.encode(event),
              let sealed = try? AYNCrypto.sealToPublicKey(plain, recipient: pub) else { return }
        let url = inboxDir(space).appendingPathComponent(event.id.uuidString + ".bin")
        try? sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func readInbox(space: VaultSpace, privateKey: Curve25519.KeyAgreement.PrivateKey) -> [IntruderEvent] {
        let dir = inboxDir(space)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [IntruderEvent] = []
        for f in files {
            guard let sealed = try? Data(contentsOf: f),
                  let plain = try? AYNCrypto.openFromPublicKey(sealed, privateKey: privateKey),
                  let e = try? PropertyListDecoder().decode(IntruderEvent.self, from: plain) else { continue }
            out.append(e)
        }
        return out.sorted { $0.date > $1.date }
    }

    static func deleteInbox(_ id: UUID?, space: VaultSpace) {
        if let id {
            try? FileManager.default.removeItem(at: inboxDir(space).appendingPathComponent(id.uuidString + ".bin"))
        } else {
            try? FileManager.default.removeItem(at: inboxDir(space))
        }
    }
}

/// Reminders use a separate device-bound key (Keychain, available after first unlock)
/// so Siri, widgets and notification buttons ("Done", "Snooze") work while AYN is locked.
/// A copy of that key is kept inside the encrypted profile so it survives a restore.
enum RemindersStore {
    private static let fileName = "reminders.enc"

    static func key(_ space: VaultSpace) -> SymmetricKey? {
        guard let d = Keychain.get("rem.key.\(space.rawValue)") else { return nil }
        return SymmetricKey(data: d)
    }

    static func installKey(_ data: Data, space: VaultSpace) {
        Keychain.set(data, account: "rem.key.\(space.rawValue)")
    }

    static func load(_ space: VaultSpace) -> [Reminder] {
        guard VaultStorage.exists(space), let k = key(space) else { return [] }
        return VaultStorage.load([Reminder].self, fileName, space: space, key: k) ?? []
    }

    static func save(_ list: [Reminder], _ space: VaultSpace) {
        guard let k = key(space) else { return }
        try? VaultStorage.save(list, fileName, space: space, key: k,
                               protection: .completeFileProtectionUntilFirstUserAuthentication)
        if space == .real { UserDefaults.standard.set(true, forKey: "backup.dirty") }
    }

    static func update(_ space: VaultSpace, _ id: UUID, _ change: (inout Reminder) -> Void) {
        var list = load(space)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        save(list, space)
    }
}
