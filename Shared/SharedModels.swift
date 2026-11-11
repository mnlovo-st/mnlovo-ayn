import Foundation
import Security
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Data shared between the app and the widget extension (App Group).
enum WidgetShared {
    static let declaredGroup = "group.com.mnlovo.saver"

    /// The App Group this install actually got.
    ///
    /// This is why the widgets were empty: the IPA is re-signed on the phone's side (Sideloadly,
    /// AltStore…) with a free Apple ID, and that re-signing renames the App Group to something tied to
    /// the signer's team, e.g. `group.com.mnlovo.saver.ABCDE12345`. The app kept writing to the name
    /// in the source code, the widget kept reading from it, and the two never met. The provisioning
    /// profile embedded in the bundle says which group was really granted, so both sides read it from
    /// there and agree with each other whatever the signer did.
    static let appGroup: String = {
        let granted = Provision.appGroups
        if granted.contains(declaredGroup) { return declaredGroup }
        if let match = granted.first(where: { $0.lowercased().contains("saver") }) { return match }
        return granted.first ?? declaredGroup
    }()

    /// True only when iOS really gave this process the shared folder. `UserDefaults(suiteName:)`
    /// never says no — without the entitlement it quietly hands back a private store, so the app and
    /// the widget each talk to themselves. This is the honest check.
    static var groupGranted: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    static let key = "widget.payload"
    static let kind = "SaverNextTasks"
    static let streakKind = "SaverStreak"
    static let subsKind = "SaverSubscriptions"
    static let openKind = "SaverQuickOpen"
    static let routinesKind = "SaverRoutines"
    static let countdownKind = "SaverCountdown"
    static let securityKind = "SaverSecurity"

    /// One routine as the widget shows it today.
    struct RoutineItem: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var emoji: String
        var at: Date          // today's time
        var done: Bool
        var secret: Bool? = nil
    }

    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var due: Date
        var icon: String
        var secret: Bool
        /// A routine's next time (ticking it off marks today done) rather than a one-off task.
        var routine: Bool? = nil
    }

    struct Payload: Codable {
        var items: [Item] = []
        var isArabic: Bool = true
        var updated: Date = Date()
        /// Routine streak (best current run of days) and today's progress.
        var streak: Int = 0
        var doneToday: Int = 0
        var totalToday: Int = 0
        /// Next subscription renewal, if any.
        var subTitle: String = ""
        var subDue: Date?
        var subPrice: String = ""
        var subMonthly: String = ""
        /// Today's routines, in time order.
        var routines: [RoutineItem] = []
        /// Safety snapshot: when the last cloud backup ran, intruder events not yet seen, how many accounts.
        var lastBackup: Date?
        var intruders: Int = 0
        var accounts: Int = 0
        var weak: Int = 0
        /// Set when the app wrote this; a fresh `Payload()` means nothing has arrived yet.
        var live: Bool = false

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
            isArabic = try c.decodeIfPresent(Bool.self, forKey: .isArabic) ?? true
            updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
            streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
            doneToday = try c.decodeIfPresent(Int.self, forKey: .doneToday) ?? 0
            totalToday = try c.decodeIfPresent(Int.self, forKey: .totalToday) ?? 0
            subTitle = try c.decodeIfPresent(String.self, forKey: .subTitle) ?? ""
            subDue = try c.decodeIfPresent(Date.self, forKey: .subDue)
            subPrice = try c.decodeIfPresent(String.self, forKey: .subPrice) ?? ""
            subMonthly = try c.decodeIfPresent(String.self, forKey: .subMonthly) ?? ""
            routines = try c.decodeIfPresent([RoutineItem].self, forKey: .routines) ?? []
            lastBackup = try c.decodeIfPresent(Date.self, forKey: .lastBackup)
            intruders = try c.decodeIfPresent(Int.self, forKey: .intruders) ?? 0
            accounts = try c.decodeIfPresent(Int.self, forKey: .accounts) ?? 0
            weak = try c.decodeIfPresent(Int.self, forKey: .weak) ?? 0
            live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? true
        }
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Placeholder content for the widget gallery.
    static var sample: Payload {
        var p = Payload()
        p.items = [
            .init(id: "1", title: "واجب قواعد البيانات", due: Date().addingTimeInterval(86400 * 2), icon: "book.closed.fill", secret: false),
            .init(id: "2", title: "موعد", due: Date().addingTimeInterval(3600 * 5), icon: "calendar.badge.clock", secret: false),
        ]
        p.streak = 12
        p.doneToday = 2
        p.totalToday = 3
        p.subTitle = "Netflix"
        p.subDue = Date().addingTimeInterval(86400 * 4)
        p.subPrice = "56 AED"
        p.subMonthly = "182 AED"
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
        p.routines = [
            .init(id: "r1", title: "شرب ماي", emoji: "💧", at: at(8, 0), done: true),
            .init(id: "r2", title: "رياضة", emoji: "🏃", at: at(17, 30), done: false),
            .init(id: "r3", title: "قراءة", emoji: "📖", at: at(22, 0), done: false),
        ]
        p.lastBackup = Date().addingTimeInterval(-3 * 3600)
        p.accounts = 24
        p.weak = 2
        p.live = true
        return p
    }

    /// Last result of writing the payload, for the status card in the app.
    static var lastKeychainStatus: Int32 = 0

    /// The app writes the payload two ways: the App Group (when the signer granted one) and a shared
    /// keychain item (which works with a free Apple ID as long as the signature carries the team's
    /// keychain wildcard). The widget reads whichever is newer.
    static func save(_ payload: Payload) {
        var p = payload
        p.live = true
        guard let data = try? JSONEncoder().encode(p) else { return }
        defaults.set(data, forKey: key)
        lastKeychainStatus = SharedKeychain.write(data, account: "payload")
    }

    /// `live` is false when nothing from the app reached this process.
    static func load() -> Payload {
        let fromGroup = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        let fromKeychain = SharedKeychain.read(account: "payload").flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        switch (fromGroup, fromKeychain) {
        case let (g?, k?): return g.updated >= k.updated ? g : k
        case let (g?, nil): return g
        case let (nil, k?): return k
        default: return Payload()
        }
    }

    /// Where the payload came from this time — for the widget's heartbeat.
    static func source() -> String {
        let g = defaults.data(forKey: key) != nil && groupGranted
        let k = SharedKeychain.read(account: "payload") != nil
        return g && k ? "group+keychain" : g ? "group" : k ? "keychain" : "none"
    }

    // MARK: Ticked off from the widget

    /// A tap on a widget's ✓ button, waiting for the app to apply it to the vault.
    struct Pending: Codable, Hashable {
        var id: String
        var routine: Bool
        var at: Date
    }

    static func pending() -> [Pending] {
        let a = defaults.data(forKey: "widget.pending").flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? []
        let b = SharedKeychain.read(account: "pending").flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? []
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.id).inserted }
    }

    static func setPending(_ list: [Pending]) {
        let data = (try? JSONEncoder().encode(list)) ?? Data("[]".utf8)
        defaults.set(data, forKey: "widget.pending")
        SharedKeychain.write(data, account: "pending")
    }

    /// Shows the tick straight away and queues it for the app, so the button works even when iOS
    /// doesn't wake the app up.
    static func tickLocally(id: String, routine: Bool) {
        var list = pending()
        if !list.contains(where: { $0.id == id }) { list.append(Pending(id: id, routine: routine, at: Date())) }
        setPending(list)

        var p = load()
        guard p.live else { return }
        p.items.removeAll { $0.id == id }
        if let i = p.routines.firstIndex(where: { $0.id == id }), !p.routines[i].done {
            p.routines[i].done = true
            p.doneToday = min(p.totalToday, p.doneToday + 1)
        }
        p.updated = Date()
        save(p)
    }

    // MARK: Heartbeat — the widget says "I ran, and here's what I saw"

    struct Heartbeat: Codable {
        var at: Date
        var source: String
        var items: Int
        var routines: Int
        var group: String
        var groupGranted: Bool
        var team: String
    }

    static func beat(_ p: Payload) {
        let hb = Heartbeat(at: Date(), source: source(), items: p.items.count, routines: p.routines.count,
                           group: appGroup, groupGranted: groupGranted, team: Provision.teamID ?? "-")
        guard let data = try? JSONEncoder().encode(hb) else { return }
        defaults.set(data, forKey: "widget.heartbeat")
        _ = SharedKeychain.write(data, account: "heartbeat")
    }

    static func lastBeat() -> Heartbeat? {
        let a = defaults.data(forKey: "widget.heartbeat").flatMap { try? JSONDecoder().decode(Heartbeat.self, from: $0) }
        let b = SharedKeychain.read(account: "heartbeat").flatMap { try? JSONDecoder().decode(Heartbeat.self, from: $0) }
        return [a, b].compactMap { $0 }.max { $0.at < $1.at }
    }
}

// MARK: - What the signer actually gave this install

/// Reads the provisioning profile Sideloadly/AltStore put in the bundle. The widget extension lives in
/// PlugIns/ inside the app, so it tries its own profile first and then the host app's, two folders up.
enum Provision {
    static let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
    static var hostURL: URL {
        isExtension ? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent() : Bundle.main.bundleURL
    }
    static var hostBundleID: String? {
        isExtension ? Bundle(url: hostURL)?.bundleIdentifier : Bundle.main.bundleIdentifier
    }

    static let profile: [String: Any] = {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") { urls.append(u) }
        urls.append(hostURL.appendingPathComponent("embedded.mobileprovision"))
        for url in urls {
            guard let raw = try? Data(contentsOf: url),
                  let start = raw.range(of: Data("<?xml".utf8)),
                  let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex) else { continue }
            let xml = raw.subdata(in: start.lowerBound..<end.upperBound)
            if let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] {
                return plist
            }
        }
        return [:]
    }()

    static var entitlements: [String: Any] { profile["Entitlements"] as? [String: Any] ?? [:] }
    static var appGroups: [String] { entitlements["com.apple.security.application-groups"] as? [String] ?? [] }
    static var keychainGroups: [String] { entitlements["keychain-access-groups"] as? [String] ?? [] }
    static var teamID: String? {
        (profile["TeamIdentifier"] as? [String])?.first
            ?? (profile["ApplicationIdentifierPrefix"] as? [String])?.first
            ?? (entitlements["com.apple.developer.team-identifier"] as? String)
    }
    static var hasProfile: Bool { !profile.isEmpty }
}

// MARK: - Shared keychain item (the fallback when there's no App Group)

enum SharedKeychain {
    static let service = "com.mnlovo.saver.widget"

    /// Every app may use `TEAMID.<its own bundle id>`; a free-account signature usually carries
    /// `TEAMID.*` too, which lets the widget into the app's group. Both sides compute the same name.
    static var group: String? {
        guard let t = Provision.teamID, let b = Provision.hostBundleID else { return nil }
        return "\(t).\(b)"
    }

    private static func base(_ account: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let g = group { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> Int32 {
        let q = base(account)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add.merge(attrs) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    static func read(account: String) -> Data? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

#if canImport(ActivityKit)
struct ReminderActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var due: Date
    }
    var reminderID: String
    var title: String
    var icon: String
    var isArabic: Bool
    /// Start of the countdown window (for the progress bar).
    var start: Date = Date()
    var kindTitle: String = ""
    /// "Last 3 hours", "Last 30 min"… — how long the countdown runs, chosen per reminder.
    var badge: String = ""
}
#endif
