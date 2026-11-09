import Foundation

/// Optional: posts a neat, formatted copy of what you add to a Telegram channel, group or chat
/// through your own bot. 🔴 top-secret items are never sent.
final class TelegramService {
    static let shared = TelegramService()

    struct Chat: Codable, Hashable, Identifiable {
        var id: Int64
        var title: String
        var type: String

        var typeTitle: String {
            switch type {
            case "channel": return tr("قناة", "Channel")
            case "group", "supergroup": return tr("قروب", "Group")
            default: return tr("محادثة", "Chat")
            }
        }
        var icon: String {
            switch type {
            case "channel": return "megaphone.fill"
            case "group", "supergroup": return "person.3.fill"
            default: return "person.fill"
            }
        }
    }

    struct Settings: Codable, Equatable {
        var enabled = false
        var chat: Chat?
        var botName = ""
        var accounts = true
        var passwords = false
        var reminders = true
        var notes = true
        var files = true
        var updates = false
        var includeSensitive = false
    }

    enum TGError: LocalizedError {
        case badToken, server(String), noChat
        var errorDescription: String? {
            switch self {
            case .badToken: return tr("رمز البوت غلط. انسخه من BotFather مرة ثانية.", "Invalid bot token. Copy it again from BotFather.")
            case .server(let m): return m
            case .noChat: return tr("اختر المحادثة أول.", "Choose a chat first.")
            }
        }
    }

    private let settingsKey = "tg.settings"
    private let tokenAccount = "tg.token"

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

    var token: String? {
        get { Keychain.get(tokenAccount).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let v = newValue, !v.isEmpty { Keychain.set(Data(v.utf8), account: tokenAccount) }
            else { Keychain.delete(tokenAccount) }
        }
    }

    var isReady: Bool { settings.enabled && settings.chat != nil && token != nil }

    // MARK: Bot API

    private func call(_ method: String, token: String, body: [String: Any]? = nil) async throws -> Any {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else { throw TGError.badToken }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if (resp as? HTTPURLResponse)?.statusCode == 401 || (resp as? HTTPURLResponse)?.statusCode == 404 { throw TGError.badToken }
        guard obj["ok"] as? Bool == true else {
            throw TGError.server((obj["description"] as? String) ?? tr("خطأ من تيليجرام", "Telegram error"))
        }
        return obj["result"] ?? [:]
    }

    /// Checks the token and returns the bot's @username.
    func verify(token: String) async throws -> String {
        let r = try await call("getMe", token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let me = r as? [String: Any], let u = me["username"] as? String else { throw TGError.badToken }
        return u
    }

    /// Chats where the bot was added or received a message recently.
    func discoverChats(token: String) async throws -> [Chat] {
        let r = try await call("getUpdates", token: token,
                               body: ["allowed_updates": ["message", "channel_post", "my_chat_member", "edited_channel_post"], "limit": 100])
        var found: [Int64: Chat] = [:]
        for u in (r as? [[String: Any]]) ?? [] {
            for key in ["message", "channel_post", "edited_channel_post", "my_chat_member"] {
                guard let m = u[key] as? [String: Any], let c = m["chat"] as? [String: Any],
                      let id = (c["id"] as? NSNumber)?.int64Value else { continue }
                let type = c["type"] as? String ?? "private"
                let title = (c["title"] as? String)
                    ?? [c["first_name"] as? String, c["last_name"] as? String].compactMap { $0 }.joined(separator: " ")
                found[id] = Chat(id: id, title: title.isEmpty ? (c["username"] as? String ?? "\(id)") : title, type: type)
            }
        }
        return Array(found.values).sorted { $0.title < $1.title }
    }

    func send(_ html: String, to chat: Chat? = nil) async throws {
        guard let token else { throw TGError.badToken }
        guard let c = chat ?? settings.chat else { throw TGError.noChat }
        _ = try await call("sendMessage", token: token, body: [
            "chat_id": c.id, "text": html, "parse_mode": "HTML", "disable_web_page_preview": true
        ])
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
                try await send(text)
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
        out += tr("<b>التطبيق:</b> ", "<b>App:</b> ") + Self.esc(a.service) + "\n"
        if !a.login.isEmpty { out += tr("<b>المستخدم:</b> ", "<b>Login:</b> ") + "<code>\(Self.esc(a.login))</code>\n" }
        if s.passwords && !a.password.isEmpty {
            out += tr("<b>كلمة السر:</b> ", "<b>Password:</b> ") + "<tg-spoiler>\(Self.esc(a.password))</tg-spoiler>\n"
        }
        if !a.url.isEmpty { out += tr("<b>الرابط:</b> ", "<b>Link:</b> ") + Self.esc(a.url) + "\n" }
        if a.totp != nil { out += tr("<b>2FA:</b> ✓ مفعّل\n", "<b>2FA:</b> ✓ on\n") }
        out += tr("<b>الحساسية:</b> ", "<b>Level:</b> ") + levelText(a.sensitivity) + "\n"
        if !a.notes.isEmpty { out += "📝 " + Self.esc(String(a.notes.prefix(800))) + "\n" }
        return out + footer()
    }

    func format(note n: SecureNote, new: Bool) -> String {
        var out = new ? tr("📝 <b>ملاحظة جديدة</b>  #ملاحظات", "📝 <b>New note</b>  #notes")
                      : tr("✏️ <b>تعديل ملاحظة</b>  #ملاحظات", "✏️ <b>Note updated</b>  #notes")
        out += "\n\(line)\n<b>\(Self.esc(n.title))</b>\n"
        out += Self.esc(String(n.body.prefix(3200))) + "\n"
        out += tr("<b>الحساسية:</b> ", "<b>Level:</b> ") + levelText(n.sensitivity) + "\n"
        return out + footer()
    }

    func format(reminder r: Reminder, header: String) -> String {
        var out = header + tr("  #تذكيرات", "  #reminders") + "\n\(line)\n"
        out += "<b>\(Self.esc(r.title))</b>\n"
        out += tr("<b>النوع:</b> ", "<b>Type:</b> ") + r.kind.title + "\n"
        out += tr("<b>الموعد:</b> ", "<b>Due:</b> ") + Self.esc(Fmt.date(r.due)) + "\n"
        if !r.done { out += "⏳ " + Self.esc(Fmt.remaining(until: r.due)) + "\n" }
        if !r.notes.isEmpty { out += "📝 " + Self.esc(String(r.notes.prefix(800))) + "\n" }
        return out + footer()
    }

    func format(file f: VaultFile) -> String {
        var out = tr("📎 <b>ملف جديد في الخزنة</b>  #الخزنة", "📎 <b>New file in the vault</b>  #vault")
        out += "\n\(line)\n"
        out += tr("<b>الاسم:</b> ", "<b>Name:</b> ") + Self.esc(f.name) + "\n"
        out += tr("<b>الحجم:</b> ", "<b>Size:</b> ") + Fmt.bytes(f.size) + "\n"
        out += tr("<i>الملف نفسه يبقى مشفّر في جوالك، ما ينرسل.</i>\n", "<i>The file itself stays encrypted on your phone.</i>\n")
        return out + footer()
    }

    func testMessage() -> String {
        tr("👋 <b>تم ربط \(Brand.appName)</b>\n\(line)\nمن الحين أي شي تضيفه في التطبيق بيوصل هنا مرتّب.\n🔴 الأشياء السرية جداً ما تنرسل أبداً.\n",
           "👋 <b>\(Brand.appName) connected</b>\n\(line)\nFrom now on, whatever you add in the app shows up here, neatly formatted.\n🔴 Top-secret items are never sent.\n")
            + footer()
    }
}
