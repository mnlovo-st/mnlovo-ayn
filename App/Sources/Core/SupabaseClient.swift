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
            return tr("ما قدرنا نرسل الإيميل. تأكد من إعدادات الإرسال (SMTP) في Supabase وجرّب بعد دقيقة.",
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

    func registerAccount(email: String, phone: String) async {
        guard let s = try? await validSession() else { return }
        let body: [String: Any] = ["user_id": s.userID, "email": email.lowercased(),
                                   "phone_hash": Self.phoneHash(phone), "email_hint": Self.emailHint(email)]
        _ = try? await request("/rest/v1/saver_accounts?on_conflict=user_id", json: body, bearer: s.accessToken,
                               headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
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
}
