import SwiftUI
import CryptoKit
import LocalAuthentication
import UserNotifications

enum AppError: LocalizedError {
    case wrongPassword, samePassword, identityMismatch, wrongRecovery, locked, notUnlocked, badBackup

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return tr("كلمة السر غلط.", "Wrong password.")
        case .samePassword: return tr("لازم تكون مختلفة عن كلمة السر الأساسية.", "It must differ from your main password.")
        case .identityMismatch: return tr("المعلومات ما تطابق صاحب الحساب.", "The details don't match the account owner.")
        case .wrongRecovery: return tr("مفتاح الاسترجاع غلط.", "Wrong recovery key.")
        case .locked: return tr("التطبيق مقفل مؤقتاً بسبب محاولات كثيرة.", "Temporarily locked after too many attempts.")
        case .notUnlocked: return tr("الخزنة مقفلة.", "The vault is locked.")
        case .badBackup: return tr("ملف النسخة الاحتياطية تالف أو كلمة السر غلط.", "Backup file is damaged or the password is wrong.")
        }
    }
}

struct NewAccountInput {
    var username = ""
    var email = ""
    var phone = ""
    var birthDate = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    var password = ""
    var totp = TOTP.generate(issuer: "MNLOVO AYN", account: "")
    var recoveryKey = PasswordTools.recoveryKey()
    var emailVerified = false
    var enableBiometrics = true
}

struct BackupBundle: Codable {
    var version = 1
    var created = Date()
    var meta: VaultMeta
    var payload: Data
}

struct BackupPayload: Codable {
    var profile: Profile
    var accounts: [AccountItem]
    var notes: [SecureNote]
    var files: [VaultFile]
    var blobs: [String: Data]
    var reminders: [Reminder]
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case intro, welcome, locked, unlocked }
    enum UnlockOutcome: Equatable { case needs2FA, wrong, lockedOut(Date) }

    @Published var phase: Phase = .intro
    @Published private(set) var space: VaultSpace = .real
    @Published var profile: Profile?
    @Published var accounts: [AccountItem] = []
    @Published var notes: [SecureNote] = []
    @Published var files: [VaultFile] = []
    @Published var reminders: [Reminder] = []
    @Published var sectionUnlocked = false
    @Published var toast: Toast?
    @Published var privacyCover = false
    @Published var screenCaptured = false
    @Published var busy: String?
    @Published var newIntrusions = 0

    private var masterKey: SymmetricKey?
    private var pending: (space: VaultSpace, key: SymmetricKey)?
    private var backgroundedAt: Date?
    private let defaults = UserDefaults.standard

    init() {
        if !defaults.bool(forKey: "app.installed") {
            // Keychain survives app deletion — start clean after a reinstall.
            if !VaultStorage.exists(.real) { Keychain.deleteAll() }
            defaults.set(true, forKey: "app.installed")
        }
    }

    // MARK: - Status

    var hasAccount: Bool { VaultStorage.exists(.real) }
    var isDecoy: Bool { space == .decoy }
    var isUnlocked: Bool { masterKey != nil }
    var displayName: String { VaultStorage.loadMeta(.real)?.displayName ?? "" }
    var hasDuress: Bool { VaultStorage.exists(.decoy) }
    var hasSectionPassword: Bool { profile?.sectionHash != nil }

    var autoLockSeconds: Int {
        get { defaults.object(forKey: "sec.autolock") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "sec.autolock"); objectWillChange.send() }
    }
    var fullLoginDays: Int { defaults.object(forKey: "sec.fullLoginDays") as? Int ?? 14 }
    var biometricsOn: Bool { (defaults.object(forKey: "sec.biometric") as? Bool ?? false) && SecureEnclaveVault.isEnrolled(.real) }
    var fullLoginExpired: Bool {
        let last = defaults.double(forKey: "sec.lastFullLogin")
        return last == 0 || Date().timeIntervalSince1970 - last > Double(fullLoginDays) * 86400
    }
    var canUseBiometrics: Bool { biometricsOn && Biometrics.isAvailable && !fullLoginExpired }

    var lockedUntil: Date? {
        let t = defaults.double(forKey: "sec.lockUntil")
        return t > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: t) : nil
    }

    func finishIntro() {
        withAnimation(.easeInOut(duration: 0.5)) { phase = hasAccount ? .locked : .welcome }
    }

    func show(_ text: String, icon: String = "checkmark.circle.fill", style: Toast.Style = .success) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = Toast(text: text, icon: icon, style: style) }
    }

    // MARK: - Key helpers (run off the main thread)

    nonisolated static func wrap(_ key: SymmetricKey, secret: String, tag: String) throws -> (salt: Data, wrapped: Data) {
        let salt = AYNCrypto.randomBytes(16)
        let kek = try AYNCrypto.pbkdf2(secret, salt: salt)
        return (salt, try AYNCrypto.seal(key.rawData, key: kek, aad: Data(tag.utf8)))
    }

    nonisolated static func unwrap(_ secret: String, salt: Data?, wrapped: Data?, tag: String) async -> SymmetricKey? {
        let s = salt ?? AYNCrypto.randomBytes(16)
        let w = wrapped ?? AYNCrypto.randomBytes(60)
        return await Task.detached(priority: .userInitiated) { () -> SymmetricKey? in
            guard let kek = try? AYNCrypto.pbkdf2(secret, salt: s),
                  let raw = try? AYNCrypto.open(w, key: kek, aad: Data(tag.utf8)) else { return nil }
            return SymmetricKey(data: raw)
        }.value
    }

    nonisolated static func identityString(email: String, phone: String, birth: Date) -> String {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = TOTP.westernDigits(phone).filter { $0.isASCII && $0.isNumber }
        let tail = String(digits.suffix(9))
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "\(mail)|\(tail)|\(f.string(from: birth))"
    }

    // MARK: - Create account

    func createAccount(_ n: NewAccountInput) async throws {
        let mk = AYNCrypto.newMasterKey()
        let inbox = Curve25519.KeyAgreement.PrivateKey()
        let remKey = AYNCrypto.randomBytes(32)
        let identity = Self.identityString(email: n.email, phone: n.phone, birth: n.birthDate)
        let recovery = PasswordTools.normalizeRecovery(n.recoveryKey)

        let built = try await Task.detached(priority: .userInitiated) { () -> VaultMeta in
            let pw = try Self.wrap(mk, secret: n.password, tag: "pw")
            let rk = try Self.wrap(mk, secret: recovery, tag: "rk")
            let idSalt = AYNCrypto.randomBytes(16)
            let idHash = try AYNCrypto.pbkdf2(identity, salt: idSalt).rawData
            return VaultMeta(displayName: n.username, salt: pw.salt, wrappedByPassword: pw.wrapped,
                             recoverySalt: rk.salt, wrappedByRecovery: rk.wrapped,
                             identitySalt: idSalt, identityHash: idHash,
                             inboxPublicKey: inbox.publicKey.rawRepresentation)
        }.value

        var totp = n.totp
        totp.account = n.username
        let prof = Profile(username: n.username, email: n.email.lowercased(), phone: n.phone, birthDate: n.birthDate,
                           emailVerified: n.emailVerified, totp: totp,
                           inboxPrivateKey: inbox.rawRepresentation, remindersKey: remKey)

        VaultStorage.wipe(.real)
        try VaultStorage.saveMeta(built, .real)
        try VaultStorage.save(prof, "profile.enc", space: .real, key: mk)
        try VaultStorage.save([AccountItem](), "accounts.enc", space: .real, key: mk)
        try VaultStorage.save([SecureNote](), "notes.enc", space: .real, key: mk)
        try VaultStorage.save([VaultFile](), "files.enc", space: .real, key: mk)
        RemindersStore.installKey(remKey, space: .real)
        RemindersStore.save([], .real)

        if n.enableBiometrics && Biometrics.isAvailable && SecureEnclaveVault.isAvailable {
            try? SecureEnclaveVault.enroll(masterKey: mk, space: .real)
            defaults.set(true, forKey: "sec.biometric")
        }
        markFullLogin()
        openVault(.real, key: mk, profile: prof)
    }

    // MARK: - Unlock

    func unlock(password: String) async -> UnlockOutcome {
        if let until = lockedUntil { return .lockedOut(until) }
        let real = VaultStorage.loadMeta(.real)
        let decoy = VaultStorage.loadMeta(.decoy)
        // Both are always computed so the timing never reveals whether a decoy vault exists.
        async let r = Self.unwrap(password, salt: real?.salt, wrapped: real?.wrappedByPassword, tag: "pw")
        async let d = Self.unwrap(password, salt: decoy?.salt, wrapped: decoy?.wrappedByPassword, tag: "pw")
        let (rk, dk) = await (r, d)
        if let rk { pending = (.real, rk); return .needs2FA }
        if let dk, decoy != nil { pending = (.decoy, dk); return .needs2FA }
        registerFailure(.wrongPassword)
        if let until = lockedUntil { return .lockedOut(until) }
        return .wrong
    }

    func verify2FA(_ code: String) -> Bool {
        guard let p = pending,
              let prof = VaultStorage.load(Profile.self, "profile.enc", space: p.space, key: p.key) else { return false }
        if prof.totp.verify(code) {
            if p.space == .real { markFullLogin() }
            openVault(p.space, key: p.key, profile: prof)
            return true
        }
        registerFailure(.wrongCode)
        return false
    }

    func cancelPending() { pending = nil }

    func unlockWithBiometrics() async -> Bool {
        guard canUseBiometrics else { return false }
        guard let ctx = await Biometrics.authenticate(reason: tr("افتح خزنتك", "Unlock your vault")) else { return false }
        do {
            let key = try SecureEnclaveVault.unlock(space: .real, context: ctx)
            return openVault(.real, key: key)
        } catch {
            SecureEnclaveVault.remove(.real)
            defaults.set(false, forKey: "sec.biometric")
            show(tr("تغيّرت بيانات \(Biometrics.name). ادخل بكلمة السر وفعّلها من جديد.",
                    "\(Biometrics.name) changed. Sign in with your password and turn it on again."),
                 icon: "exclamationmark.triangle.fill", style: .warning)
            return false
        }
    }

    private func markFullLogin() {
        defaults.set(Date().timeIntervalSince1970, forKey: "sec.lastFullLogin")
    }

    private func registerFailure(_ reason: IntruderEvent.Reason) {
        let n = defaults.integer(forKey: "sec.failCount") + 1
        defaults.set(n, forKey: "sec.failCount")
        if n >= 5 {
            let delay = min(900, 30 * pow(2, Double(n - 5)))
            defaults.set(Date().timeIntervalSince1970 + delay, forKey: "sec.lockUntil")
        }
        if n >= 3 {
            IntruderCam.shared.capture { photo in
                VaultStorage.writeInbox(IntruderEvent(reason: reason, photo: photo))
            }
        } else {
            VaultStorage.writeInbox(IntruderEvent(reason: reason, photo: nil))
        }
    }

    @discardableResult
    private func openVault(_ s: VaultSpace, key: SymmetricKey, profile p: Profile? = nil) -> Bool {
        guard let prof = p ?? VaultStorage.load(Profile.self, "profile.enc", space: s, key: key) else { return false }
        masterKey = key
        space = s
        profile = prof
        if RemindersStore.key(s) == nil { RemindersStore.installKey(prof.remindersKey, space: s) }
        accounts = VaultStorage.load([AccountItem].self, "accounts.enc", space: s, key: key) ?? []
        notes = VaultStorage.load([SecureNote].self, "notes.enc", space: s, key: key) ?? []
        files = VaultStorage.load([VaultFile].self, "files.enc", space: s, key: key) ?? []
        reminders = RemindersStore.load(s)
        pending = nil
        sectionUnlocked = false
        defaults.set(0, forKey: "sec.failCount")
        defaults.set(0, forKey: "sec.lockUntil")
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .unlocked }
        SoundFX.shared.play(.unlock)
        Haptics.success()
        ReminderEngine.rescheduleAll()
        LiveActivityManager.sync()
        if s == .real {
            countNewIntrusions()
            Task { await autoBackupIfNeeded() }
        }
        return true
    }

    func lock(sound: Bool = true) {
        guard masterKey != nil || pending != nil else { return }
        masterKey = nil
        pending = nil
        profile = nil
        accounts = []
        notes = []
        files = []
        reminders = []
        sectionUnlocked = false
        space = .real
        VaultStorage.clearTemp()
        withAnimation(.easeInOut(duration: 0.35)) { phase = .locked }
        if sound { SoundFX.shared.play(.lock); Haptics.tap(.medium) }
    }

    func scenePhaseChanged(_ p: ScenePhase) {
        switch p {
        case .active:
            privacyCover = false
            if let t = backgroundedAt, isUnlocked, Date().timeIntervalSince(t) >= Double(autoLockSeconds) {
                lock(sound: false)
            }
            backgroundedAt = nil
            if isUnlocked { reminders = RemindersStore.load(space) }
            LiveActivityManager.sync()
        case .inactive:
            privacyCover = true
        case .background:
            privacyCover = true
            if backgroundedAt == nil { backgroundedAt = Date() }
            if autoLockSeconds == 0 { lock(sound: false) }
        @unknown default:
            break
        }
    }

    // MARK: - Biometrics setting

    func setBiometrics(_ on: Bool) async -> Bool {
        guard space == .real else { return false }
        if !on {
            SecureEnclaveVault.remove(.real)
            defaults.set(false, forKey: "sec.biometric")
            objectWillChange.send()
            return true
        }
        guard let mk = masterKey, SecureEnclaveVault.isAvailable,
              await Biometrics.authenticate(reason: tr("فعّل الدخول السريع", "Enable quick unlock")) != nil else { return false }
        do {
            try SecureEnclaveVault.enroll(masterKey: mk, space: .real)
            defaults.set(true, forKey: "sec.biometric")
            objectWillChange.send()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Passwords

    func verifyMainPassword(_ password: String) async -> Bool {
        guard let meta = VaultStorage.loadMeta(space) else { return false }
        return await Self.unwrap(password, salt: meta.salt, wrapped: meta.wrappedByPassword, tag: "pw") != nil
    }

    func changePassword(current: String, new: String) async throws {
        guard let mk = masterKey, var meta = VaultStorage.loadMeta(space) else { throw AppError.notUnlocked }
        guard await verifyMainPassword(current) else { throw AppError.wrongPassword }
        let w = try await Task.detached { try Self.wrap(mk, secret: new, tag: "pw") }.value
        meta.salt = w.salt
        meta.wrappedByPassword = w.wrapped
        try VaultStorage.saveMeta(meta, space)
    }

    /// Generates a new recovery key (old one stops working). Returns it for display.
    func regenerateRecoveryKey() async throws -> String {
        guard let mk = masterKey, var meta = VaultStorage.loadMeta(space) else { throw AppError.notUnlocked }
        let key = PasswordTools.recoveryKey()
        let norm = PasswordTools.normalizeRecovery(key)
        let w = try await Task.detached { try Self.wrap(mk, secret: norm, tag: "rk") }.value
        meta.recoverySalt = w.salt
        meta.wrappedByRecovery = w.wrapped
        try VaultStorage.saveMeta(meta, space)
        return key
    }

    // MARK: - Section password

    func setSectionPassword(_ p: String) async {
        guard var prof = profile else { return }
        let salt = AYNCrypto.randomBytes(16)
        let hash = await Task.detached { (try? AYNCrypto.pbkdf2(p, salt: salt, rounds: 200_000))?.rawData }.value
        prof.sectionSalt = salt
        prof.sectionHash = hash
        profile = prof
        saveProfile()
        sectionUnlocked = true
    }

    func checkSectionPassword(_ p: String) async -> Bool {
        guard let prof = profile, let salt = prof.sectionSalt, let hash = prof.sectionHash else { return false }
        let h = await Task.detached { (try? AYNCrypto.pbkdf2(p, salt: salt, rounds: 200_000))?.rawData }.value
        guard let h else { return false }
        let ok = AYNCrypto.constantTimeEqual(h, hash)
        if ok { sectionUnlocked = true }
        return ok
    }

    func saveProfile() {
        guard let mk = masterKey, let prof = profile else { return }
        try? VaultStorage.save(prof, "profile.enc", space: space, key: mk)
    }

    // MARK: - Duress (decoy vault)

    func setupDuress(password: String) async throws {
        guard space == .real, let prof = profile else { throw AppError.notUnlocked }
        if await verifyMainPassword(password) { throw AppError.samePassword }
        let dk = AYNCrypto.newMasterKey()
        let inbox = Curve25519.KeyAgreement.PrivateKey()
        let remKey = AYNCrypto.randomBytes(32)
        let w = try await Task.detached { try Self.wrap(dk, secret: password, tag: "pw") }.value
        let meta = VaultMeta(displayName: prof.username, salt: w.salt, wrappedByPassword: w.wrapped,
                             inboxPublicKey: inbox.publicKey.rawRepresentation)
        var decoyProfile = prof
        decoyProfile.inboxPrivateKey = inbox.rawRepresentation
        decoyProfile.remindersKey = remKey
        VaultStorage.wipe(.decoy)
        try VaultStorage.saveMeta(meta, .decoy)
        try VaultStorage.save(decoyProfile, "profile.enc", space: .decoy, key: dk)
        try VaultStorage.save([AccountItem](), "accounts.enc", space: .decoy, key: dk)
        try VaultStorage.save([SecureNote](), "notes.enc", space: .decoy, key: dk)
        try VaultStorage.save([VaultFile](), "files.enc", space: .decoy, key: dk)
        RemindersStore.installKey(remKey, space: .decoy)
        RemindersStore.save([], .decoy)
        objectWillChange.send()
    }

    func removeDuress() {
        VaultStorage.wipe(.decoy)
        objectWillChange.send()
    }

    // MARK: - Recovery

    func verifyRecovery(email: String, phone: String, birth: Date, recoveryKey: String) async throws -> SymmetricKey {
        guard let meta = VaultStorage.loadMeta(.real),
              let idSalt = meta.identitySalt, let idHash = meta.identityHash else { throw AppError.identityMismatch }
        let identity = Self.identityString(email: email, phone: phone, birth: birth)
        let h = await Task.detached { (try? AYNCrypto.pbkdf2(identity, salt: idSalt))?.rawData }.value
        guard let h, AYNCrypto.constantTimeEqual(h, idHash) else {
            registerFailure(.wrongPassword)
            throw AppError.identityMismatch
        }
        guard let key = await Self.unwrap(PasswordTools.normalizeRecovery(recoveryKey), salt: meta.recoverySalt,
                                          wrapped: meta.wrappedByRecovery, tag: "rk") else {
            registerFailure(.wrongPassword)
            throw AppError.wrongRecovery
        }
        return key
    }

    /// Sets a new password and a fresh recovery key (shown to the user beforehand), then opens the vault.
    func finishRecovery(key: SymmetricKey, newPassword: String, newRecovery: String) async throws {
        guard var meta = VaultStorage.loadMeta(.real) else { throw AppError.notUnlocked }
        let norm = PasswordTools.normalizeRecovery(newRecovery)
        let (pw, rk) = try await Task.detached { () -> ((salt: Data, wrapped: Data), (salt: Data, wrapped: Data)) in
            (try Self.wrap(key, secret: newPassword, tag: "pw"), try Self.wrap(key, secret: norm, tag: "rk"))
        }.value
        meta.salt = pw.salt
        meta.wrappedByPassword = pw.wrapped
        meta.recoverySalt = rk.salt
        meta.wrappedByRecovery = rk.wrapped
        try VaultStorage.saveMeta(meta, .real)
        SecureEnclaveVault.remove(.real)
        defaults.set(false, forKey: "sec.biometric")
        markFullLogin()
        openVault(.real, key: key)
    }

    // MARK: - Accounts

    func upsert(_ item: AccountItem) {
        var u = item
        u.updated = Date()
        if let i = accounts.firstIndex(where: { $0.id == item.id }) {
            if accounts[i].password != item.password { u.passwordChanged = Date() }
            accounts[i] = u
        } else {
            accounts.insert(u, at: 0)
        }
        persist(accounts, "accounts.enc")
    }

    func delete(_ item: AccountItem) {
        accounts.removeAll { $0.id == item.id }
        persist(accounts, "accounts.enc")
        SoundFX.shared.play(.delete)
    }

    var reusedPasswordIDs: Set<UUID> {
        var groups: [String: [UUID]] = [:]
        for a in accounts where !a.password.isEmpty { groups[a.password, default: []].append(a.id) }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    // MARK: - Notes

    func upsert(_ note: SecureNote) {
        var u = note
        u.updated = Date()
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = u } else { notes.insert(u, at: 0) }
        persist(notes, "notes.enc")
    }

    func delete(_ note: SecureNote) {
        notes.removeAll { $0.id == note.id }
        persist(notes, "notes.enc")
        SoundFX.shared.play(.delete)
    }

    // MARK: - Files

    func importFile(at url: URL, name: String, sensitivity: Sensitivity,
                    kind: VaultFileKind? = nil, ocrText: String? = nil) async throws {
        guard let mk = masterKey else { throw AppError.notUnlocked }
        let k = kind ?? MediaTools.kind(for: url)
        let id = UUID()
        let dst = VaultStorage.blobURL(id, space: space)
        try await Task.detached(priority: .userInitiated) { try AYNCrypto.encryptFile(from: url, to: dst, key: mk) }.value
        let thumb = await MediaTools.thumbnail(for: url, kind: k)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        files.insert(VaultFile(id: id, name: name, kind: k, size: size, sensitivity: sensitivity,
                               thumbnail: thumb, ocrText: ocrText), at: 0)
        persist(files, "files.enc")
    }

    func decryptedURL(for f: VaultFile) async throws -> URL {
        guard let mk = masterKey else { throw AppError.notUnlocked }
        let folder = VaultStorage.tempDir.appendingPathComponent(f.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = f.name.replacingOccurrences(of: "/", with: "-")
        let out = folder.appendingPathComponent(safeName.isEmpty ? "file" : safeName)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        let src = VaultStorage.blobURL(f.id, space: space)
        try await Task.detached(priority: .userInitiated) { try AYNCrypto.decryptFile(from: src, to: out, key: mk) }.value
        return out
    }

    func update(_ f: VaultFile) {
        if let i = files.firstIndex(where: { $0.id == f.id }) { files[i] = f }
        persist(files, "files.enc")
    }

    func delete(_ f: VaultFile) {
        try? FileManager.default.removeItem(at: VaultStorage.blobURL(f.id, space: space))
        files.removeAll { $0.id == f.id }
        persist(files, "files.enc")
        SoundFX.shared.play(.delete)
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        guard let mk = masterKey else { return }
        do { try VaultStorage.save(value, name, space: space, key: mk) }
        catch { show(tr("تعذّر الحفظ", "Couldn't save"), icon: "xmark.octagon.fill", style: .error) }
    }

    // MARK: - Reminders

    func upsert(_ r: Reminder) {
        if let i = reminders.firstIndex(where: { $0.id == r.id }) { reminders[i] = r } else { reminders.append(r) }
        saveReminders()
    }

    func delete(_ r: Reminder) {
        reminders.removeAll { $0.id == r.id }
        saveReminders()
        SoundFX.shared.play(.delete)
    }

    func setDone(_ r: Reminder, _ done: Bool) {
        var u = r
        u.done = done
        u.doneAt = done ? Date() : nil
        u.snoozedUntil = nil
        upsert(u)
    }

    private func saveReminders() {
        RemindersStore.save(reminders, space)
        ReminderEngine.rescheduleAll()
        LiveActivityManager.sync()
    }

    // MARK: - Intruder log

    private var inboxKey: Curve25519.KeyAgreement.PrivateKey? {
        guard let p = profile else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: p.inboxPrivateKey)
    }

    func intruderEvents() -> [IntruderEvent] {
        guard let k = inboxKey else { return [] }
        return VaultStorage.readInbox(space: space, privateKey: k)
    }

    func clearIntruderLog() {
        VaultStorage.deleteInbox(nil, space: space)
        newIntrusions = 0
    }

    private func countNewIntrusions() {
        let lastSeen = defaults.double(forKey: "sec.lastSeenIntrusion")
        let events = intruderEvents().filter { $0.date.timeIntervalSince1970 > lastSeen && $0.reason != .screenshot }
        newIntrusions = events.count
        if !events.isEmpty {
            show(tr("⚠️ في \(events.count) محاولة دخول فاشلة. شوف سجل المتطفلين.",
                    "⚠️ \(events.count) failed sign-in attempts. Check the intruder log."),
                 icon: "eye.trianglebadge.exclamationmark.fill", style: .warning)
        }
    }

    func markIntrusionsSeen() {
        defaults.set(Date().timeIntervalSince1970, forKey: "sec.lastSeenIntrusion")
        newIntrusions = 0
    }

    func logScreenEvent(_ reason: IntruderEvent.Reason) {
        VaultStorage.writeInbox(IntruderEvent(reason: reason, photo: nil), space: space)
    }

    // MARK: - Backup

    /// Encrypted backup bundle. `maxFileSize` skips large files (cloud free plan); nil = include everything.
    func makeBackup(maxFileSize: Int64?) async throws -> (data: Data, skipped: Int) {
        guard let mk = masterKey, let prof = profile, let meta = VaultStorage.loadMeta(space) else { throw AppError.notUnlocked }
        var blobs: [String: Data] = [:]
        var included: [VaultFile] = []
        var skipped = 0
        for f in files {
            if let max = maxFileSize, f.size > max { skipped += 1; continue }
            if let d = try? Data(contentsOf: VaultStorage.blobURL(f.id, space: space)) {
                blobs[f.id.uuidString] = d
                included.append(f)
            }
        }
        let payload = BackupPayload(profile: prof, accounts: accounts, notes: notes, files: included,
                                    blobs: blobs, reminders: reminders)
        let data = try await Task.detached(priority: .userInitiated) { () -> Data in
            let enc = PropertyListEncoder()
            enc.outputFormat = .binary
            let plain = try enc.encode(payload)
            let sealed = try AYNCrypto.seal(plain, key: mk, aad: Data("backup".utf8))
            return try enc.encode(BackupBundle(meta: meta, payload: sealed))
        }.value
        return (data, skipped)
    }

    /// Restores a bundle using its password (or recovery key). Replaces the real vault on this phone.
    func restore(_ data: Data, secret: String) async throws {
        guard let bundle = try? PropertyListDecoder().decode(BackupBundle.self, from: data) else { throw AppError.badBackup }
        var key = await Self.unwrap(secret, salt: bundle.meta.salt, wrapped: bundle.meta.wrappedByPassword, tag: "pw")
        if key == nil {
            key = await Self.unwrap(PasswordTools.normalizeRecovery(secret), salt: bundle.meta.recoverySalt,
                                    wrapped: bundle.meta.wrappedByRecovery, tag: "rk")
        }
        guard let mk = key,
              let plain = try? AYNCrypto.open(bundle.payload, key: mk, aad: Data("backup".utf8)),
              let payload = try? PropertyListDecoder().decode(BackupPayload.self, from: plain) else { throw AppError.badBackup }

        lock(sound: false)
        VaultStorage.wipe(.real)
        try VaultStorage.saveMeta(bundle.meta, .real)
        try VaultStorage.save(payload.profile, "profile.enc", space: .real, key: mk)
        try VaultStorage.save(payload.accounts, "accounts.enc", space: .real, key: mk)
        try VaultStorage.save(payload.notes, "notes.enc", space: .real, key: mk)
        try VaultStorage.save(payload.files, "files.enc", space: .real, key: mk)
        for (id, blob) in payload.blobs {
            guard let uuid = UUID(uuidString: id) else { continue }
            try blob.write(to: VaultStorage.blobURL(uuid, space: .real), options: [.atomic, .completeFileProtection])
        }
        RemindersStore.installKey(payload.profile.remindersKey, space: .real)
        RemindersStore.save(payload.reminders, .real)
        defaults.set(false, forKey: "sec.biometric")
        markFullLogin()
        openVault(.real, key: mk, profile: payload.profile)
    }

    var autoBackup: Bool {
        get { defaults.object(forKey: "backup.auto") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "backup.auto"); objectWillChange.send() }
    }
    var lastBackup: Date? {
        let t = defaults.double(forKey: "backup.last")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func backupToCloud() async throws -> Int {
        // In the decoy vault, pretend it worked so the real cloud backup is never overwritten.
        if space == .decoy { try? await Task.sleep(nanoseconds: 900_000_000); return 0 }
        let (data, skipped) = try await makeBackup(maxFileSize: 5 * 1024 * 1024)
        try await SupabaseClient.shared.uploadBackup(data)
        defaults.set(Date().timeIntervalSince1970, forKey: "backup.last")
        objectWillChange.send()
        return skipped
    }

    private func autoBackupIfNeeded() async {
        guard autoBackup, space == .real, SupabaseClient.shared.isConfigured, SupabaseClient.shared.session != nil else { return }
        if let last = lastBackup, Date().timeIntervalSince(last) < 7 * 86400 { return }
        _ = try? await backupToCloud()
    }

    // MARK: - Erase

    func eraseEverything() {
        lock(sound: false)
        VaultStorage.wipeAll()
        SupabaseClient.shared.signOut()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for k in ["sec.biometric", "sec.lastFullLogin", "sec.failCount", "sec.lockUntil", "backup.last", "sec.lastSeenIntrusion"] {
            defaults.removeObject(forKey: k)
        }
        WidgetBridge.update()
        LiveActivityManager.sync()
        withAnimation { phase = .welcome }
    }
}
