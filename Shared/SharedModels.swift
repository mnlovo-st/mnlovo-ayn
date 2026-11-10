import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Data shared between the app and the widget extension (App Group).
enum WidgetShared {
    static let appGroup = "group.com.mnlovo.saver"
    static let key = "widget.payload"
    static let kind = "SaverNextTasks"
    static let streakKind = "SaverStreak"
    static let subsKind = "SaverSubscriptions"
    static let openKind = "SaverQuickOpen"

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
}
#endif
