import Foundation
import SwiftUI

/// Optional: posts a neat, formatted copy of what you add to Telegram through the official
/// MNLOVO SAVER bot (@mnlovo_sbot). The bot token lives only on our server (Supabase Edge Function);
/// the app talks to it with your signed-in session. 🔴 top-secret items are never sent.
final class TelegramService {
    static let shared = TelegramService()
    static let botUsername = "mnlovo_sbot"
    static let blue = Color(hex: 0x2AABEE)
    private let fn = "saver-telegram"

    struct Target: Codable, Hashable, Identifiable {
        var id: Int64
        var title: String
        var type: String
        var enabled: Bool
        var role: String = "owner"

        init(id: Int64, title: String, type: String, enabled: Bool, role: String = "owner") {
            self.id = id; self.title = title; self.type = type; self.enabled = enabled; self.role = role
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int64.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "private"
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            role = try c.decodeIfPresent(String.self, forKey: .role) ?? "owner"
        }

        var isFriend: Bool { role == "friend" }
        var typeTitle: String {
            if isFriend { return tr("شخص ثاني", "Another person") }
            switch type {
            case "channel": return tr("قناة", "Channel")
            case "group", "supergroup": return tr("قروب", "Group")
            default: return tr("محادثة البوت (الخاصة)", "Bot chat (private)")
            }
        }
        var icon: String {
            if isFriend { return "person.2.fill" }
            switch type {
            case "channel": return "megaphone.fill"
            case "group", "supergroup": return "person.3.fill"
            default: return "paperplane.fill"
            }
        }
    }

    struct Settings: Codable, Equatable {
        var enabled = false
        var targets: [Target] = []
        var accounts = true
        var passwords = false
        var reminders = true
        var notes = true
        var files = true
        var updates = false
        var includeSensitive = false
        /// Values arrive blurred (Telegram spoiler) until tapped.
        var spoiler = true

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            targets = try c.decodeIfPresent([Target].self, forKey: .targets) ?? []
            accounts = try c.decodeIfPresent(Bool.self, forKey: .accounts) ?? true
            passwords = try c.decodeIfPresent(Bool.self, forKey: .passwords) ?? false
            reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? true
            notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? true
            files = try c.decodeIfPresent(Bool.self, forKey: .files) ?? true
            updates = try c.decodeIfPresent(Bool.self, forKey: .updates) ?? false
            includeSensitive = try c.decodeIfPresent(Bool.self, forKey: .includeSensitive) ?? false
            spoiler = try c.decodeIfPresent(Bool.self, forKey: .spoiler) ?? true
        }
    }

    enum TGError: LocalizedError {
        case noCloud, server(String)
        var errorDescription: String? {
            switch self {
            case .noCloud: return tr("لازم تكون مسجّل دخول بالسحابة (كود الإيميل) عشان نربط تيليجرام.",
                                     "You need to be signed in to the cloud (email code) to link Telegram.")
            case .server(let m): return m
            }
        }
    }

    private let settingsKey = "tg.official.settings"

    var settings: Settings {
        get {
            guard let d = UserDefaults.standard.data(forKey: settingsKey),
                  let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
            return s
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: settingsKey) }
        }
    }

    var cloudReady: Bool { SupabaseClient.shared.isConfigured && SupabaseClient.shared.hasSession }
    var isLinked: Bool { !settings.targets.isEmpty }
    var isReady: Bool { settings.enabled && cloudReady && settings.targets.contains { $0.enabled } }
    var privateTarget: Target? { settings.targets.first { $0.type == "private" && !$0.isFriend } }

    // MARK: Server calls

    private func call(_ action: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        guard cloudReady else { throw TGError.noCloud }
        var payload = extra
        payload["action"] = action
        return try await SupabaseClient.shared.callFunction(fn, payload)
    }

    /// One-time code that ties a Telegram chat to this account (valid 30 minutes).
    private func linkCode(friend: Bool = false) async throws -> (bot: String, code: String) {
        let r = try await call("link", friend ? ["kind": "friend"] : [:])
        guard let code = r["code"] as? String else { throw TGError.server(tr("ما قدرنا نجهّز رابط الربط.", "Couldn't prepare the link.")) }
        return ((r["bot"] as? String) ?? Self.botUsername, code)
    }

    /// Opens the bot in Telegram; tapping Start links the private chat.
    func privateLink() async throws -> URL {
        let c = try await linkCode()
        return URL(string: "https://t.me/\(c.bot)?start=\(c.code)")!
    }

    /// Telegram shows the user's groups; the bot joins the chosen one and links it.
    func groupLink() async throws -> URL {
        let c = try await linkCode()
        return URL(string: "https://t.me/\(c.bot)?startgroup=\(c.code)&admin=post_messages")!
    }

    /// A one-time link for another person: when they tap Start, they receive your updates too.
    func friendLink() async throws -> URL {
        let c = try await linkCode(friend: true)
        return URL(string: "https://t.me/\(c.bot)?start=\(c.code)")!
    }

    /// Telegram shows the user's channels; the bot is added as an admin that can only post.
    func channelLink() -> URL {
        URL(string: "https://t.me/\(Self.botUsername)?startchannel&admin=post_messages")!
    }

    /// Fetches linked chats from the server and caches them.
    @discardableResult
    func refresh() async throws -> [Target] {
        let r = try await call("status")
        let list = (r["targets"] as? [[String: Any]] ?? []).compactMap { t -> Target? in
            guard let id = (t["chat_id"] as? NSNumber)?.int64Value else { return nil }
            return Target(id: id, title: t["title"] as? String ?? "\(id)", type: t["type"] as? String ?? "private",
                          enabled: t["enabled"] as? Bool ?? true, role: t["role"] as? String ?? "owner")
        }
        var s = settings
        let wasEmpty = s.targets.isEmpty
        s.targets = list
        if wasEmpty && !list.isEmpty { s.enabled = true }
        if list.isEmpty { s.enabled = false }
        settings = s
        return list
    }

    func setEnabled(_ target: Target, _ on: Bool) async throws {
        _ = try await call("toggle", ["chat_id": target.id, "enabled": on])
        var s = settings
        if let i = s.targets.firstIndex(where: { $0.id == target.id }) { s.targets[i].enabled = on }
        settings = s
    }

    func remove(_ target: Target) async throws {
        _ = try await call("remove", ["chat_id": target.id])
        var s = settings
        s.targets.removeAll { $0.id == target.id }
        if s.targets.isEmpty { s.enabled = false }
        settings = s
    }

    /// Sends to every enabled linked chat; returns how many received it.
    @discardableResult
    func send(_ html: String) async throws -> Int {
        let r = try await call("send", ["text": html])
        return (r["sent"] as? NSNumber)?.intValue ?? 0
    }

    // MARK: Events

    enum Event {
        case accountAdded(AccountItem), accountUpdated(AccountItem)
        case noteAdded(SecureNote), noteUpdated(SecureNote)
        case reminderAdded(Reminder), reminderUpdated(Reminder), reminderDone(Reminder)
        case fileAdded(VaultFile)
    }

    /// Fire-and-forget; respects the user's choices and never sends 🔴 items.
    func post(_ event: Event, space: VaultSpace) {
        guard space == .real, isReady else { return }
        let s = settings
        func allowed(_ level: Sensitivity) -> Bool {
            level == .normal || (level == .sensitive && s.includeSensitive)
        }
        var text: String?
        switch event {
        case .accountAdded(let a) where s.accounts && allowed(a.sensitivity): text = format(account: a, new: true, s: s)
        case .accountUpdated(let a) where s.accounts && s.updates && allowed(a.sensitivity): text = format(account: a, new: false, s: s)
        case .noteAdded(let n) where s.notes && allowed(n.sensitivity): text = format(note: n, new: true)
        case .noteUpdated(let n) where s.notes && s.updates && allowed(n.sensitivity): text = format(note: n, new: false)
        case .reminderAdded(let r) where s.reminders && allowed(r.sensitivity): text = format(reminder: r, header: tr("⏰ <b>تذكير جديد</b>", "⏰ <b>New reminder</b>"))
        case .reminderUpdated(let r) where s.reminders && s.updates && allowed(r.sensitivity): text = format(reminder: r, header: tr("✏️ <b>تعديل تذكير</b>", "✏️ <b>Reminder updated</b>"))
        case .reminderDone(let r) where s.reminders && allowed(r.sensitivity): text = format(reminder: r, header: tr("✅ <b>خلصت مهمة</b>", "✅ <b>Task done</b>"))
        case .fileAdded(let f) where s.files && allowed(f.sensitivity): text = format(file: f)
        default: text = nil
        }
        guard let text else { return }
        Task {
            do {
                let n = try await send(text)
                if n == 0 { try? await refresh() }
                UserDefaults.standard.removeObject(forKey: "tg.lastError")
            } catch {
                UserDefaults.standard.set(error.localizedDescription, forKey: "tg.lastError")
            }
        }
    }

    // MARK: Formatting (Telegram HTML)

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private let line = "━━━━━━━━━━━━━━"

    /// Escapes a value and, if blurring is on, hides it under a Telegram spoiler.
    private func v(_ text: String) -> String {
        let e = Self.esc(text)
        return settings.spoiler ? "<tg-spoiler>\(e)</tg-spoiler>" : e
    }

    private func footer() -> String {
        "\(line)\n🕒 \(Self.esc(Fmt.date(Date())))\n<i>\(Brand.appName)</i>"
    }

    private func levelText(_ l: Sensitivity) -> String {
        switch l {
        case .normal: return "🟢 " + l.title
        case .sensitive: return "🟡 " + l.title
        case .secret: return "🔴 " + l.title
        }
    }

    func format(account a: AccountItem, new: Bool, s: Settings) -> String {
        var out = new ? tr("🔐 <b>حساب جديد</b>  #حسابات", "🔐 <b>New account</b>  #accounts")
                      : tr("✏️ <b>تعديل حساب</b>  #حسابات", "✏️ <b>Account updated</b>  #accounts")
        out += "\n\(line)\n"
        out += tr("<b>التطبيق:</b> ", "<b>App:</b> ") + v(a.service) + "\n"
        if !a.login.isEmpty {
            out += tr("<b>المستخدم:</b> ", "<b>Login:</b> ") + (s.spoiler ? v(a.login) : "<code>\(Self.esc(a.login))</code>") + "\n"
        }
        if s.passwords && !a.password.isEmpty {
            out += tr("<b>كلمة السر:</b> ", "<b>Password:</b> ") + "<tg-spoiler>\(Self.esc(a.password))</tg-spoiler>\n"
        }
        if !a.url.isEmpty { out += tr("<b>الرابط:</b> ", "<b>Link:</b> ") + v(a.url) + "\n" }
        if a.totp != nil { out += tr("<b>2FA:</b> ✓ مفعّل\n", "<b>2FA:</b> ✓ on\n") }
        out += tr("<b>الحساسية:</b> ", "<b>Level:</b> ") + levelText(a.sensitivity) + "\n"
        if !a.notes.isEmpty { out += "📝 " + v(String(a.notes.prefix(800))) + "\n" }
        return out + footer()
    }

    func format(note n: SecureNote, new: Bool) -> String {
        var out = new ? tr("📝 <b>ملاحظة جديدة</b>  #ملاحظات", "📝 <b>New note</b>  #notes")
                      : tr("✏️ <b>تعديل ملاحظة</b>  #ملاحظات", "✏️ <b>Note updated</b>  #notes")
        out += "\n\(line)\n<b>\(v(n.title))</b>\n"
        out += v(String(n.body.prefix(3200))) + "\n"
        out += tr("<b>الحساسية:</b> ", "<b>Level:</b> ") + levelText(n.sensitivity) + "\n"
        return out + footer()
    }

    func format(reminder r: Reminder, header: String) -> String {
        var out = header + tr("  #تذكيرات", "  #reminders") + "\n\(line)\n"
        out += "<b>\(v(r.title))</b>\n"
        out += tr("<b>النوع:</b> ", "<b>Type:</b> ") + r.kind.title + "\n"
        out += tr("<b>الموعد:</b> ", "<b>Due:</b> ") + Self.esc(Fmt.date(r.due)) + "\n"
        if !r.done { out += "⏳ " + Self.esc(Fmt.remaining(until: r.due)) + "\n" }
        if !r.notes.isEmpty { out += "📝 " + v(String(r.notes.prefix(800))) + "\n" }
        return out + footer()
    }

    func format(file f: VaultFile) -> String {
        var out = tr("📎 <b>ملف جديد في الخزنة</b>  #الخزنة", "📎 <b>New file in the vault</b>  #vault")
        out += "\n\(line)\n"
        out += tr("<b>الاسم:</b> ", "<b>Name:</b> ") + v(f.name) + "\n"
        out += tr("<b>الحجم:</b> ", "<b>Size:</b> ") + Fmt.bytes(f.size) + "\n"
        out += tr("<i>الملف نفسه يبقى مشفّر في جوالك، ما ينرسل.</i>\n", "<i>The file itself stays encrypted on your phone.</i>\n")
        return out + footer()
    }

    func testMessage() -> String {
        tr("👋 <b>رسالة تجريبية من \(Brand.appName)</b>\n\(line)\nكذا بتوصلك الأشياء: \(v("النص مشوّش، اضغط عليه عشان يبين"))\n🔴 الأشياء السرية جداً ما تنرسل أبداً.\n",
           "👋 <b>Test message from \(Brand.appName)</b>\n\(line)\nThis is how items arrive: \(v("blurred text, tap to reveal"))\n🔴 Top-secret items are never sent.\n")
            + footer()
    }
}
