import Foundation
import CryptoKit

/// Minimal Supabase client (free plan): email one-time codes + encrypted backup storage.
/// The server never sees your data in clear — backups are encrypted on the phone first.
final class SupabaseClient {
    static let shared = SupabaseClient()

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var userID: String
        var email: String
        var expiresAt: Date
    }

    enum SBError: LocalizedError {
        case notConfigured, server(String), noSession, notFound
        var errorDescription: String? {
            switch self {
            case .notConfigured: return tr("السحابة غير مُعدّة بعد.", "The cloud isn't set up yet.")
            case .server(let m): return m
            case .noSession: return tr("اربط السحابة بكود الإيميل أولاً.", "Connect the cloud with an email code first.")
            case .notFound: return tr("ما لقيت نسخة احتياطية في السحابة.", "No cloud backup found.")
            }
        }
    }

    private let urlKey = "sb.url", anonKey = "sb.anon", sessionAccount = "sb.session"

    var baseURL: String {
        get {
            let custom = UserDefaults.standard.string(forKey: urlKey) ?? ""
            return custom.isEmpty ? SupabaseConfig.url : custom
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: urlKey) }
    }
    var anon: String {
        get {
            let custom = UserDefaults.standard.string(forKey: anonKey) ?? ""
            return custom.isEmpty ? SupabaseConfig.publishableKey : custom
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: anonKey) }
    }
    var isConfigured: Bool { baseURL.hasPrefix("https://") && anon.count > 20 }

    var session: Session? {
        get {
            guard let d = Keychain.get(sessionAccount) else { return nil }
            return try? JSONDecoder().decode(Session.self, from: d)
        }
        set {
            if let s = newValue, let d = try? JSONEncoder().encode(s) { Keychain.set(d, account: sessionAccount) }
            else { Keychain.delete(sessionAccount) }
        }
    }

    // MARK: HTTP

    private func request(_ path: String, method: String = "POST", json: [String: Any]? = nil,
                         body: Data? = nil, bearer: String? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard isConfigured, let url = URL(string: baseURL + path) else { throw SBError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue(anon, forHTTPHeaderField: "apikey")
        // New "sb_publishable_…" keys are not JWTs: they go only in the apikey header.
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        } else if !anon.hasPrefix("sb_") {
            req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let body {
            req.httpBody = body
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SBError.server("No response") }
        return (data, http)
    }

    private func message(from data: Data, status: Int) -> String {
        let raw = String(data: data, encoding: .utf8) ?? ""
        if status == 429 || raw.contains("rate limit") {
            return tr("طلبات كثيرة. انتظر دقيقة وجرّب مرة ثانية.", "Too many requests. Wait a minute and try again.")
        }
        if raw.localizedCaseInsensitiveContains("sending") && raw.localizedCaseInsensitiveContains("email") {
            return tr("ما قدرنا نطرش الإيميل. تأكد من إعدادات الإرسال (SMTP) في Supabase وجرّب بعد دقيقة.",
                      "Couldn't send the email. Check the SMTP settings in Supabase and try again in a minute.")
        }
        if raw.contains("otp_expired") || raw.localizedCaseInsensitiveContains("expired") || raw.localizedCaseInsensitiveContains("invalid") {
            return tr("الكود غلط أو انتهى. اطلب كود جديد.", "The code is wrong or expired. Request a new one.")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["msg", "message", "error_description", "error"] {
                if let m = obj[k] as? String { return "\(m) (\(status))" }
            }
        }
        return tr("خطأ من الخادم", "Server error") + " (\(status))"
    }

    /// Calls an Edge Function as the signed-in user and returns its JSON.
    func callFunction(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let s = try await validSession()
        let (data, http) = try await request("/functions/v1/\(name)", json: payload, bearer: s.accessToken)
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: data, status: http.statusCode)) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    var hasSession: Bool { session != nil }

    /// Simple connectivity test for the settings screen.
    func testConnection() async -> Bool {
        guard let result = try? await request("/auth/v1/settings", method: "GET") else { return false }
        return result.1.statusCode == 200
    }

    // MARK: Email one-time code

    func sendEmailCode(to email: String) async throws {
        let (data, http) = try await request("/auth/v1/otp", json: ["email": email.lowercased(), "create_user": true])
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: data, status: http.statusCode)) }
    }

    @discardableResult
    func verifyEmailCode(email: String, code: String) async throws -> Session {
        let token = TOTP.westernDigits(code.filter { !$0.isWhitespace })
        let (data, http) = try await request("/auth/v1/verify", json: ["type": "email", "email": email.lowercased(), "token": token])
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: data, status: http.statusCode)) }
        let s = try parseSession(data, fallbackEmail: email)
        session = s
        return s
    }

    private func parseSession(_ data: Data, fallbackEmail: String) throws -> Session {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { throw SBError.server("Bad session") }
        let user = obj["user"] as? [String: Any]
        let uid = user?["id"] as? String ?? ""
        let mail = user?["email"] as? String ?? fallbackEmail
        let expiresIn = obj["expires_in"] as? Double ?? 3600
        return Session(accessToken: access, refreshToken: refresh, userID: uid, email: mail,
                       expiresAt: Date().addingTimeInterval(expiresIn - 60))
    }

    private func validSession() async throws -> Session {
        guard var s = session else { throw SBError.noSession }
        if s.expiresAt > Date() { return s }
        let (data, http) = try await request("/auth/v1/token?grant_type=refresh_token", json: ["refresh_token": s.refreshToken])
        guard (200..<300).contains(http.statusCode) else {
            session = nil
            throw SBError.noSession
        }
        s = try parseSession(data, fallbackEmail: s.email)
        session = s
        return s
    }

    func signOut() { session = nil }

    // MARK: Account registry (one account per email; warn when a phone is shared)

    struct SignupCheck {
        var emailTaken: Bool
        var phoneHints: [String]
    }

    static func phoneHash(_ phone: String) -> String {
        let digits = TOTP.westernDigits(phone).filter { $0.isASCII && $0.isNumber }
        let data = Data("saver|\(digits.suffix(9))".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// "mnloae@gmail.com" → "m••••e@gmail.com"
    static func emailHint(_ email: String) -> String {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let at = e.firstIndex(of: "@") else { return e }
        let local = String(e[..<at])
        let domain = String(e[at...])
        guard let first = local.first, let last = local.last else { return e }
        let mid = String(repeating: "•", count: max(2, min(6, local.count - 2)))
        return local.count <= 2 ? "\(first)•\(domain)" : "\(first)\(mid)\(last)\(domain)"
    }

    /// nil when the check isn't available (offline, or registry.sql not run yet) — sign-up then continues.
    func checkSignup(email: String, phone: String) async -> SignupCheck? {
        guard isConfigured,
              let result = try? await request("/rest/v1/rpc/saver_check_signup",
                                              json: ["p_email": email.lowercased(), "p_phone_hash": Self.phoneHash(phone)]),
              (200..<300).contains(result.1.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { return nil }
        return SignupCheck(emailTaken: obj["email_taken"] as? Bool ?? false,
                           phoneHints: obj["phone_hints"] as? [String] ?? [])
    }

    /// One-way fingerprint of the birth date, so support can confirm it when you tell them (never stored in clear).
    static func day(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dobHash(_ birth: Date) -> String {
        SHA256.hash(data: Data("saver|dob|\(day(birth))".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func registerAccount(email: String, phone: String, username: String? = nil, birth: Date? = nil) async {
        guard let s = try? await validSession() else { return }
        var body: [String: Any] = ["user_id": s.userID, "email": email.lowercased(),
                                   "phone_hash": Self.phoneHash(phone), "email_hint": Self.emailHint(email),
                                   "updated_at": ISO8601DateFormatter().string(from: Date())]
        if let username { body["username"] = username }
        if let birth {
            body["dob_hash"] = Self.dobHash(birth)
            body["dob"] = Self.day(birth)
        }
        if !phone.isEmpty { body["phone"] = phone }
        if let r = try? await request("/rest/v1/saver_accounts?on_conflict=user_id", json: body, bearer: s.accessToken,
                                      headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]),
           (200..<300).contains(r.1.statusCode) {
            UserDefaults.standard.set(s.userID, forKey: "cloud.userID")
        }
    }

    // MARK: Username (email code first, then locked for 90 days — see supabase/username.sql)

    enum UsernameChange {
        case ok(next: Date)
        case locked(until: Date)
        case needsCode, tooShort, same, failed(String)
    }

    private static func isoDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// When the name can be changed again (nil = now).
    func usernameUnlockDate() async -> Date? {
        guard let s = try? await validSession(),
              let r = try? await request("/rest/v1/saver_accounts?select=username_changed_at&user_id=eq.\(s.userID)",
                                         method: "GET", bearer: s.accessToken),
              (200..<300).contains(r.1.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: r.0) as? [[String: Any]],
              let changed = Self.isoDate(rows.first?["username_changed_at"]) else { return nil }
        let next = changed.addingTimeInterval(90 * 86400)
        return next > Date() ? next : nil
    }

    /// Call right after `verifyEmailCode` — the server checks that this session came from that code.
    func changeUsername(_ name: String) async -> UsernameChange {
        do {
            let s = try await validSession()
            let (data, http) = try await request("/rest/v1/rpc/saver_change_username", json: ["p_name": name], bearer: s.accessToken)
            guard (200..<300).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed(message(from: data, status: http.statusCode))
            }
            if obj["ok"] as? Bool == true {
                return .ok(next: Self.isoDate(obj["next_at"]) ?? Date().addingTimeInterval(90 * 86400))
            }
            switch obj["error"] as? String {
            case "locked": return .locked(until: Self.isoDate(obj["next_at"]) ?? Date().addingTimeInterval(90 * 86400))
            case "code": return .needsCode
            case "length": return .tooShort
            case "same": return .same
            default: return .failed(obj["error"] as? String ?? "")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Backup storage (bucket "backups", path <user-id>/vault.saver)

    func uploadBackup(_ data: Data) async throws {
        let s = try await validSession()
        let (resp, http) = try await request("/storage/v1/object/backups/\(s.userID)/vault.saver", body: data, bearer: s.accessToken,
                                             headers: ["Content-Type": "application/octet-stream", "x-upsert": "true"])
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: resp, status: http.statusCode)) }
    }

    func downloadBackup() async throws -> Data {
        let s = try await validSession()
        let (data, http) = try await request("/storage/v1/object/authenticated/backups/\(s.userID)/vault.saver",
                                             method: "GET", bearer: s.accessToken)
        if http.statusCode == 404 || http.statusCode == 400 { throw SBError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: data, status: http.statusCode)) }
        return data
    }

    /// Removes everything this account has on the server: backup, registry entry and Telegram links.
    func deleteCloudData() async {
        guard let s = try? await validSession() else { signOut(); return }
        _ = try? await callFunction("saver-telegram", ["action": "unlink_all"])
        _ = try? await request("/storage/v1/object/backups/\(s.userID)/vault.saver", method: "DELETE", bearer: s.accessToken)
        _ = try? await request("/rest/v1/saver_accounts?user_id=eq.\(s.userID)", method: "DELETE", bearer: s.accessToken,
                               headers: ["Prefer": "return=minimal"])
        signOut()
    }

    // MARK: Support desk (admin key only)

    func adminCall(key: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let (data, http) = try await request("/functions/v1/saver-admin", json: payload, headers: ["x-admin-key": key])
        if http.statusCode == 403 { throw SBError.server(tr("مفتاح الدعم غلط.", "Wrong support key.")) }
        if http.statusCode == 429 { throw SBError.server(tr("محاولات كثيرة، انتظر ربع ساعة.", "Too many attempts, wait 15 minutes.")) }
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let e = obj["error"] as? String ?? ""
            if e == "email_taken" { throw SBError.server(tr("هالإيميل مستخدم في حساب ثاني.", "That email belongs to another account.")) }
            throw SBError.server(e.isEmpty ? message(from: data, status: http.statusCode) : e)
        }
        return obj
    }
}
