import Foundation
import UserNotifications
import WidgetKit
import ActivityKit
import EventKit

/// Escalating reminder plan:
///   3 days before → 2 days before → 1 day before →
///   last day: every N hours until due ("did you do it?") → at due time →
///   overdue: every 3 hours for 24h until you confirm it's done.
enum ReminderEngine {
    static let category = "AYN_REMINDER"
    static let maxPending = 60

    struct Planned: Hashable {
        var date: Date
        var title: String
        var body: String
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: tr("✅ خلصتها", "✅ Done"), options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: tr("⏰ ذكّرني بعد ساعة", "⏰ Remind me in 1h"), options: [])
        let cat = UNNotificationCategory(identifier: category, actions: [done, snooze], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func plan(for r: Reminder, now: Date = Date()) -> [Planned] {
        guard !r.done else { return [] }
        let name = r.displayTitle
        var out: [Planned] = []
        let cal = Calendar.current

        for days in [3, 2, 1] {
            let d = r.due.addingTimeInterval(-Double(days) * 86400)
            let body: String
            switch days {
            case 3: body = tr("باقي ٣ أيام على التسليم. خطط لها من الحين 💪", "3 days left. Plan it now 💪")
            case 2: body = tr("باقي يومين! لا تخليها لآخر لحظة.", "2 days left! Don't leave it to the last minute.")
            default: body = tr("باقي يوم واحد ⚠️ بكرة آخر يوم.", "1 day left ⚠️ Tomorrow is the last day.")
            }
            out.append(Planned(date: d, title: name, body: body))
        }

        // Last day nagging window
        let startOfDay = cal.startOfDay(for: r.due)
        var windowStart = startOfDay.addingTimeInterval(8 * 3600)
        if windowStart >= r.due { windowStart = r.due.addingTimeInterval(-6 * 3600) }
        let step = Double(max(1, r.nagHours)) * 3600
        var t = windowStart
        while t < r.due.addingTimeInterval(-15 * 60) {
            out.append(Planned(date: t, title: name,
                               body: tr("اليوم آخر يوم! سويتها؟ اضغط «خلصتها» عشان أقفل المهمة.",
                                        "Today is the last day! Done yet? Tap “Done” to close it.")))
            t = t.addingTimeInterval(step)
        }
        out.append(Planned(date: r.due, title: name,
                           body: tr("⏰ انتهى الوقت الحين. سويتها؟", "⏰ Time's up now. Did you do it?")))

        // Overdue follow-ups
        for h in stride(from: 3, through: 24, by: 3) {
            out.append(Planned(date: r.due.addingTimeInterval(Double(h) * 3600), title: name,
                               body: tr("المهمة متأخرة. إذا خلصتها أكّد عشان أقفلها ✅",
                                        "This is overdue. Confirm when done so I can close it ✅")))
        }

        if let s = r.snoozedUntil, s > now {
            out.append(Planned(date: s, title: name, body: tr("رجعت أذكّرك 👀 سويتها؟", "Reminding you again 👀 Done yet?")))
            // Drop anything between now and the snooze time
            out = out.filter { $0.date >= s || $0.date == s }
        }
        return out.filter { $0.date > now.addingTimeInterval(5) }.sorted { $0.date < $1.date }
    }

    /// Rebuilds every pending notification from both vault spaces (iOS allows 64 pending).
    static func rescheduleAll() {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var all: [(Planned, Reminder, VaultSpace)] = []
        for space in VaultSpace.allCases where VaultStorage.exists(space) {
            for r in RemindersStore.load(space) {
                for p in plan(for: r, now: now) { all.append((p, r, space)) }
            }
        }
        all.sort { $0.0.date < $1.0.date }
        center.removeAllPendingNotificationRequests()
        for (i, item) in all.prefix(maxPending).enumerated() {
            let (p, r, space) = item
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = UNNotificationSound(named: UNNotificationSoundName("notify.wav"))
            content.categoryIdentifier = category
            content.threadIdentifier = r.id.uuidString
            content.userInfo = ["rid": r.id.uuidString, "space": space.rawValue]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "rem.\(r.id.uuidString).\(i)", content: content, trigger: trigger))
        }
        WidgetBridge.update()
    }

    static func handleAction(_ action: String, userInfo: [AnyHashable: Any]) {
        guard let rid = (userInfo["rid"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let space = VaultSpace(rawValue: userInfo["space"] as? String ?? "real") ?? .real
        switch action {
        case "DONE":
            RemindersStore.update(space, rid) { $0.done = true; $0.doneAt = Date(); $0.snoozedUntil = nil }
        case "SNOOZE":
            RemindersStore.update(space, rid) { $0.snoozedUntil = Date().addingTimeInterval(3600) }
        default:
            return
        }
        rescheduleAll()
        LiveActivityManager.sync()
    }

    // MARK: Calendar

    static func addToCalendar(_ r: Reminder) async -> String? {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return nil }
        let ev = EKEvent(eventStore: store)
        ev.title = r.displayTitle
        ev.notes = r.sensitivity == .secret ? nil : r.notes
        if r.kind == .appointment {
            ev.startDate = r.due
            ev.endDate = r.due.addingTimeInterval(3600)
        } else {
            ev.startDate = r.due.addingTimeInterval(-1800)
            ev.endDate = r.due
        }
        ev.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(ev, span: .thisEvent)
            return ev.eventIdentifier
        } catch {
            return nil
        }
    }
}

enum WidgetBridge {
    static func update() {
        let now = Date()
        let list = RemindersStore.load(.real)
            .filter { !$0.done && $0.due > now.addingTimeInterval(-86400) }
            .sorted { $0.due < $1.due }
            .prefix(5)
        let items = list.map {
            WidgetShared.Item(id: $0.id.uuidString,
                              title: $0.sensitivity == .secret ? tr("🔒 مهمة سرية", "🔒 Secret task") : $0.title,
                              due: $0.due, icon: $0.kind.icon, secret: $0.sensitivity == .secret)
        }
        WidgetShared.save(WidgetShared.Payload(items: Array(items), isArabic: AppLanguage.current == .ar, updated: now))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Last-day countdown in the Dynamic Island and on the Lock Screen.
enum LiveActivityManager {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "fx.liveActivity") as? Bool ?? true }

    static func sync() {
        let now = Date()
        let candidates = RemindersStore.load(.real)
            .filter { !$0.done && $0.due > now && $0.due.timeIntervalSince(now) < 86400 }
            .sorted { $0.due < $1.due }
        let target = enabled ? candidates.first : nil

        for act in Activity<ReminderActivityAttributes>.activities where act.attributes.reminderID != target?.id.uuidString {
            Task { await act.end(nil, dismissalPolicy: .immediate) }
        }
        guard let t = target, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if Activity<ReminderActivityAttributes>.activities.contains(where: { $0.attributes.reminderID == t.id.uuidString }) { return }
        let attrs = ReminderActivityAttributes(reminderID: t.id.uuidString,
                                               title: t.sensitivity == .secret ? tr("🔒 مهمة سرية", "🔒 Secret task") : t.title,
                                               icon: t.kind.icon,
                                               isArabic: AppLanguage.current == .ar)
        let content = ActivityContent(state: ReminderActivityAttributes.ContentState(due: t.due),
                                      staleDate: t.due.addingTimeInterval(3600))
        _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
    }
}
