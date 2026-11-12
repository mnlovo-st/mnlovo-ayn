import SwiftUI
import CryptoKit
import LocalAuthentication
import UserNotifications

enum AppError: LocalizedError {
    case wrongPassword, samePassword, identityMismatch, wrongRecovery, locked, notUnlocked, badBackup
    case wrongCode, clockOff, noFaceID, faceFailed

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return tr("كلمة السر غلط.", "Wrong password.")
        case .samePassword: return tr("لازم تكون مختلفة عن كلمة السر الأساسية.", "It must differ from your main password.")
        case .identityMismatch: return tr("المعلومات ما تطابق صاحب الحساب.", "The details don't match the account owner.")
        case .wrongRecovery: return tr("مفتاح الاسترجاع غلط.", "Wrong recovery key.")
        case .locked: return tr("التطبيق مقفل مؤقتاً بسبب محاولات كثيرة.", "Temporarily locked after too many attempts.")
        case .notUnlocked: return tr("الخزنة مقفلة.", "The vault is locked.")
        case .badBackup: return tr("ملف النسخة الاحتياطية تالف أو كلمة السر غلط.", "Backup file is damaged or the password is wrong.")
        case .wrongCode: return tr("رمز التحقق غلط. استخدم الرمز اللي يطلع الحين في «كلمات السر» تحت اسم MNLOVO SAVER.",
                                   "Wrong code. Use the code currently shown in Passwords under MNLOVO SAVER.")
        case .clockOff: return tr("الرمز كان صحيح بس ساعة تلفونك مب مضبوطة. فعّل «ضبط تلقائي» للوقت من الإعدادات ← عام ← التاريخ والوقت.",
                                  "The code is right but your iPhone clock is off. Turn on Set Automatically in Settings → General → Date & Time.")
        case .noFaceID: return tr("هالطريقة تحتاج \(Biometrics.name) مفعّل على هالجوال. استخدم مفتاح الاسترجاع بدالها.",
                                  "This method needs \(Biometrics.name) set up on this iPhone. Use your recovery key instead.")
        case .faceFailed: return tr("فشل التحقق بالوجه.", "Face check failed.")
        }
    }
}

struct NewAccountInput {
    var username = ""
    var email = ""
    var phone = ""
    var birthDate = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    var password = ""
    /// Re-uses the 2FA secret from an earlier sign-up attempt (or install), so the code already
    /// saved in the iPhone Passwords app keeps working.
    var totp = TOTPCarry.loadOrCreate()
    var recoveryKey = PasswordTools.recoveryKey()
    var emailVerified = false
    var enableBiometrics = true
    var sectionCode = ""
    var sectionKind: PasscodeKind = .pin6
    var duressPassword = ""
}

/// Keeps the account's 2FA secret in the Keychain (this device only) across sign-up attempts and reinstalls.
enum TOTPCarry {
    static let account = "totp.carry"
    static func load() -> TOTP? {
        guard let d = Keychain.get(account), let t = try? JSONDecoder().decode(TOTP.self, from: d) else { return nil }
        return t
    }
    static func save(_ t: TOTP) {
        if let d = try? JSONEncoder().encode(t) { Keychain.set(d, account: account) }
    }
    /// Saved the moment it's created, so an abandoned sign-up never leaves a code in Passwords that no longer works.
    static func loadOrCreate() -> TOTP {
        if let t = load() { return t }
        let t = TOTP.generate(issuer: Brand.issuer, account: "")
        save(t)
        return t
    }
}

enum TOTPCheck: Equatable { case ok, adopted(TOTP), clockOff, wrong }

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
    /// The duress vault exactly as it sits on the phone (already encrypted with its own password),
    /// so signing out and back in doesn't lose it.
    var decoy: [String: Data]? = nil
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case intro, welcome, locked, unlocked }
    enum UnlockOutcome: Equatable { case unlocked, needs2FA, wrong, lockedOut(Date) }

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
    @Published var syncing = false
    @Published var celebration: Celebration?
    /// The goodbye animation playing over everything (sign out / account deleted).
    @Published var farewell: Farewell?
    enum Farewell: Equatable { case signOut(String), delete(String) }
    @Published var syncError: String?

    private var masterKey: SymmetricKey?
    private var pending: (space: VaultSpace, key: SymmetricKey)?
    private var bioKey: SymmetricKey?
    private var backgroundedAt: Date?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backupTask: Task<Void, Never>?
    private var sectionFails = 0
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

    /// Seconds the app may stay in the background before it locks again (default 5).
    var autoLockSeconds: Int {
        get { defaults.object(forKey: "sec.autolock") as? Int ?? 5 }
        set { defaults.set(newValue, forKey: "sec.autolock"); objectWillChange.send() }
    }
    var biometricsWanted: Bool { defaults.object(forKey: "sec.biometric") as? Bool ?? true }
    var biometricsOn: Bool { biometricsWanted && SecureEnclaveVault.isEnrolled(.real) }
    /// Entry = Face ID + password. Without Face ID: password + 2FA code.
    var canUseBiometrics: Bool { biometricsOn && Biometrics.isAvailable }
    var bioPassed: Bool { bioKey != nil }
    var sectionKind: PasscodeKind {
        PasscodeKind(rawValue: profile?.sectionKind ?? "") ?? (hasSectionPassword ? .text : .pin6)
    }

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

    /// Builds the plain-text parcel handed over by the heartbeat feature. Only what the user ticked.
    func legacyBundle(_ sel: LegacyService.Selection) -> String {
        var out = ["MNLOVO SAVER — \(tr("وصية وأمانة", "Will and legacy"))",
                   "\(tr("أُعدّت في", "Prepared")): \(Fmt.date(Date()))", ""]
        if !sel.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(contentsOf: ["══ \(tr("الوصية", "The will")) ══", sel.message, ""])
        }
        if sel.accounts && !accounts.isEmpty {
            out.append("══ \(tr("الحسابات", "Accounts")) (\(accounts.count)) ══")
            for a in accounts.sorted(by: { $0.service < $1.service }) {
                out.append("• \(a.service)")
                if !a.login.isEmpty { out.append("  \(tr("المستخدم", "Login")): \(a.login)") }
                if sel.passwords && !a.password.isEmpty { out.append("  \(tr("كلمة السر", "Password")): \(a.password)") }
                if !a.url.isEmpty { out.append("  \(tr("الرابط", "Link")): \(a.url)") }
                if let t = a.totp { out.append("  2FA: \(t.secretBase32)") }
                if !a.notes.isEmpty { out.append("  \(a.notes)") }
            }
            out.append("")
        }
        if sel.notes && !notes.isEmpty {
            out.append("══ \(tr("الملاحظات", "Notes")) (\(notes.count)) ══")
            for n in notes { out.append("• \(n.title)\n  \(n.body)") }
            out.append("")
        }
        if sel.reminders && !reminders.isEmpty {
            out.append("══ \(tr("التذكيرات", "Reminders")) ══")
            for r in reminders where !r.done { out.append("• \(r.title) — \(Fmt.date(r.due))") }
            out.append("")
        }
        if sel.fileList && !files.isEmpty {
            out.append("══ \(tr("ملفات في الخزنة (أسماء فقط)", "Vault files (names only)")) ══")
            for f in files { out.append("• \(f.name) — \(Fmt.bytes(f.size))") }
            out.append("")
        }
        out.append(tr("الملفات والصور نفسها تبقى مشفّرة في الجهاز وما تنطرش.",
                      "The files and photos themselves stay encrypted on the device and are not sent."))
        return out.joined(separator: "\n")
    }

    nonisolated static func identity2String(phone: String, birth: Date) -> String {
        let digits = TOTP.westernDigits(phone).filter { $0.isASCII && $0.isNumber }
        return "v2|\(digits.suffix(9))|\(SupabaseClient.day(birth))"
    }

    /// Adds the phone+birth-date check to older vaults the first time they open.
    private func ensureIdentity2(_ prof: Profile) {
        guard var meta = VaultStorage.loadMeta(.real), meta.identity2Hash == nil else { return }
        let id2 = Self.identity2String(phone: prof.phone, birth: prof.birthDate)
        Task.detached(priority: .utility) {
            let salt = AYNCrypto.randomBytes(16)
            guard let h = try? AYNCrypto.pbkdf2(id2, salt: salt).rawData else { return }
            await MainActor.run {
                meta.identity2Salt = salt
                meta.identity2Hash = h
                try? VaultStorage.saveMeta(meta, .real)
            }
        }
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
        if totp.account.isEmpty { totp.account = "\(n.username) · \(totp.fingerprint)" }
        TOTPCarry.save(totp)
        var prof = Profile(username: n.username, email: n.email.lowercased(), phone: n.phone, birthDate: n.birthDate,
                           emailVerified: n.emailVerified, totp: totp,
                           inboxPrivateKey: inbox.rawRepresentation, remindersKey: remKey)
        if !n.sectionCode.isEmpty {
            let code = n.sectionCode
            let sSalt = AYNCrypto.randomBytes(16)
            prof.sectionSalt = sSalt
            prof.sectionHash = await Task.detached { (try? AYNCrypto.pbkdf2(code, salt: sSalt, rounds: 200_000))?.rawData }.value
            prof.sectionKind = n.sectionKind.rawValue
        }

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
        } else {
            defaults.set(false, forKey: "sec.biometric")
        }
        defaults.set(true, forKey: "backup.dirty")
        markPassword()
        openVault(.real, key: mk, profile: prof)
        if !n.duressPassword.isEmpty { try? await setupDuress(password: n.duressPassword) }
        Task { await SupabaseClient.shared.registerAccount(email: n.email, phone: n.phone, username: n.username, birth: n.birthDate) }
        celebration = Celebration(title: tr("أهلاً \(n.username)! 🎉", "Welcome, \(n.username)! 🎉"),
                                  subtitle: tr("حسابك جاهز ومحمي بالكامل", "Your account is ready and fully protected"))
    }

    // MARK: - Unlock

    /// Step 1 of entry: Face ID. Uses the Secure Enclave key, so a matching face is proven by hardware.
    func biometricStep() async -> Bool {
        guard canUseBiometrics else { return false }
        guard let ctx = await Biometrics.authenticate(reason: tr("افتح خزنتك", "Unlock your vault")) else { return false }
        do {
            bioKey = try SecureEnclaveVault.unlock(space: .real, context: ctx)
            return true
        } catch {
            SecureEnclaveVault.remove(.real)
            show(tr("تغيّرت بيانات \(Biometrics.name). ادخل بكلمة السر ورمز التحقق، وبنفعّلها لك من جديد.",
                    "\(Biometrics.name) changed. Sign in with your password and 2FA code — we'll set it up again."),
                 icon: "exclamationmark.triangle.fill", style: .warning)
            return false
        }
    }

    func resetBiometricStep() { bioKey = nil }

    /// Step 2 of entry: the password. After Face ID it opens straight away;
    /// without Face ID it asks for the 2FA code as the second factor.
    func unlock(password: String) async -> UnlockOutcome {
        if let until = lockedUntil { return .lockedOut(until) }
        let real = VaultStorage.loadMeta(.real)
        let decoy = VaultStorage.loadMeta(.decoy)
        // Both are always computed so the timing never reveals whether a decoy vault exists.
        async let r = Self.unwrap(password, salt: real?.salt, wrapped: real?.wrappedByPassword, tag: "pw")
        async let d = Self.unwrap(password, salt: decoy?.salt, wrapped: decoy?.wrappedByPassword, tag: "pw")
        let (rk, dk) = await (r, d)
        let strong = needsStrongCheck
        if rk != nil || (dk != nil && decoy != nil) { markPassword() }
        if let rk {
            if !strong { openVault(.real, key: rk); return .unlocked }
            pending = (.real, rk)
            return .needs2FA
        }
        if let dk, decoy != nil {
            if !strong { openVault(.decoy, key: dk); return .unlocked }
            pending = (.decoy, dk)
            return .needs2FA
        }
        registerFailure(.wrongPassword)
        if let until = lockedUntil { return .lockedOut(until) }
        return .wrong
    }

    /// After 3 wrong attempts the 2FA code is required as an extra check.
    var needsStrongCheck: Bool { defaults.integer(forKey: "sec.failCount") >= 3 }
    var failCount: Int { defaults.integer(forKey: "sec.failCount") }
    @Published var lastCodeProblem: AppError?

    /// Checks a 2FA code against the account (and the secret kept on this device, in case the
    /// Passwords app holds that one). Never weaker: both secrets live only on this iPhone.
    nonisolated static func checkTOTP(_ code: String, _ totp: TOTP) -> TOTPCheck {
        if totp.verify(code) { return .ok }
        if let c = TOTPCarry.load(), c.secret != totp.secret, c.verify(code) { return .adopted(c) }
        if totp.verify(code, window: 30) { return .clockOff }
        return .wrong
    }

    /// Applies a check to a profile; saves the adopted secret so future codes keep matching.
    private func applyTOTP(_ code: String, profile prof: inout Profile, space s: VaultSpace, key: SymmetricKey) -> Bool {
        switch Self.checkTOTP(code, prof.totp) {
        case .ok:
            lastCodeProblem = nil
            return true
        case .adopted(let c):
            var t = c
            t.account = prof.totp.account
            prof.totp = t
            try? VaultStorage.save(prof, "profile.enc", space: s, key: key)
            defaults.set(true, forKey: "backup.dirty")
            lastCodeProblem = nil
            return true
        case .clockOff:
            lastCodeProblem = .clockOff
            return false
        case .wrong:
            lastCodeProblem = .wrongCode
            return false
        }
    }

    /// Checks a code against the open vault's profile (section reset, delete account…).
    func checkCodeNow(_ code: String) -> Bool {
        guard var prof = profile, let mk = masterKey else { return false }
        let ok = applyTOTP(code, profile: &prof, space: space, key: mk)
        if ok { profile = prof }
        return ok
    }

    /// Alternative to the 2FA code at the strong check: the recovery key.
    func verifyPendingRecovery(_ key: String) async -> Bool {
        guard let p = pending, let meta = VaultStorage.loadMeta(p.space), meta.wrappedByRecovery != nil,
              let k = await Self.unwrap(PasswordTools.normalizeRecovery(key), salt: meta.recoverySalt,
                                        wrapped: meta.wrappedByRecovery, tag: "rk") else {
            registerFailure(.wrongCode)
            return false
        }
        openVault(p.space, key: k)
        return true
    }

    func verify2FA(_ code: String) -> Bool {
        guard let p = pending,
              var prof = VaultStorage.load(Profile.self, "profile.enc", space: p.space, key: p.key) else { return false }
        if applyTOTP(code, profile: &prof, space: p.space, key: p.key) {
            // Face ID was invalidated (e.g. a new face added) → quietly set it up again.
            if p.space == .real && biometricsWanted && !SecureEnclaveVault.isEnrolled(.real)
                && Biometrics.isAvailable && SecureEnclaveVault.isAvailable {
                try? SecureEnclaveVault.enroll(masterKey: p.key, space: .real)
            }
            openVault(p.space, key: p.key, profile: prof)
            return true
        }
        registerFailure(.wrongCode)
        return false
    }

    func cancelPending() { pending = nil }

    private func registerFailure(_ reason: IntruderEvent.Reason) {
        let n = defaults.integer(forKey: "sec.failCount") + 1
        defaults.set(n, forKey: "sec.failCount")
        if n >= 5 {
            let delay = min(900, 30 * pow(2, Double(n - 5)))
            defaults.set(Date().timeIntervalSince1970 + delay, forKey: "sec.lockUntil")
        }
        let title = IntruderEvent(reason: reason, photo: nil).title
        if n >= 2 {
            IntruderCam.shared.capture { photo in
                let event = IntruderEvent(reason: reason, photo: photo, attempt: n)
                VaultStorage.writeInbox(event)
                // Telegram gets the finished card (photo + name, date, time, attempt), not the bare frame.
                let card = photo.flatMap { UIImage(data: $0) }
                    .flatMap { IntruderStamp.stamped($0, event: event).jpegData(compressionQuality: 0.85) }
                if let shot = card ?? photo {
                    TelegramService.shared.sendIntruderAlert(photo: shot, reason: title, attempt: n)
                }
            }
        } else {
            VaultStorage.writeInbox(IntruderEvent(reason: reason, photo: nil, attempt: n))
        }
        TelegramService.shared.sendAttemptAlert(reason: title, attempt: n)
    }

    @discardableResult
    private func openVault(_ s: VaultSpace, key: SymmetricKey, profile p: Profile? = nil) -> Bool {
        guard var prof = p ?? VaultStorage.load(Profile.self, "profile.enc", space: s, key: key) else { return false }
        // The duress vault has to wear the same name as the real one, or it gives itself away.
        if s == .decoy, let realName = VaultStorage.loadMeta(.real)?.displayName, prof.username != realName {
            prof.username = realName
            try? VaultStorage.save(prof, "profile.enc", space: .decoy, key: key)
            if var m = VaultStorage.loadMeta(.decoy) { m.displayName = realName; try? VaultStorage.saveMeta(m, .decoy) }
        }
        masterKey = key
        space = s
        profile = prof
        if s == .real && TOTPCarry.load() == nil { TOTPCarry.save(prof.totp) }
        if s == .real {
            ensureIdentity2(prof)
            LegacyService.shared.checkIn()   // proof of life for the heartbeat feature
        }
        if RemindersStore.key(s) == nil { RemindersStore.installKey(prof.remindersKey, space: s) }
        accounts = VaultStorage.load([AccountItem].self, "accounts.enc", space: s, key: key) ?? []
        notes = VaultStorage.load([SecureNote].self, "notes.enc", space: s, key: key) ?? []
        files = VaultStorage.load([VaultFile].self, "files.enc", space: s, key: key) ?? []
        reminders = RemindersStore.load(s)
        pending = nil
        bioKey = nil
        sectionUnlocked = false
        sectionFails = 0
        defaults.set(0, forKey: "sec.failCount")
        defaults.set(0, forKey: "sec.lockUntil")
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .unlocked }
        SoundFX.shared.play(.unlock)
        Haptics.success()
        ReminderEngine.rescheduleAll()
        LiveActivityManager.sync()
        LiveActivityManager.startWatching()
        if s == .real { refreshWidgetSnapshot() }
        if s == .real {
            if cloudReady && !defaults.bool(forKey: "registry.v2") {
                let p = prof
                Task {
                    await SupabaseClient.shared.registerAccount(email: p.email, phone: p.phone, username: p.username, birth: p.birthDate)
                    UserDefaults.standard.set(true, forKey: "registry.v2")
                }
            }
            countNewIntrusions()
            if defaults.bool(forKey: "backup.dirty") || (lastBackup.map { Date().timeIntervalSince($0) > 86400 } ?? true) {
                scheduleBackup(delay: 1.5)
            }
        }
        return true
    }

    func lock(sound: Bool = true) {
        guard masterKey != nil || pending != nil else { return }
        masterKey = nil
        pending = nil
        bioKey = nil
        backupTask?.cancel()
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

    // A short, user-started trip to another app (e.g. linking Telegram) shouldn't lock the vault.
    private var tripUntil: Date?
    private var currentGrace: Double = 5
    func allowShortTrip(_ seconds: Double = 120) { tripUntil = Date().addingTimeInterval(seconds) }
    private var onTrip: Bool { (tripUntil ?? .distantPast) > Date() }

    func scenePhaseChanged(_ p: ScenePhase) {
        switch p {
        case .active:
            privacyCover = false
            endBackgroundTask()
            if let t = backgroundedAt, isUnlocked, Date().timeIntervalSince(t) >= currentGrace {
                lock(sound: false)
            }
            backgroundedAt = nil
            tripUntil = nil
            if isUnlocked { reminders = RemindersStore.load(space) }
            LiveActivityManager.sync()
        case .inactive:
            privacyCover = true
        case .background:
            privacyCover = true
            if backgroundedAt == nil { backgroundedAt = Date() }
            if !isUnlocked { bioKey = nil }
            let trip = onTrip
            currentGrace = trip ? max(Double(autoLockSeconds), tripUntil!.timeIntervalSinceNow) : Double(autoLockSeconds)
            if currentGrace <= 0 { lock(sound: false); return }
            // Stay alive just long enough to lock and wipe keys from memory after the grace period.
            if backgroundTask == .invalid {
                backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "saver.autolock") { [weak self] in
                    Task { @MainActor in
                        if !trip { self?.lock(sound: false) }
                        self?.endBackgroundTask()
                    }
                }
            }
            let grace = currentGrace
            DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in
                guard let self, let t = self.backgroundedAt, Date().timeIntervalSince(t) >= grace - 0.05 else { return }
                self.lock(sound: false)
                self.endBackgroundTask()
            }
        @unknown default:
            break
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
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

    func setSectionPassword(_ p: String, kind: PasscodeKind) async {
        guard var prof = profile else { return }
        let salt = AYNCrypto.randomBytes(16)
        let hash = await Task.detached { (try? AYNCrypto.pbkdf2(p, salt: salt, rounds: 200_000))?.rawData }.value
        prof.sectionSalt = salt
        prof.sectionHash = hash
        prof.sectionKind = kind.rawValue
        profile = prof
        saveProfile()
        sectionUnlocked = true
    }

    /// Five wrong section passcodes in a row lock the whole app.
    func checkSectionPassword(_ p: String) async -> Bool {
        guard let prof = profile, let salt = prof.sectionSalt, let hash = prof.sectionHash else { return false }
        let h = await Task.detached { (try? AYNCrypto.pbkdf2(p, salt: salt, rounds: 200_000))?.rawData }.value
        guard let h else { return false }
        let ok = AYNCrypto.constantTimeEqual(h, hash)
        if ok {
            sectionUnlocked = true
            sectionFails = 0
        } else {
            sectionFails += 1
            logScreenEvent(.wrongPassword)
            if sectionFails >= 5 {
                show(tr("محاولات كثيرة — قفلنا التطبيق للأمان.", "Too many attempts — the app locked for safety."),
                     icon: "lock.fill", style: .warning)
                lock()
            }
        }
        return ok
    }

    /// Forgot section passcode: account password + (2FA code or recovery key).
    func verifyForSectionReset(password: String, code: String?, recoveryKey: String?) async throws {
        guard await verifyMainPassword(password) else {
            logScreenEvent(.wrongPassword)
            throw AppError.wrongPassword
        }
        if let code {
            guard checkCodeNow(code) else { throw lastCodeProblem ?? AppError.wrongCode }
        } else if let recoveryKey {
            guard let meta = VaultStorage.loadMeta(space),
                  await Self.unwrap(PasswordTools.normalizeRecovery(recoveryKey), salt: meta.recoverySalt,
                                    wrapped: meta.wrappedByRecovery, tag: "rk") != nil else { throw AppError.wrongRecovery }
        }
        sectionFails = 0
    }

    func saveProfile() {
        guard let mk = masterKey, let prof = profile else { return }
        try? VaultStorage.save(prof, "profile.enc", space: space, key: mk)
        scheduleBackup()
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
        scheduleBackup(delay: 1)   // the backup carries it, so it survives signing out and back in
    }

    func removeDuress() {
        VaultStorage.wipe(.decoy)
        objectWillChange.send()
        scheduleBackup(delay: 1)
    }

    // MARK: - Username

    /// After the server accepted the new name (email code + 90-day rule).
    func applyNewUsername(_ name: String) {
        guard space == .real, var prof = profile else { return }
        prof.username = name
        prof.usernameChangedAt = Date()
        profile = prof
        saveProfile()
        if var meta = VaultStorage.loadMeta(.real) {
            meta.displayName = name
            try? VaultStorage.saveMeta(meta, .real)
        }
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

    /// Forgot password, step 1: email + phone + birth date must match the account.
    /// If only phone + birth date match (e.g. support changed the email), returns true: the new email
    /// must then be proven with its code and belong to this account in the cloud.
    @discardableResult
    func verifyIdentity(email: String, phone: String, birth: Date) async throws -> Bool {
        guard let meta = VaultStorage.loadMeta(.real),
              let idSalt = meta.identitySalt, let idHash = meta.identityHash else { throw AppError.identityMismatch }
        let identity = Self.identityString(email: email, phone: phone, birth: birth)
        let h = await Task.detached { (try? AYNCrypto.pbkdf2(identity, salt: idSalt))?.rawData }.value
        if let h, AYNCrypto.constantTimeEqual(h, idHash) { return false }
        if let s2 = meta.identity2Salt, let h2 = meta.identity2Hash, UserDefaults.standard.string(forKey: "cloud.userID") != nil {
            let id2 = Self.identity2String(phone: phone, birth: birth)
            let c = await Task.detached { (try? AYNCrypto.pbkdf2(id2, salt: s2))?.rawData }.value
            if let c, AYNCrypto.constantTimeEqual(c, h2) { return true }
        }
        registerFailure(.wrongPassword)
        throw AppError.identityMismatch
    }

    // MARK: - Entry policy: Face ID, with the password every few minutes

    /// Seconds between password prompts when Face ID is on (0 = every time).
    var passwordEvery: Int {
        get { defaults.object(forKey: "sec.pwEvery") as? Int ?? 300 }
        set { defaults.set(newValue, forKey: "sec.pwEvery"); objectWillChange.send() }
    }
    private var lastPasswordAt: Date? {
        let t = defaults.double(forKey: "sec.lastPassword")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    private func markPassword() { defaults.set(Date().timeIntervalSince1970, forKey: "sec.lastPassword") }

    /// Is the password needed on this entry?
    var passwordDue: Bool {
        guard canUseBiometrics, passwordEvery > 0, !needsStrongCheck, let last = lastPasswordAt else { return true }
        return Date().timeIntervalSince(last) >= Double(passwordEvery)
    }

    /// After Face ID: opens straight away when the password isn't due.
    func unlockWithFace() -> Bool {
        guard let k = bioKey, !passwordDue else { return false }
        openVault(.real, key: k)
        return true
    }

    /// Forgot password, last step (option A): Face ID opens the vault key, the 2FA code proves the second factor.
    func recoverWithFaceAndCode(_ code: String) async throws -> SymmetricKey {
        guard SecureEnclaveVault.isEnrolled(.real), Biometrics.isAvailable else { throw AppError.noFaceID }
        guard let ctx = await Biometrics.authenticate(reason: tr("استرجاع الحساب", "Account recovery")) else { throw AppError.faceFailed }
        guard let key = try? SecureEnclaveVault.unlock(space: .real, context: ctx),
              var prof = VaultStorage.load(Profile.self, "profile.enc", space: .real, key: key) else { throw AppError.noFaceID }
        guard applyTOTP(code, profile: &prof, space: .real, key: key) else {
            registerFailure(.wrongCode)
            throw lastCodeProblem ?? AppError.wrongCode
        }
        return key
    }

    /// Forgot password, last step (option B): the 24-character recovery key.
    func recoverWithKey(_ recoveryKey: String) async throws -> SymmetricKey {
        guard let meta = VaultStorage.loadMeta(.real),
              let key = await Self.unwrap(PasswordTools.normalizeRecovery(recoveryKey), salt: meta.recoverySalt,
                                          wrapped: meta.wrappedByRecovery, tag: "rk") else {
            registerFailure(.wrongPassword)
            throw AppError.wrongRecovery
        }
        return key
    }

    /// Sets a new password (and, if given, a fresh recovery key shown to the user beforehand), then opens the vault.
    func finishRecovery(key: SymmetricKey, newPassword: String, newRecovery: String?) async throws {
        guard var meta = VaultStorage.loadMeta(.real) else { throw AppError.notUnlocked }
        let pw = try await Task.detached { try Self.wrap(key, secret: newPassword, tag: "pw") }.value
        meta.salt = pw.salt
        meta.wrappedByPassword = pw.wrapped
        if let newRecovery {
            let norm = PasswordTools.normalizeRecovery(newRecovery)
            let rk = try await Task.detached { try Self.wrap(key, secret: norm, tag: "rk") }.value
            meta.recoverySalt = rk.salt
            meta.wrappedByRecovery = rk.wrapped
        }
        try VaultStorage.saveMeta(meta, .real)
        SecureEnclaveVault.remove(.real)
        if biometricsWanted && Biometrics.isAvailable && SecureEnclaveVault.isAvailable {
            try? SecureEnclaveVault.enroll(masterKey: key, space: .real)
        }
        defaults.set(true, forKey: "backup.dirty")
        markPassword()
        openVault(.real, key: key)
    }

    // MARK: - Accounts

    func upsert(_ item: AccountItem) {
        var u = item
        u.updated = Date()
        if let i = accounts.firstIndex(where: { $0.id == item.id }) {
            if accounts[i].password != item.password { u.passwordChanged = Date() }
            accounts[i] = u
            TelegramService.shared.post(.accountUpdated(u), space: space)
        } else {
            accounts.insert(u, at: 0)
            TelegramService.shared.post(.accountAdded(u), space: space)
        }
        persist(accounts, "accounts.enc")
        refreshWidgetSnapshot()
    }

    /// The numbers the safety widget shows. Only counts and dates leave the vault, never names.
    func refreshWidgetSnapshot() {
        guard space == .real, isUnlocked else { return }
        let weak = accounts.filter { !$0.password.isEmpty && PasswordTools.strength($0.password).score <= 1 }.count
        WidgetBridge.vault = .init(accounts: accounts.count, weak: weak + reusedPasswordIDs.count,
                                   intruders: newIntrusions, lastBackup: lastBackup)
        WidgetBridge.update()
    }

    func delete(_ item: AccountItem) {
        accounts.removeAll { $0.id == item.id }
        persist(accounts, "accounts.enc")
        refreshWidgetSnapshot()
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
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = u
            TelegramService.shared.post(.noteUpdated(u), space: space)
        } else {
            notes.insert(u, at: 0)
            TelegramService.shared.post(.noteAdded(u), space: space)
        }
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
        let vf = VaultFile(id: id, name: name, kind: k, size: size, sensitivity: sensitivity,
                           thumbnail: thumb, ocrText: ocrText)
        files.insert(vf, at: 0)
        TelegramService.shared.post(.fileAdded(vf), space: space)
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
        do {
            try VaultStorage.save(value, name, space: space, key: mk)
            if name != "files.enc" { scheduleBackup() }
        } catch { show(tr("تعذّر الحفظ", "Couldn't save"), icon: "xmark.octagon.fill", style: .error) }
    }

    // MARK: - Reminders

    func upsert(_ r: Reminder) {
        if let i = reminders.firstIndex(where: { $0.id == r.id }) {
            let wasDone = reminders[i].done
            reminders[i] = r
            if r.done && !wasDone { TelegramService.shared.post(.reminderDone(r), space: space) }
            else if !r.done { TelegramService.shared.post(.reminderUpdated(r), space: space) }
        } else {
            reminders.append(r)
            TelegramService.shared.post(.reminderAdded(r), space: space)
        }
        saveReminders()
    }

    func delete(_ r: Reminder) {
        reminders.removeAll { $0.id == r.id }
        saveReminders()
        SoundFX.shared.play(.delete)
    }

    /// Ticks (or unticks) today's routine.
    func markRoutine(_ r: Reminder, done: Bool, skip: Bool = false) {
        guard var ro = r.routine else { return }
        let k = Routine.dayKey(Date())
        ro.doneDays.removeAll { $0 == k }
        ro.skipDays.removeAll { $0 == k }
        if done { ro.doneDays.append(k) }
        if skip { ro.skipDays.append(k) }
        ro.doneDays = Array(ro.doneDays.suffix(400))
        var u = r
        u.routine = ro
        u.snoozedUntil = nil
        u.due = ro.next(after: Date()) ?? r.due
        if let i = reminders.firstIndex(where: { $0.id == r.id }) { reminders[i] = u }
        saveReminders()
        if done { TelegramService.shared.post(.reminderDone(u), space: space) }
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
        scheduleBackup()
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
        refreshWidgetSnapshot()
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
    // Automatic cloud backup: accounts, notes, reminders and settings (not photos/videos/files),
    // encrypted on the phone and uploaded a few seconds after every change.

    /// Encrypted backup bundle. `includeFiles` adds photos/videos/files (manual full export only).
    func makeBackup(includeFiles: Bool) async throws -> Data {
        guard let mk = masterKey, let prof = profile, let meta = VaultStorage.loadMeta(space) else { throw AppError.notUnlocked }
        var blobs: [String: Data] = [:]
        var included: [VaultFile] = []
        if includeFiles {
            for f in files {
                if let d = try? Data(contentsOf: VaultStorage.blobURL(f.id, space: space)) {
                    blobs[f.id.uuidString] = d
                    included.append(f)
                }
            }
        }
        var payload = BackupPayload(profile: prof, accounts: accounts, notes: notes, files: included,
                                    blobs: blobs, reminders: reminders)
        if space == .real && VaultStorage.exists(.decoy) {
            var d: [String: Data] = [:]
            for name in ["meta.json", "profile.enc", "accounts.enc", "notes.enc", "files.enc", "reminders.enc"] {
                if let raw = try? Data(contentsOf: VaultStorage.dir(.decoy).appendingPathComponent(name)) { d[name] = raw }
            }
            if d["meta.json"] != nil && d["profile.enc"] != nil { payload.decoy = d }
        }
        return try await Task.detached(priority: .utility) { () -> Data in
            let enc = PropertyListEncoder()
            enc.outputFormat = .binary
            let plain = try enc.encode(payload)
            let sealed = try AYNCrypto.seal(plain, key: mk, aad: Data("backup".utf8))
            return try enc.encode(BackupBundle(meta: meta, payload: sealed))
        }.value
    }

    /// Restores a bundle using its password (or recovery key). Keeps photos/files already on this phone.
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
        // Photos/files on this phone encrypted with the same vault key are kept.
        let sameVault = VaultStorage.loadMeta(.real).map { $0.inboxPublicKey == bundle.meta.inboxPublicKey } ?? false
        let keptFiles: [VaultFile] = sameVault ? (VaultStorage.load([VaultFile].self, "files.enc", space: .real, key: mk) ?? []) : []
        if !sameVault {
            VaultStorage.wipe(.real)
            VaultStorage.wipe(.decoy)   // another account's duress vault must not stay behind
        }
        if let decoy = payload.decoy, decoy["meta.json"] != nil {
            VaultStorage.wipe(.decoy)
            let dir = VaultStorage.dir(.decoy)
            for (name, raw) in decoy where !name.contains("/") {
                try? raw.write(to: dir.appendingPathComponent(name),
                               options: [.atomic, name == "meta.json" || name == "reminders.enc"
                                         ? .completeFileProtectionUntilFirstUserAuthentication : .completeFileProtection])
            }
        }
        try VaultStorage.saveMeta(bundle.meta, .real)
        try VaultStorage.save(payload.profile, "profile.enc", space: .real, key: mk)
        try VaultStorage.save(payload.accounts, "accounts.enc", space: .real, key: mk)
        try VaultStorage.save(payload.notes, "notes.enc", space: .real, key: mk)
        var allFiles = keptFiles
        for f in payload.files where !allFiles.contains(where: { $0.id == f.id }) { allFiles.append(f) }
        try VaultStorage.save(allFiles, "files.enc", space: .real, key: mk)
        for (id, blob) in payload.blobs {
            guard let uuid = UUID(uuidString: id) else { continue }
            try blob.write(to: VaultStorage.blobURL(uuid, space: .real), options: [.atomic, .completeFileProtection])
        }
        RemindersStore.installKey(payload.profile.remindersKey, space: .real)
        RemindersStore.save(payload.reminders, .real)
        SecureEnclaveVault.remove(.real)
        if biometricsWanted && Biometrics.isAvailable && SecureEnclaveVault.isAvailable {
            try? SecureEnclaveVault.enroll(masterKey: mk, space: .real)
        }
        markPassword()
        openVault(.real, key: mk, profile: payload.profile)
        let p = payload.profile
        Task { await SupabaseClient.shared.registerAccount(email: p.email, phone: p.phone, username: p.username, birth: p.birthDate) }
        celebration = Celebration(title: tr("أهلاً من جديد \(payload.profile.username)! 🎉", "Welcome back, \(payload.profile.username)! 🎉"),
                                  subtitle: tr("رجعت بياناتك كلها", "All your data is back"))
    }

    var lastBackup: Date? {
        let t = defaults.double(forKey: "backup.last")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    var cloudReady: Bool { SupabaseClient.shared.isConfigured && SupabaseClient.shared.session != nil }

    /// Debounced automatic backup (a few seconds after the last change).
    func scheduleBackup(delay: Double = 4) {
        defaults.set(true, forKey: "backup.dirty")
        guard space == .real, cloudReady else { return }
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.backupNow(silent: true)
        }
    }

    @discardableResult
    func backupNow(silent: Bool = false) async -> Bool {
        // In the decoy vault, pretend it worked so the real cloud backup is never overwritten.
        if space == .decoy { return true }
        guard cloudReady, isUnlocked else { return false }
        syncing = true
        defer { syncing = false }
        do {
            let data = try await makeBackup(includeFiles: false)
            try await SupabaseClient.shared.uploadBackup(data)
            defaults.set(Date().timeIntervalSince1970, forKey: "backup.last")
            defaults.set(false, forKey: "backup.dirty")
            refreshWidgetSnapshot()
            syncError = nil
            objectWillChange.send()
            return true
        } catch {
            syncError = error.localizedDescription
            if !silent { show(error.localizedDescription, icon: "icloud.slash", style: .error) }
            return false
        }
    }

    // MARK: - Sign out

    enum SignOutResult: Equatable { case done, wrongPassword, noBackup }

    /// Step one of signing out: the password, then a fresh cloud backup. No backup, no sign-out —
    /// nothing may be lost.
    func prepareSignOut(password: String) async -> SignOutResult {
        guard space == .real else { return .wrongPassword }
        guard await verifyMainPassword(password) else { return .wrongPassword }
        guard cloudReady, await backupNow(silent: true) else { return .noBackup }
        return .done
    }

    /// Step two, once the sheet is gone: the goodbye covers the screen, then this phone is cleaned.
    /// The 2FA entry and the Telegram links stay, so signing back in brings everything home.
    func finishSignOut() async {
        let name = profile?.username ?? ""
        withAnimation(.easeInOut(duration: 0.5)) { farewell = .signOut(name) }
        try? await Task.sleep(nanoseconds: 700_000_000)
        eraseEverything()
    }

    // MARK: - Erase

    /// Deletes the account for good: cloud copy, Telegram links and everything on this iPhone.
    func deleteAccount(includeCloud: Bool) async {
        if includeCloud && space == .real {
            busy = tr("نحذف نسختك من السحابة…", "Deleting your cloud copy…")
            await SupabaseClient.shared.deleteCloudData()
            busy = nil
        }
        TelegramService.shared.settings = .init()
        Keychain.delete(TOTPCarry.account)
        eraseEverything()
    }

    func eraseEverything() {
        lock(sound: false)
        VaultStorage.wipeAll()
        SupabaseClient.shared.signOut()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for k in ["sec.biometric", "sec.failCount", "sec.lockUntil", "backup.last", "backup.dirty", "sec.lastSeenIntrusion"] {
            defaults.removeObject(forKey: k)
        }
        WidgetBridge.update()
        LiveActivityManager.sync()
        withAnimation { phase = .welcome }
    }
}
