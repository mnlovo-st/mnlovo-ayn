import Foundation

/// "Heartbeat" — if the vault isn't opened for a long time, the bot checks whether you're OK, and if
/// nobody answers it hands a copy of your data to one person you picked beforehand.
///
/// Note on trust: for the server to be able to deliver readable data later, it has to hold that copy.
/// So the chosen items leave the phone's end-to-end encryption and sit in a server-only table until
/// they're delivered or you turn the feature off. Nothing else in the vault is affected.
@MainActor
final class LegacyService: ObservableObject {
    static let shared = LegacyService()

    struct Status: Equatable {
        var enabled = false
        var intervalDays = 30
        var graceDays = 7
        var recipientName = ""
        var hasRecipient = false
        var lastSeen: Date?
        var state = "ok"
        var bundleAt: Date?
        var askedCount = 0

        var isArmed: Bool { enabled && hasRecipient && bundleAt != nil }
        /// When the bot would start asking if the app stayed closed from now on.
        var silentUntil: Date? { lastSeen.map { $0.addingTimeInterval(Double(intervalDays) * 86400) } }
        var deliverAt: Date? { lastSeen.map { $0.addingTimeInterval(Double(intervalDays + graceDays) * 86400) } }
    }

    /// What goes into the parcel.
    struct Selection: Codable, Equatable {
        var accounts = true
        var passwords = true
        var notes = true
        var reminders = false
        var fileList = false
        var message = ""

        static var saved: Selection {
            guard let d = UserDefaults.standard.data(forKey: "legacy.selection"),
                  let s = try? JSONDecoder().decode(Selection.self, from: d) else { return Selection() }
            return s
        }
        func save() {
            if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "legacy.selection") }
        }
    }

    @Published var status = Status()

    private var tg: TelegramService { .shared }
    private func call(_ action: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        guard tg.cloudReady else { throw TelegramService.TGError.noCloud }
        var p = extra
        p["action"] = action
        return try await SupabaseClient.shared.callFunction("saver-telegram", p)
    }

    private func parse(_ r: [String: Any]) -> Status {
        var s = Status()
        s.enabled = r["enabled"] as? Bool ?? false
        s.intervalDays = (r["interval_days"] as? NSNumber)?.intValue ?? 30
        s.graceDays = (r["grace_days"] as? NSNumber)?.intValue ?? 7
        s.recipientName = r["recipient_name"] as? String ?? ""
        s.hasRecipient = r["recipient_chat_id"] != nil && !(r["recipient_chat_id"] is NSNull)
        s.state = r["state"] as? String ?? "ok"
        s.askedCount = (r["asked_count"] as? NSNumber)?.intValue ?? 0
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: String) -> Date? {
            guard let t = r[key] as? String else { return nil }
            return iso.date(from: t) ?? ISO8601DateFormatter().date(from: t)
        }
        s.lastSeen = date("last_seen")
        s.bundleAt = date("bundle_at")
        return s
    }

    @discardableResult
    func refresh() async -> Status {
        guard let r = try? await call("legacy_get") else { return status }
        status = parse(r)
        return status
    }

    func save(enabled: Bool? = nil, interval: Int? = nil, grace: Int? = nil, bundle: String? = nil,
              clearRecipient: Bool = false) async throws {
        var p: [String: Any] = [:]
        if let enabled { p["enabled"] = enabled }
        if let interval { p["interval_days"] = interval }
        if let grace { p["grace_days"] = grace }
        if let bundle { p["bundle"] = bundle }
        if clearRecipient { p["clear_recipient"] = true }
        status = parse(try await call("legacy_set", p))
    }

    /// A one-time link the chosen person opens to become the trustee.
    func recipientLink() async throws -> URL {
        let r = try await call("link", ["kind": "legacy"])
        guard let code = r["code"] as? String else { throw TelegramService.TGError.server(tr("ما قدرنا نجهّز الرابط.", "Couldn't prepare the link.")) }
        let bot = (r["bot"] as? String) ?? TelegramService.botUsername
        return URL(string: "https://t.me/\(bot)?start=\(code)")!
    }

    func sendTestToRecipient() async throws { _ = try await call("legacy_test") }

    /// Called whenever the vault opens: proof of life, at most once an hour.
    func checkIn() {
        guard tg.cloudReady else { return }
        let key = "legacy.lastCheckin"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        Task { _ = try? await call("legacy_checkin") }
    }
}
