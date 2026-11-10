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
        var passwords = true
        var reminders = false
        var notes = false
        var files = false
        var updates = false
        var includeSensitive = true
        /// 🔴 top-secret items too — on by default now; the whole message is blurred anyway.
        var includeSecret = true
        /// The whole message arrives blurred (Telegram spoiler) until tapped.
        var spoiler = true
        /// Ask, after adding each account, whether to post it (and with which cipher).
        var askEachTime = true
        /// Send an intruder photo straight to Telegram the moment it's captured.
        var intruderAlerts = true

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            targets = try c.decodeIfPresent([Target].self, forKey: .targets) ?? []
            accounts = try c.decodeIfPresent(Bool.self, forKey: .accounts) ?? true
            passwords = try c.decodeIfPresent(Bool.self, forKey: .passwords) ?? true
            reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? false
            notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? false
            files = try c.decodeIfPresent(Bool.self, forKey: .files) ?? false
            updates = try c.decodeIfPresent(Bool.self, forKey: .updates) ?? false
            includeSensitive = try c.decodeIfPresent(Bool.self, forKey: .includeSensitive) ?? true
            includeSecret = try c.decodeIfPresent(Bool.self, forKey: .includeSecret) ?? true
            spoiler = try c.decodeIfPresent(Bool.self, forKey: .spoiler) ?? true
            askEachTime = try c.decodeIfPresent(Bool.self, forKey: .askEachTime) ?? true
            intruderAlerts = try c.decodeIfPresent(Bool.self, forKey: .intruderAlerts) ?? true
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
                  var s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
            if !UserDefaults.standard.bool(forKey: "tg.defaults.v4") {
                // Default message set: accounts + passwords + 🟡 + 🔴, fully blurred; reminders/notes/files off.
                ["tg.defaults.v2", "tg.defaults.v3", "tg.defaults.v4"].forEach { UserDefaults.standard.set(true, forKey: $0) }
                s.accounts = true; s.passwords = true; s.includeSensitive = true; s.includeSecret = true; s.spoiler = true
                s.reminders = false; s.notes = false; s.files = false; s.updates = false
                if let e = try? JSONEncoder().encode(s) { UserDefaults.standard.set(e, forKey: settingsKey) }
            }
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
    /// Tells the server this account is about to add a channel, so the channel lands on the right account.
    func prepareChannel() async throws -> URL {
        do {
            _ = try await call("link", ["kind": "channel"])
        } catch SupabaseClient.SBError.server(let m) where m.contains("need_private") || m.contains("409") {
            throw TGError.server(tr("اربط محادثة البوت أول (زر «ربط تيليجرام»)، وبعدها أضف القناة.",
                                    "Link the bot chat first (“Link Telegram”), then add the channel."))
        }
        return channelLink()
    }

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

    /// Posts one account on demand (the per-add prompt). `cipher` nil = normal blurred message;
    /// otherwise the whole body is run through that cipher so only the app (or the key) can read it.
    @discardableResult
    func sendAccountNow(_ a: AccountItem, cipher: Cipher?, key: String = "") async throws -> Int {
        let body = format(account: a, new: true, s: settings)
        if let cipher {
            let blob = cipher.encode(plainAccount(a), key: key)
            let header = tr("🔐 <b>حساب مشفّر</b>", "🔐 <b>Encrypted account</b>")
            let how = cipher == .aes
                ? tr("🔑 ينفك بكلمة المرور من «أداة التشفير» في التطبيق.", "🔑 Decode with the password in the app's Cipher tool.")
                : tr("🔓 الصقه في «أداة التشفير» بالتطبيق عشان يطلع واضح.", "🔓 Paste it into the app's Cipher tool to reveal it.")
            // Plain text, not <code>: the mono face wraps badly on a phone, and long-press copies either way.
            let msg = "\(header)\n\n\(Self.esc(blob))\n\n<i>\(how)</i>"
                + footer(tr("#حسابات", "#accounts"))
            return try await send(msg)   // already unreadable; no spoiler needed
        }
        return try await send(wrap(body))
    }

    /// Plain, unformatted account text — the input for a chosen cipher.
    private func plainAccount(_ a: AccountItem) -> String {
        var lines = [tr("التطبيق: ", "App: ") + a.service]
        if !a.login.isEmpty { lines.append(tr("المستخدم: ", "Login: ") + a.login) }
        if !a.password.isEmpty { lines.append(tr("كلمة السر: ", "Password: ") + a.password) }
        if !a.url.isEmpty { lines.append(tr("الرابط: ", "Link: ") + a.url) }
        if !a.notes.isEmpty { lines.append(a.notes) }
        return lines.joined(separator: "\n")
    }

    /// Sends an intruder snapshot straight to Telegram the moment it's taken (works while the app is locked).
    func sendIntruderAlert(photo: Data?, reason: String) {
        guard settings.intruderAlerts, cloudReady, !settings.targets.isEmpty else { return }
        let when = Fmt.date(Date())
        let caption = tr("🚨 <b>محاولة دخول للتطبيق</b>\n\n\(reason)\n\n<i>#متطفل · \(Self.esc(when))</i>",
                         "🚨 <b>App access attempt</b>\n\n\(reason)\n\n<i>#intruder · \(Self.esc(when))</i>")
        Task {
            var payload: [String: Any] = ["caption": caption]
            if let photo { payload["photo"] = photo.base64EncodedString() }
            _ = try? await call("alert", payload)
        }
    }

    // MARK: Events

    enum Event {
        case accountAdded(AccountItem), accountUpdated(AccountItem)
        case noteAdded(SecureNote), noteUpdated(SecureNote)
        case reminderAdded(Reminder), reminderUpdated(Reminder), reminderDone(Reminder)
        case fileAdded(VaultFile)
    }

    /// Fire-and-forget; respects the user's choices (🔴 items only when the user allows them).
    func post(_ event: Event, space: VaultSpace) {
        guard space == .real, isReady else { return }
        // When the app asks before each account, auto-posting of a new account is suppressed
        // (the prompt handles it); everything else still flows automatically.
        if settings.askEachTime, case .accountAdded = event { return }
        let s = settings
        func allowed(_ level: Sensitivity) -> Bool {
            level == .normal || (level == .sensitive && s.includeSensitive) || (level == .secret && s.includeSecret)
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
        guard var text else { return }
        text = wrap(text)
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
    //
    // House style, after the first version came out looking like a wall of monospace:
    //   • one bold title line, then a blank line — no divider bars
    //   • each field is "label<thin space>value" on its own line, label dim-bold, value plain
    //   • no <pre>/<code> blocks: Telegram renders them in a cramped mono face, and it also
    //     refuses to blur anything inside <code>
    //   • one short italic footer line carrying the hashtag and the time
    // The result reads like a card instead of a terminal dump.

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// With blurring on, the whole message is one spoiler: nothing shows until it's tapped.
    func wrap(_ html: String) -> String {
        settings.spoiler ? "<tg-spoiler>\(html)</tg-spoiler>" : html
    }

    /// Escapes a value for Telegram HTML.
    private func v(_ text: String) -> String {
        Self.esc(text)
    }

    /// One field line. The gap is a real space pair so it survives both RTL and LTR.
    private func row(_ label: String, _ value: String) -> String {
        "<b>\(label)</b>  \(value)\n"
    }

    /// A value the recipient will want to copy. Monospace reads badly in Telegram and it also kills
    /// the spoiler, so copyable values are left as plain text — long-press still copies the line.
    private func field(_ text: String) -> String {
        Self.esc(text)
    }

    /// A secret. With whole-message blurring the outer spoiler already covers it; without it, the
    /// secret gets its own spoiler so a shoulder-surfer sees nothing.
    private func secret(_ text: String) -> String {
        settings.spoiler ? Self.esc(text) : "<tg-spoiler>\(Self.esc(text))</tg-spoiler>"
    }

    private func footer(_ tag: String) -> String {
        "\n<i>\(tag) · \(Self.esc(Fmt.date(Date())))</i>"
    }

    /// The colour goes after the word, the way a label is read, not before it.
    private func levelText(_ l: Sensitivity) -> String {
        switch l {
        case .normal: return l.title + " 🟢"
        case .sensitive: return l.title + " 🟡"
        case .secret: return l.title + " 🔴"
        }
    }

    func format(account a: AccountItem, new: Bool, s: Settings) -> String {
        let tag = tr("#حسابات", "#accounts")
        var out = new ? tr("🔐 <b>حساب جديد</b>", "🔐 <b>New account</b>")
                      : tr("✏️ <b>تعديل حساب</b>", "✏️ <b>Account updated</b>")
        out += "\n\n<b>\(v(a.service))</b>\n"
        if !a.login.isEmpty {
            out += row(tr("المستخدم", "Login"), field(a.login))
        }
        if s.passwords && !a.password.isEmpty {
            out += row(tr("كلمة السر", "Password"), secret(a.password))
        }
        if !a.url.isEmpty { out += row(tr("الرابط", "Link"), v(a.url)) }
        if a.totp != nil { out += row(tr("التحقق بخطوتين", "Two-factor"), tr("مفعّل ✓", "on ✓")) }
        out += row(tr("الحساسية", "Level"), levelText(a.sensitivity))
        if !a.notes.isEmpty { out += "\n📝 " + v(String(a.notes.prefix(800))) + "\n" }
        return out + footer(tag)
    }

    func format(note n: SecureNote, new: Bool) -> String {
        let tag = tr("#ملاحظات", "#notes")
        var out = new ? tr("📝 <b>ملاحظة جديدة</b>", "📝 <b>New note</b>")
                      : tr("✏️ <b>تعديل ملاحظة</b>", "✏️ <b>Note updated</b>")
        out += "\n\n<b>\(v(n.title))</b>\n"
        out += v(String(n.body.prefix(3200))) + "\n"
        out += row(tr("الحساسية", "Level"), levelText(n.sensitivity))
        return out + footer(tag)
    }

    func format(reminder r: Reminder, header: String) -> String {
        let tag = tr("#تذكيرات", "#reminders")
        var out = header + "\n\n<b>\(v(r.title))</b>\n"
        out += row(tr("النوع", "Type"), Self.esc(r.kind.title))
        out += row(tr("الموعد", "Due"), Self.esc(Fmt.date(r.due)))
        if !r.done { out += row(tr("باقي", "Left"), Self.esc(Fmt.remaining(until: r.due))) }
        if !r.notes.isEmpty { out += "\n📝 " + v(String(r.notes.prefix(800))) + "\n" }
        return out + footer(tag)
    }

    func format(file f: VaultFile) -> String {
        let tag = tr("#الخزنة", "#vault")
        var out = tr("📎 <b>ملف جديد في الخزنة</b>", "📎 <b>New file in the vault</b>")
        out += "\n\n<b>\(v(f.name))</b>\n"
        out += row(tr("الحجم", "Size"), Fmt.bytes(f.size))
        out += tr("\n<i>الملف نفسه يبقى مشفّر في تلفونك، ما ينطرش.</i>",
                  "\n<i>The file itself stays encrypted on your phone.</i>")
        return out + footer(tag)
    }

    func testMessage() -> String {
        let tag = tr("#تجربة", "#test")
        let body = settings.spoiler
            ? tr("كذا بتوصلك الأشياء: الرسالة كلها مغطّاة، اضغط عليها عشان تبين.",
                 "This is how items arrive: the whole message is covered, tap it to reveal.")
            : tr("كذا بتوصلك الأشياء — واضحة من غير تغطية، وكلمات السر بس هي المغطّاة.",
                 "This is how items arrive — in the clear, with only passwords covered.")
        return wrap(tr("👋 <b>رسالة تجريبية</b>", "👋 <b>Test message</b>")
                    + "\n\n" + body + "\n" + footer(tag))
    }
}
