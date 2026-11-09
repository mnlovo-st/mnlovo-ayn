import Foundation

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
            case .notConfigured: return tr("Supabase غير مُعد. روح الإعدادات ← السحابة.", "Supabase isn't set up. Go to Settings → Cloud.")
            case .server(let m): return m
            case .noSession: return tr("لازم تتحقق من إيميلك أولاً.", "Verify your email first.")
            case .notFound: return tr("ما لقيت نسخة احتياطية في السحابة.", "No cloud backup found.")
            }
        }
    }

    private let urlKey = "sb.url", anonKey = "sb.anon", sessionAccount = "sb.session"

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: urlKey) }
    }
    var anon: String {
        get { UserDefaults.standard.string(forKey: anonKey) ?? "" }
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
        req.setValue("Bearer \(bearer ?? anon)", forHTTPHeaderField: "Authorization")
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

    // MARK: Backup storage (bucket "backups", path <user-id>/vault.ayn)

    func uploadBackup(_ data: Data) async throws {
        let s = try await validSession()
        let (resp, http) = try await request("/storage/v1/object/backups/\(s.userID)/vault.ayn", body: data, bearer: s.accessToken,
                                             headers: ["Content-Type": "application/octet-stream", "x-upsert": "true"])
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: resp, status: http.statusCode)) }
    }

    func downloadBackup() async throws -> Data {
        let s = try await validSession()
        let (data, http) = try await request("/storage/v1/object/authenticated/backups/\(s.userID)/vault.ayn",
                                             method: "GET", bearer: s.accessToken)
        if http.statusCode == 404 || http.statusCode == 400 { throw SBError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw SBError.server(message(from: data, status: http.statusCode)) }
        return data
    }
}
