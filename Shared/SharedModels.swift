import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Data shared between the app and the widget extension (App Group).
enum WidgetShared {
    static let appGroup = "group.com.mnlovo.saver"
    static let key = "widget.payload"
    static let kind = "SaverNextTasks"

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
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

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
