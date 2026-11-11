import Foundation
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
        let granted = provisionedGroups()
        if granted.contains(declaredGroup) { return declaredGroup }
        if let match = granted.first(where: { $0.lowercased().contains("saver") }) { return match }
        return granted.first ?? declaredGroup
    }()

    private static func provisionedGroups() -> [String] {
        // The widget extension lives in PlugIns/ inside the app, so try its own profile first and
        // then the host app's, two folders up.
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") { urls.append(u) }
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        urls.append(host.appendingPathComponent("embedded.mobileprovision"))
        for url in urls {
            guard let raw = try? Data(contentsOf: url),
                  let start = raw.range(of: Data("<?xml".utf8)),
                  let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex) else { continue }
            let xml = raw.subdata(in: start.lowerBound..<end.upperBound)
            guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
                  let ent = plist["Entitlements"] as? [String: Any],
                  let groups = ent["com.apple.security.application-groups"] as? [String], !groups.isEmpty else { continue }
            return groups
        }
        return []
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
    }

    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var due: Date
        var icon: String
        var secret: Bool
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
        return p
    }

    static func save(_ payload: Payload) {
        if let data = try? JSONEncoder().encode(payload) { defaults.set(data, forKey: key) }
    }

    static func load() -> Payload {
        guard let data = defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return Payload() }
        return p
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
